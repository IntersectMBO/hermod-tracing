-- | Pure classification of hermod-recon lines (and raw stderr lines) into
--   zero-or-one outgoing 'IngressRequest', matching cardano-tracer's alarm
--   ingress wire contract:
--
--   > { "sourceEventId": "...", "raisedAt": "...", "ruleId": "...",
--   >   "severity": "warning", "summary": "...",
--   >   "scope": {}, "labels": {}, "details": { ... } }
--
--   See the module-level table in the design notes for the exact mapping;
--   summarised at each function below.
module Hermod.AlarmBridge.Classify
  ( IngressRequest (..)
  , classifyHermodLine
  , classifyStderrLine
  , classifyReConStopped
  , defaultRuleIdForFormula
  , defaultSummaryForFormula
  , internalRuleId
  , stderrRuleId
  , stoppedRuleId
  , nsHasSuffixSegment
  , truncateText
  ) where

import           Hermod.AlarmBridge.Envelope (HermodLine (..))
import           Hermod.AlarmBridge.Rules (RuleOverride (..), RuleOverrides, lookupOverride)
import           Hermod.AlarmBridge.Severity (Severity (..), severityToWireText)

import           Data.Aeson (Value (..), object, (.:), (.=))
import qualified Data.Aeson as Aeson
import           Data.Aeson.Types (parseMaybe)
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Maybe (fromMaybe)
import           Data.Text (Text)
import qualified Data.Text as Text
import           Data.Time.Clock (UTCTime)
import           Data.Time.Format.ISO8601 (iso8601Show)

-- | The producer-submitted alarm payload. Field names mirror
--   cardano-tracer's own @IngressRequest@ wire keys exactly (see
--   @cardano-tracer/docs/alarm-system-concept.md@ and
--   @Cardano.Tracer.Handlers.Alarms.Types@ in the cardano-node tree) --
--   this bridge defines its own copy of the /shape/ rather than depending
--   on that Haskell type, since hermod-alarm-bridge is built and shipped
--   independently of cardano-tracer.
data IngressRequest = IngressRequest
  { irSourceEventId :: !Text
  , irRaisedAt      :: !UTCTime
  , irRuleId        :: !Text
  , irSeverity      :: !Severity
  , irSummary       :: !Text
  , irScope         :: !(Map Text Text)
  , irLabels        :: !(Map Text Text)
  , irDetails       :: !(Maybe Value)
  }
  deriving stock (Show, Eq)

instance Aeson.ToJSON IngressRequest where
  toJSON IngressRequest{..} = object $
    [ "sourceEventId" .= irSourceEventId
    , "raisedAt"      .= irRaisedAt
    , "ruleId"        .= irRuleId
    , "severity"      .= severityToWireText irSeverity
    , "summary"       .= irSummary
    , "scope"         .= irScope
    , "labels"        .= irLabels
    ] ++ maybe [] (\d -> ["details" .= d]) irDetails

-- | The hermod namespace suffix that identifies a formula violation.
formulaNegativeOutcomeSegment :: Text
formulaNegativeOutcomeSegment = "FormulaNegativeOutcome"

-- | Does the last dot-joined segment of a namespace equal the given one?
--   E.g. @nsHasSuffixSegment "FormulaNegativeOutcome" "ReCon.FormulaNegativeOutcome" == True@.
--   Exported for testing the namespace-matching rule in isolation.
nsHasSuffixSegment :: Text -> Text -> Bool
nsHasSuffixSegment seg ns = case Text.splitOn "." ns of
  [] -> False
  segs -> last segs == seg

-- | hermod-recon lines whose own 'Hermod.AlarmBridge.Severity.Severity' is
--   alarm-worthy on its own (independent of namespace): everything at
--   Warning or above. Debug\/Info\/Notice lines that aren't a
--   FormulaNegativeOutcome are simply dropped.
alarmableSeverities :: [Severity]
alarmableSeverities = [Warning, Error, Critical, Alert, Emergency]

-- | Classify one decoded hermod-recon line into zero-or-one outgoing alarm.
--
--   * @ns@ ends with @FormulaNegativeOutcome@: a formula violation (see
--     'classifyFormulaNegativeOutcome').
--   * any other line with severity in @{Warning, Error, Critical, Alert,
--     Emergency}@: a framework-internal diagnostic (see
--     'classifyInternalEvent').
--   * anything else (Debug\/Info\/Notice, and not a FormulaNegativeOutcome):
--     dropped.
classifyHermodLine :: RuleOverrides -> Severity -> HermodLine -> Maybe IngressRequest
classifyHermodLine overrides defaultSev hl
  | nsHasSuffixSegment formulaNegativeOutcomeSegment (hlNs hl) =
      Just (classifyFormulaNegativeOutcome overrides defaultSev hl)
  | hlSev hl `elem` alarmableSeverities =
      Just (classifyInternalEvent hl)
  | otherwise =
      Nothing

defaultRuleIdForFormula :: Int -> Text
defaultRuleIdForFormula idx = "hermod-formula-" <> Text.pack (show idx)

defaultSummaryForFormula :: Int -> Text -> Text
defaultSummaryForFormula idx formula =
  "Formula #" <> Text.pack (show idx) <> " violated: " <> truncateText 160 formula

-- | @ruleId@/@severity@/@summary@ default (absent an override) for a
--   FormulaNegativeOutcome. @details@ is always
--   @{"formulaIndex", "formula", "relevance"}@, and @sourceEventId@ is
--   @"hermod:<index>:<at>"@ -- stable across retries of the same violation.
--
--   @data.index@ is documented as always present on a FormulaNegativeOutcome
--   line; if a malformed line is missing it anyway, this falls back to @-1@
--   rather than dropping a genuine formula violation on the floor.
classifyFormulaNegativeOutcome :: RuleOverrides -> Severity -> HermodLine -> IngressRequest
classifyFormulaNegativeOutcome overrides defaultSev hl = IngressRequest
  { irSourceEventId = "hermod:" <> Text.pack (show idx) <> ":" <> Text.pack (iso8601Show (hlAt hl))
  , irRaisedAt      = hlAt hl
  , irRuleId        = fromMaybe (defaultRuleIdForFormula idx) (override >>= roRuleId)
  , irSeverity      = fromMaybe defaultSev (override >>= roSeverity)
  , irSummary       = fromMaybe (defaultSummaryForFormula idx formula) (override >>= roSummary)
  , irScope         = Map.empty
  , irLabels        = Map.empty
  , irDetails       = Just $ object
      [ "formulaIndex" .= idx
      , "formula"       .= formula
      , "relevance"     .= relevance
      ]
  }
 where
  d          = hlData hl
  idx        = fromMaybe (-1)  (parseMaybe (.: "index") d    :: Maybe Int)
  formula    = fromMaybe ""    (parseMaybe (.: "formula") d  :: Maybe Text)
  -- "relevance" is a Haskell Show-rendered string, not structured JSON (a
  -- known upstream limitation of hermod-recon) -- passed through verbatim.
  relevance  = fromMaybe ""    (parseMaybe (.: "relevance") d :: Maybe Text)
  override   = lookupOverride idx overrides

internalRuleId :: Text
internalRuleId = "hermod-recon-internal"

-- | Any other hermod-recon line whose own severity is Warning or above
--   (typically a @...Reflection.TracerConsistencyWarnings@ or
--   @...Reflection.UnknownNamespace@ framework diagnostic). The full raw
--   @data@ object is passed through as @details@ unmodified.
classifyInternalEvent :: HermodLine -> IngressRequest
classifyInternalEvent hl = IngressRequest
  { irSourceEventId = "hermod-internal:" <> hlNs hl <> ":" <> Text.pack (iso8601Show (hlAt hl))
  , irRaisedAt      = hlAt hl
  , irRuleId        = internalRuleId
  , irSeverity      = hlSev hl
  , irSummary       = "Hermod internal event: " <> hlNs hl
  , irScope         = Map.empty
  , irLabels        = Map.empty
  , irDetails       = Just (Object (hlData hl))
  }

stderrRuleId :: Text
stderrRuleId = "hermod-recon-stderr"

-- | Classify one raw (never JSON-parsed) line read from hermod-recon's
--   stderr. @now@ and @counter@ are both supplied by the caller so this
--   stays pure and independently testable:
--
--   * @now@ stands in for "the current time" since a stderr line carries no
--     @at@ field of its own.
--   * @counter@ is a monotonic, caller-tracked sequence number (bumped once
--     per non-empty stderr line seen). It is folded into 'irSourceEventId'
--     so that distinct occurrences never collapse into a single idempotent
--     alarm on cardano-tracer's side purely because their text happened to
--     match (a crash loop repeating the same message must not look like
--     "one alarm raised once"). It deliberately does /not/ hash or embed
--     the full line content into the id, which would risk an unbounded
--     number of distinct alarms for a line that is unique per-byte (e.g.
--     one embedding its own timestamp) -- the caller-owned counter is the
--     single, bounded source of uniqueness here.
classifyStderrLine :: Int -> UTCTime -> Text -> IngressRequest
classifyStderrLine counter now rawLine = IngressRequest
  { irSourceEventId = "hermod-recon-stderr:" <> Text.pack (show counter)
  , irRaisedAt      = now
  , irRuleId        = stderrRuleId
  , irSeverity      = Error
  , irSummary       = truncateText 200 rawLine
  , irScope         = Map.empty
  , irLabels        = Map.empty
  , irDetails       = Just (object ["rawLine" .= rawLine])
  }

stoppedRuleId :: Text
stoppedRuleId = "hermod-recon-stopped"

-- | The synthetic alarm emitted once, right before the bridge itself exits,
--   when running in @--exec@ mode and hermod-recon's own exit is deemed
--   noteworthy (see "Hermod.AlarmBridge.ReConProcess.isOnlineMode" and
--   "Main" for when this is called).
classifyReConStopped :: UTCTime -> Int -> IngressRequest
classifyReConStopped now exitCode = IngressRequest
  { irSourceEventId = "hermod-recon-stopped:" <> Text.pack (iso8601Show now)
  , irRaisedAt      = now
  , irRuleId        = stoppedRuleId
  , irSeverity      = Error
  , irSummary       = "hermod-recon exited with code " <> Text.pack (show exitCode)
  , irScope         = Map.empty
  , irLabels        = Map.empty
  , irDetails       = Just (object ["exitCode" .= exitCode])
  }

-- | Truncate to at most @n@ characters, appending an ellipsis if anything
--   was cut off.
truncateText :: Int -> Text -> Text
truncateText n t
  | Text.length t <= n = t
  | otherwise           = Text.take n t <> "\x2026"
