-- | Parses the optional @--rules@ YAML file, which maps a hermod formula
--   index to overrides for the outgoing alarm's @ruleId@\/@severity@\/@summary@:
--
--   > 0:
--   >   ruleId: node-set-invariant
--   >   severity: warning
--   >   summary: "Node set contains an unexpected node"
--   > 2:
--   >   severity: critical
--
--   A missing index (or a missing @--rules@ flag entirely) falls back to
--   "Hermod.AlarmBridge.Classify"'s defaults.
module Hermod.AlarmBridge.Rules
  ( RuleOverride (..)
  , RuleOverrides
  , emptyRuleOverrides
  , lookupOverride
  , parseRuleOverrides
  , loadRuleOverrides
  ) where

import           Hermod.AlarmBridge.Severity (Severity, severityFromWireText)

import           Control.Exception (IOException, try)
import           Data.Aeson (FromJSON (..), withObject, (.:?))
import qualified Data.ByteString as BS
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Yaml as Yaml
import           Text.Read (readMaybe)

-- | Per-formula-index overrides; every field is optional and falls back to
--   "Hermod.AlarmBridge.Classify"'s built-in defaults when absent.
data RuleOverride = RuleOverride
  { roRuleId   :: !(Maybe Text)
  , roSeverity :: !(Maybe Severity)
  , roSummary  :: !(Maybe Text)
  }
  deriving stock (Show, Eq)

instance FromJSON RuleOverride where
  parseJSON = withObject "RuleOverride" $ \o -> do
    ruleId     <- o .:? "ruleId"
    sevText    <- o .:? "severity"
    severity'  <- traverse parseSeverityField sevText
    summary    <- o .:? "summary"
    pure RuleOverride { roRuleId = ruleId, roSeverity = severity', roSummary = summary }
   where
    parseSeverityField t =
      maybe (fail ("Hermod.AlarmBridge.Rules: unknown severity in rules file: " <> Text.unpack t))
            pure
            (severityFromWireText t)

type RuleOverrides = Map Int RuleOverride

emptyRuleOverrides :: RuleOverrides
emptyRuleOverrides = Map.empty

lookupOverride :: Int -> RuleOverrides -> Maybe RuleOverride
lookupOverride = Map.lookup

-- | Parse rule-override YAML bytes. JSON\/YAML object keys are always text
--   (even an unquoted YAML integer key like @0:@ is coerced to the text
--   key @"0"@ by the time it reaches an 'Data.Aeson.Object'), so this reads
--   the top level as @Map Text RuleOverride@ first and then parses each key
--   as an 'Int'. A key that isn't a valid integer is reported as an error
--   rather than silently dropped, so a typo (e.g. @"O"@ for @"0"@) doesn't
--   silently produce "no override" instead of the intended one.
parseRuleOverrides :: BS.ByteString -> Either String RuleOverrides
parseRuleOverrides bytes = do
  raw <- either (Left . show) Right
           (Yaml.decodeEither' bytes :: Either Yaml.ParseException (Map Text RuleOverride))
  let indexed = [ (readMaybe (Text.unpack k) :: Maybe Int, k, v) | (k, v) <- Map.toList raw ]
      bad     = [ k | (Nothing, k, _) <- indexed ]
      good    = [ (idx, v) | (Just idx, _, v) <- indexed ]
  if null bad
    then Right (Map.fromList good)
    else Left ("Hermod.AlarmBridge.Rules: rules file has non-integer formula index key(s): "
                 <> show bad)

-- | 'IO' wrapper around 'parseRuleOverrides' for a @--rules FILE@ argument.
--   A missing\/unreadable file is reported the same way as a malformed one
--   (@Left@ with a readable message) rather than crashing with a raw
--   'IOException' -- the caller ("Main") routes either case through a single
--   friendly @die@.
loadRuleOverrides :: FilePath -> IO (Either String RuleOverrides)
loadRuleOverrides fp = do
  readResult <- try (BS.readFile fp)
  pure $ case readResult of
    Left (ioErr :: IOException) ->
      Left ("Hermod.AlarmBridge.Rules: could not read rules file " <> fp <> ": " <> show ioErr)
    Right bytes -> parseRuleOverrides bytes
