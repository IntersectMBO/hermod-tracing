-- | An integration-ish test tying the bridge's classify pipeline to a real
--   scenario documented in this repo's own hermod-recon-framework fixtures:
--
--     * hermod-recon-framework/examples/cfgs/formulas.yaml -- formula index
--       2 is the Praos "since" invariant:
--       @☐ ᪲₁ (∀i ∈ ℤ. (¬ (NodeIsLeader{slot=i} ∨ NodeNotLeader{slot=i}) |¹ StartLeadershipCheck{slot=i}))@
--     * hermod-recon-framework/examples/extracts/fail-1.txt -- whose header
--       comment documents exactly why that formula is violated on that
--       trace: "NodeNotLeader{slot=5} follows StartLeadershipCheck{slot=4}
--       -- slot mismatch violates formula 2".
--
--   This test does not run hermod-recon or replay fail-1.txt itself (that
--   file's lines are the *input* trace hermod-recon evaluates, not its own
--   machine-format output). Instead, it hand-writes the small handful of
--   lines hermod-recon would actually emit on its own stdout while
--   evaluating that scenario -- matching the real
--   @Hermod.ReCon.TraceMessage@ wire schema (@formula@\/@relevance@\/@index@
--   for a FormulaNegativeOutcome, read straight from that module's
--   @forMachine@ instance) -- and pushes them through the bridge's real
--   decode + classify + deliver pipeline, substituting an in-memory
--   recording sink for the real HTTP socket.
module Hermod.AlarmBridge.Test.Integration (tests) where

import           Hermod.AlarmBridge.Classify
import           Hermod.AlarmBridge.Deliver (DeliverOne, DeliverResult (Delivered), defaultRetryPolicy,
                   deliverWithRetry)
import           Hermod.AlarmBridge.Envelope (HermodLine (..), decodeHermodLine)
import           Hermod.AlarmBridge.Rules (RuleOverride (..), RuleOverrides)
import           Hermod.AlarmBridge.Severity (Severity (..))

import qualified Data.Aeson as Aeson
import           Data.Aeson (Value, object, (.=))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import           Data.IORef
import qualified Data.Map.Strict as Map
import           Data.Maybe (mapMaybe)
import           Data.Text (Text)
import qualified Data.Text as Text
import           Data.Time.Format.ISO8601 (iso8601Show)
import           Test.Tasty
import           Test.Tasty.HUnit

-- | The Praos "since" formula's source text, from
--   hermod-recon-framework/examples/cfgs/formulas.yaml (formula index 2;
--   rendered here in plain ASCII rather than the file's own unicode
--   operators -- only that the text passed through verbatim is this
--   bridge's concern, not hermod-recon's own pretty-printer output).
formula2Text :: Text
formula2Text =
  "G (Since1 (not (NodeIsLeader{slot=i} or NodeNotLeader{slot=i})) StartLeadershipCheck{slot=i})"

-- | The relevance explanation, mirroring the header comment of
--   hermod-recon-framework/examples/extracts/fail-1.txt.
relevance2Text :: Text
relevance2Text =
  "NodeNotLeader{slot=5} follows StartLeadershipCheck{slot=4}: slot mismatch violates formula 2"

-- | Build one wire-format line exactly as documented in
--   "Hermod.AlarmBridge.Envelope".
jsonLine :: Text -> Text -> Text -> Value -> BS.ByteString
jsonLine at ns sev dat = BL.toStrict . Aeson.encode $ object
  [ "at"     .= at
  , "ns"     .= ns
  , "data"   .= dat
  , "sev"    .= sev
  , "thread" .= ("50" :: Text)
  , "host"   .= ("russoul-mac.local" :: Text)
  ]

-- | Line 1: hermod-recon announcing it is about to check formula #0 (an
--   unrelated formula from the same formulas.yaml). @FormulaStartCheck@ is
--   always Info and is never itself alarm-worthy.
line1StartCheck :: BS.ByteString
line1StartCheck = jsonLine "2025-12-01T07:06:48.001700Z" "FormulaStartCheck" "Info"
  (object ["formula" .= ("some other formula" :: Text), "index" .= (0 :: Int)])

-- | Line 2: formula #0 is satisfied on this trace -- also Info, also
--   dropped.
line2PositiveOutcome :: BS.ByteString
line2PositiveOutcome = jsonLine "2025-12-01T07:06:48.500000Z" "FormulaPositiveOutcome" "Info"
  (object ["formula" .= ("some other formula" :: Text), "index" .= (0 :: Int)])

-- | Line 3: the actual violation -- formula #2 (the "since" invariant) is
--   unsatisfied, for exactly the reason fail-1.txt's header comment
--   documents. hermod-recon emits a FormulaNegativeOutcome at Notice
--   severity (see @Hermod.ReCon.TraceMessage@'s @severityFor@), but that
--   severity is irrelevant to the bridge: any FormulaNegativeOutcome always
--   alarms, regardless of hlSev.
line3NegativeOutcome :: BS.ByteString
line3NegativeOutcome = jsonLine "2025-12-01T07:06:49.002000Z" "FormulaNegativeOutcome" "Notice"
  (object ["formula" .= formula2Text, "relevance" .= relevance2Text, "index" .= (2 :: Int)])

allLines :: [BS.ByteString]
allLines = [line1StartCheck, line2PositiveOutcome, line3NegativeOutcome]

-- | A --rules override for formula #2 that only renames the ruleId,
--   leaving severity/summary at their defaults -- exercising the rules
--   pipeline inside this same integration scenario.
overrides :: RuleOverrides
overrides = Map.fromList
  [ (2, RuleOverride { roRuleId = Just "praos-since-invariant", roSeverity = Nothing, roSummary = Nothing }) ]

decodeAllOrFail :: IO [HermodLine]
decodeAllOrFail = mapM (either assertFailure pure . decodeHermodLine) allLines

-- | The classified alarms from all three lines, in order -- expected to be
--   a single-element list (only line 3 alarms).
classifiedAlarms :: IO [IngressRequest]
classifiedAlarms = mapMaybe (classifyHermodLine overrides Error) <$> decodeAllOrFail

-- | An in-memory 'DeliverOne': records every request it's asked to deliver
--   and always reports success -- standing in for a real HTTP socket to
--   cardano-tracer.
recordingDeliverOne :: IORef [IngressRequest] -> DeliverOne
recordingDeliverOne ref req = modifyIORef' ref (++ [req]) >> pure Delivered

tests :: TestTree
tests = testGroup "Integration (hermod-recon-framework fixtures: formulas.yaml / fail-1.txt, formula #2)"
  [ testCase "all three hand-written lines decode as valid hermod-recon JSON" $ do
      decoded <- decodeAllOrFail
      length decoded @?= 3

  , testCase "only the FormulaNegativeOutcome (formula #2) line produces an alarm" $ do
      alarms <- classifiedAlarms
      length alarms @?= 1

  , testCase "the alarm's fields match fail-1.txt's documented scenario, with the --rules override applied" $ do
      decoded <- decodeAllOrFail
      let hl3    = decoded !! 2
          alarms = mapMaybe (classifyHermodLine overrides Error) decoded
      case alarms of
        [req] -> do
          irSourceEventId req @?= "hermod:2:" <> Text.pack (iso8601Show (hlAt hl3))
          irRaisedAt req      @?= hlAt hl3
          irRuleId req        @?= "praos-since-invariant" -- from the --rules override, not "hermod-formula-2"
          irSeverity req      @?= Error                   -- default-severity: the override didn't touch severity
          irSummary req       @?= "Formula #2 violated: " <> formula2Text
          irScope req         @?= Map.empty
          irLabels req        @?= Map.empty
          irDetails req       @?= Just (object
            [ "formulaIndex" .= (2 :: Int)
            , "formula"      .= formula2Text
            , "relevance"    .= relevance2Text
            ])
        other -> assertFailure ("expected exactly one alarm, got " <> show (length other))

  , testCase "delivering that alarm through the injectable sink (no real socket) records it exactly" $ do
      alarms <- classifiedAlarms
      case alarms of
        [req] -> do
          deliveredRef <- newIORef []
          ok <- deliverWithRetry defaultRetryPolicy (const (pure ())) (recordingDeliverOne deliveredRef) req
          ok @?= True
          delivered <- readIORef deliveredRef
          delivered @?= [req]
        other -> assertFailure ("expected exactly one alarm, got " <> show (length other))
  ]
