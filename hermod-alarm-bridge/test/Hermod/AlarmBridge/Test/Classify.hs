-- | Unit tests for "Hermod.AlarmBridge.Classify": the core mapping from a
--   decoded hermod-recon line (or a raw stderr line, or a child-process
--   exit) into zero-or-one outgoing 'IngressRequest'.
module Hermod.AlarmBridge.Test.Classify (tests) where

import           Hermod.AlarmBridge.Classify
import           Hermod.AlarmBridge.Envelope (HermodLine (..))
import           Hermod.AlarmBridge.Rules (RuleOverride (..), RuleOverrides, emptyRuleOverrides)
import           Hermod.AlarmBridge.Severity (Severity (..))

import qualified Data.Aeson as Aeson
import           Data.Aeson (Value (..), object, (.=))
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map
import           Data.Text (Text)
import qualified Data.Text as Text
import           Data.Time.Calendar (fromGregorian)
import           Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import           Data.Time.Format.ISO8601 (iso8601Show)
import           Test.Tasty
import           Test.Tasty.HUnit

-- | An arbitrary, fixed timestamp -- its exact value is unimportant; what
--   matters is that classification threads it through unchanged and formats
--   it consistently via 'iso8601Show'.
t0 :: UTCTime
t0 = UTCTime (fromGregorian 2025 12 1) (secondsToDiffTime (7 * 3600 + 6 * 60 + 49))

t0Text :: Text
t0Text = Text.pack (iso8601Show t0)

-- | A minimal 'HermodLine' builder: everything but @ns@, @data@ and @sev@
--   (the three fields classification actually branches on) is a fixed,
--   uninteresting default.
mkLine :: Text -> KeyMap.KeyMap Value -> Severity -> HermodLine
mkLine ns dat sev = HermodLine
  { hlAt = t0, hlNs = ns, hlData = dat, hlSev = sev, hlThread = "50", hlHost = "test-host" }

wireSeverityOf :: IngressRequest -> Maybe Value
wireSeverityOf req = case Aeson.toJSON req of
  Object o -> KeyMap.lookup "severity" o
  _        -> Nothing

-- | 'classifyHermodLine', asserting it produced an alarm (used by every test
--   below that expects a 'Just').
mustClassify :: RuleOverrides -> Severity -> HermodLine -> IO IngressRequest
mustClassify overrides defSev hl = case classifyHermodLine overrides defSev hl of
  Just req -> pure req
  Nothing  -> assertFailure "expected classifyHermodLine to produce a Just, got Nothing"

tests :: TestTree
tests = testGroup "Classify"
  [ formulaNegativeOutcomeTests
  , internalEventTests
  , droppedLineTests
  , stderrLineTests
  , reconStoppedTests
  , nsHasSuffixSegmentTests
  , truncateTextTests
  , defaultNamingTests
  ]

--------------------------------------------------------------------------------
-- FormulaNegativeOutcome
--------------------------------------------------------------------------------

-- | A realistic FormulaNegativeOutcome payload, in the shape
--   @Hermod.ReCon.TraceMessage.forMachine@ actually emits it: @formula@,
--   @relevance@ and @index@ (see hermod-recon-framework's own
--   @TraceMessage.hs@). The scenario text below mirrors the "since"-formula
--   violation documented at the top of
--   hermod-recon-framework/examples/extracts/fail-1.txt for formula index 2
--   in hermod-recon-framework/examples/cfgs/formulas.yaml.
negativeOutcomeData :: KeyMap.KeyMap Value
negativeOutcomeData = KeyMap.fromList
  [ ("formula", Aeson.toJSON formulaText)
  , ("relevance", Aeson.toJSON relevanceText)
  , ("index", Aeson.toJSON (2 :: Int))
  ]
 where
  formulaText   = "since(StartLeadershipCheck{slot=i}, NodeIsLeader{slot=i} or NodeNotLeader{slot=i})" :: Text
  relevanceText = "NodeNotLeader{slot=5} follows StartLeadershipCheck{slot=4}: slot mismatch" :: Text

formulaNegativeOutcomeTests :: TestTree
formulaNegativeOutcomeTests = testGroup "FormulaNegativeOutcome"
  [ testCase "maps to the expected IngressRequest, no --rules override" $ do
      let hl = mkLine "ReCon.FormulaNegativeOutcome" negativeOutcomeData Notice
      req <- mustClassify emptyRuleOverrides Error hl
      req @?= IngressRequest
        { irSourceEventId = "hermod:2:" <> t0Text
        , irRaisedAt      = t0
        , irRuleId        = "hermod-formula-2"
        , irSeverity      = Error -- the caller-supplied default, NOT hlSev (which was Notice)
        , irSummary       = "Formula #2 violated: since(StartLeadershipCheck{slot=i}, NodeIsLeader{slot=i} or NodeNotLeader{slot=i})"
        , irScope         = Map.empty
        , irLabels        = Map.empty
        , irDetails       = Just (object
            [ "formulaIndex" .= (2 :: Int)
            , "formula"      .= ("since(StartLeadershipCheck{slot=i}, NodeIsLeader{slot=i} or NodeNotLeader{slot=i})" :: Text)
            , "relevance"    .= ("NodeNotLeader{slot=5} follows StartLeadershipCheck{slot=4}: slot mismatch" :: Text)
            ])
        }

  , testCase "a full --rules override replaces ruleId, severity and summary" $ do
      let overrides :: RuleOverrides
          overrides = Map.fromList
            [ (2, RuleOverride
                    { roRuleId = Just "praos-since-invariant"
                    , roSeverity = Just Warning
                    , roSummary = Just "Node set leadership check invariant violated"
                    })
            ]
          hl = mkLine "ReCon.FormulaNegativeOutcome" negativeOutcomeData Notice
      req <- mustClassify overrides Error hl
      irRuleId req   @?= "praos-since-invariant"
      irSeverity req @?= Warning
      irSummary req  @?= "Node set leadership check invariant violated"

  , testCase "a partial --rules override (severity only) leaves ruleId/summary at their defaults" $ do
      let overrides :: RuleOverrides
          overrides = Map.fromList [ (2, RuleOverride Nothing (Just Critical) Nothing) ]
          hl = mkLine "ReCon.FormulaNegativeOutcome" negativeOutcomeData Notice
      req <- mustClassify overrides Error hl
      irRuleId req   @?= "hermod-formula-2"
      irSeverity req @?= Critical
      irSummary req  @?= defaultSummaryForFormula 2
                            "since(StartLeadershipCheck{slot=i}, NodeIsLeader{slot=i} or NodeNotLeader{slot=i})"

  , testCase "an override for a different formula index doesn't apply" $ do
      let overrides :: RuleOverrides
          overrides = Map.fromList [ (7, RuleOverride (Just "wrong-rule") Nothing Nothing) ]
          hl = mkLine "ReCon.FormulaNegativeOutcome" negativeOutcomeData Notice
      req <- mustClassify overrides Error hl
      irRuleId req @?= "hermod-formula-2"

  , testCase "a top-level namespace segment (no dotted prefix) still matches" $
      case classifyHermodLine emptyRuleOverrides Error
             (mkLine "FormulaNegativeOutcome" negativeOutcomeData Notice) of
        Just _  -> pure ()
        Nothing -> assertFailure "expected a Just for an un-prefixed FormulaNegativeOutcome namespace"

  , testCase "matches regardless of the line's own severity" $
      mapM_ (\sev ->
               case classifyHermodLine emptyRuleOverrides Error
                      (mkLine "ReCon.FormulaNegativeOutcome" negativeOutcomeData sev) of
                 Just _  -> pure ()
                 Nothing -> assertFailure ("expected a Just for FormulaNegativeOutcome at severity " <> show sev))
            [minBound .. maxBound]

  , testCase "a missing data.index falls back to -1 rather than dropping the violation" $ do
      let dataWithoutIndex = KeyMap.fromList
            [ ("formula", Aeson.toJSON ("f" :: Text)), ("relevance", Aeson.toJSON ("r" :: Text)) ]
          hl = mkLine "ReCon.FormulaNegativeOutcome" dataWithoutIndex Notice
      req <- mustClassify emptyRuleOverrides Error hl
      irRuleId req        @?= "hermod-formula--1"
      irSourceEventId req @?= "hermod:-1:" <> t0Text

  , testCase "a completely empty data object still produces an alarm, with blank formula/relevance" $ do
      let hl = mkLine "ReCon.FormulaNegativeOutcome" KeyMap.empty Notice
      req <- mustClassify emptyRuleOverrides Error hl
      irRuleId req  @?= "hermod-formula--1"
      irSummary req @?= "Formula #-1 violated: "
      irDetails req @?= Just (object ["formulaIndex" .= (-1 :: Int), "formula" .= ("" :: Text), "relevance" .= ("" :: Text)])
  ]

--------------------------------------------------------------------------------
-- Non-outcome, alarm-worthy-by-severity lines -> hermod-recon-internal
--------------------------------------------------------------------------------

internalEventTests :: TestTree
internalEventTests = testGroup "generic internal event (Warning/Error and above)"
  [ testCase "a Warning-severity Reflection line becomes a hermod-recon-internal alarm" $ do
      let dat = KeyMap.fromList [("unknownNamespace", Aeson.toJSON ("Foo.Bar" :: Text))]
          hl  = mkLine "ReCon.Reflection.UnknownNamespace" dat Warning
      req <- mustClassify emptyRuleOverrides Error hl
      irRuleId req        @?= internalRuleId
      irRuleId req        @?= "hermod-recon-internal"
      irSeverity req      @?= Warning
      irSourceEventId req @?= "hermod-internal:ReCon.Reflection.UnknownNamespace:" <> t0Text
      irSummary req       @?= "Hermod internal event: ReCon.Reflection.UnknownNamespace"
      irDetails req       @?= Just (Object dat)

  , testCase "severity is lowercased on the outgoing wire JSON" $ do
      let hl  = mkLine "ReCon.Reflection.Something" KeyMap.empty Warning
      req <- mustClassify emptyRuleOverrides Error hl
      wireSeverityOf req @?= Just (Aeson.toJSON ("warning" :: Text))

  , testCase "an Error-severity line is also picked up, lowercased to \"error\"" $ do
      let hl  = mkLine "ReCon.Reflection.Something" KeyMap.empty Error
      req <- mustClassify emptyRuleOverrides Error hl
      irSeverity req @?= Error
      wireSeverityOf req @?= Just (Aeson.toJSON ("error" :: Text))

  , testCase "Critical/Alert/Emergency lines are picked up too" $
      mapM_ (\sev ->
               case classifyHermodLine emptyRuleOverrides Error (mkLine "ReCon.Reflection.X" KeyMap.empty sev) of
                 Just req -> irSeverity req @?= sev
                 Nothing  -> assertFailure ("expected a Just at severity " <> show sev))
            [Critical, Alert, Emergency]

  , testCase "--rules overrides never apply to a generic internal event" $ do
      let overrides = Map.fromList [ (0, RuleOverride (Just "should-not-apply") Nothing Nothing) ]
          hl  = mkLine "ReCon.Reflection.Something" KeyMap.empty Warning
      req <- mustClassify overrides Error hl
      irRuleId req @?= "hermod-recon-internal"
  ]

--------------------------------------------------------------------------------
-- Dropped lines
--------------------------------------------------------------------------------

droppedLineTests :: TestTree
droppedLineTests = testGroup "dropped (Debug/Info/Notice, not a FormulaNegativeOutcome)"
  [ testCase ("a " <> show sev <> " non-outcome line produces nothing") $
      classifyHermodLine emptyRuleOverrides Error (mkLine "ReCon.FormulaPositiveOutcome" KeyMap.empty sev) @?= Nothing
  | sev <- [Debug, Info, Notice]
  ]

--------------------------------------------------------------------------------
-- stderr lines
--------------------------------------------------------------------------------

stderrLineTests :: TestTree
stderrLineTests = testGroup "classifyStderrLine"
  [ testCase "always becomes a hermod-recon-stderr Error alarm" $ do
      let req = classifyStderrLine 7 t0 "panic: stack overflow"
      irRuleId req        @?= stderrRuleId
      irRuleId req        @?= "hermod-recon-stderr"
      irSeverity req      @?= Error
      irSourceEventId req @?= "hermod-recon-stderr:7"
      irSummary req       @?= "panic: stack overflow"
      irDetails req       @?= Just (object ["rawLine" .= ("panic: stack overflow" :: Text)])
      irScope req         @?= Map.empty
      irLabels req        @?= Map.empty

  , testCase "the counter (not line content) drives sourceEventId uniqueness" $ do
      let reqA = classifyStderrLine 1 t0 "same message"
          reqB = classifyStderrLine 2 t0 "same message"
      irSourceEventId reqA @?= "hermod-recon-stderr:1"
      irSourceEventId reqB @?= "hermod-recon-stderr:2"
      assertBool "two occurrences of an identical line must not collapse to one id"
        (irSourceEventId reqA /= irSourceEventId reqB)

  , testCase "a long line is truncated in the summary, but kept verbatim in details.rawLine" $ do
      let longLine = Text.replicate 250 "x"
          req      = classifyStderrLine 1 t0 longLine
      Text.length (irSummary req) @?= 201 -- truncateText 200 appends one ellipsis char
      irDetails req @?= Just (object ["rawLine" .= longLine])
  ]

--------------------------------------------------------------------------------
-- hermod-recon-stopped
--------------------------------------------------------------------------------

reconStoppedTests :: TestTree
reconStoppedTests = testGroup "classifyReConStopped"
  [ testCase "reports the child's exit code" $ do
      let req = classifyReConStopped t0 1
      irRuleId req   @?= stoppedRuleId
      irRuleId req   @?= "hermod-recon-stopped"
      irSeverity req @?= Error
      irSummary req  @?= "hermod-recon exited with code 1"
      irDetails req  @?= Just (object ["exitCode" .= (1 :: Int)])

  , testCase "also fires for a synthetic exit code of 0 (--mode online, clean exit is anomalous)" $ do
      let req = classifyReConStopped t0 0
      irSummary req @?= "hermod-recon exited with code 0"
      irDetails req @?= Just (object ["exitCode" .= (0 :: Int)])
  ]

--------------------------------------------------------------------------------
-- Pure helpers
--------------------------------------------------------------------------------

nsHasSuffixSegmentTests :: TestTree
nsHasSuffixSegmentTests = testGroup "nsHasSuffixSegment"
  [ testCase "matches a dotted namespace ending in the segment" $
      nsHasSuffixSegment "FormulaNegativeOutcome" "ReCon.FormulaNegativeOutcome" @?= True
  , testCase "matches an un-dotted (top-level) namespace equal to the segment" $
      nsHasSuffixSegment "FormulaNegativeOutcome" "FormulaNegativeOutcome" @?= True
  , testCase "does not match a namespace ending in something else" $
      nsHasSuffixSegment "FormulaNegativeOutcome" "ReCon.FormulaPositiveOutcome" @?= False
  , testCase "does not match a namespace merely containing the segment mid-path" $
      nsHasSuffixSegment "FormulaNegativeOutcome" "ReCon.FormulaNegativeOutcome.Extra" @?= False
  , testCase "an empty namespace never matches a non-empty segment" $
      nsHasSuffixSegment "FormulaNegativeOutcome" "" @?= False
  ]

truncateTextTests :: TestTree
truncateTextTests = testGroup "truncateText"
  [ testCase "text no longer than the limit is left unchanged" $
      truncateText 5 "abcde" @?= "abcde"
  , testCase "text shorter than the limit is left unchanged" $
      truncateText 5 "ab" @?= "ab"
  , testCase "text longer than the limit is cut and gets an ellipsis appended" $
      truncateText 3 "abcdef" @?= "abc\x2026"
  , testCase "an empty limit still just appends the ellipsis" $
      truncateText 0 "abc" @?= "\x2026"
  , testCase "empty text is never truncated" $
      truncateText 0 "" @?= ""
  ]

defaultNamingTests :: TestTree
defaultNamingTests = testGroup "default naming helpers"
  [ testCase "defaultRuleIdForFormula" $ do
      defaultRuleIdForFormula 0 @?= "hermod-formula-0"
      defaultRuleIdForFormula 42 @?= "hermod-formula-42"
      defaultRuleIdForFormula (-1) @?= "hermod-formula--1"
  , testCase "defaultSummaryForFormula truncates a long formula to 160 characters" $ do
      let longFormula = Text.replicate 200 "y"
      defaultSummaryForFormula 3 longFormula @?=
        "Formula #3 violated: " <> Text.replicate 160 "y" <> "\x2026"
  , testCase "the well-known rule-id constants are distinct" $ do
      let ids = [internalRuleId, stderrRuleId, stoppedRuleId]
      Map.size (Map.fromList (zip ids ([0 ..] :: [Int]))) @?= length ids
  ]
