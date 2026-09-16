-- | The shared severity vocabulary used on both sides of the bridge.
--
--   hermod-recon's own JSON lines carry a capitalized @sev@ field
--   (@"Debug"@, @"Info"@, ..., @"Emergency"@); cardano-tracer's alarm
--   ingress wire format uses the /same/ eight-value vocabulary, but
--   lowercased (@"debug"@, @"info"@, ..., @"emergency"@). Rather than have
--   two incompatible Haskell types, this module defines one 'Severity' type
--   and two independent textual codecs for it, matching each side's casing
--   convention exactly.
module Hermod.AlarmBridge.Severity
  ( Severity (..)
  , severityFromHermodText
  , severityToWireText
  , severityFromWireText
  ) where

import           Data.Text (Text)
import qualified Data.Text as Text

-- | Ordered least to most severe, matching both hermod's and cardano-tracer's
--   severity vocabularies (itself following RFC 5424).
data Severity
  = Debug
  | Info
  | Notice
  | Warning
  | Error
  | Critical
  | Alert
  | Emergency
  deriving stock (Show, Eq, Ord, Enum, Bounded)

-- | Parse hermod-recon's own capitalized @sev@ field, e.g. @"Notice"@.
severityFromHermodText :: Text -> Maybe Severity
severityFromHermodText = \case
  "Debug"     -> Just Debug
  "Info"      -> Just Info
  "Notice"    -> Just Notice
  "Warning"   -> Just Warning
  "Error"     -> Just Error
  "Critical"  -> Just Critical
  "Alert"     -> Just Alert
  "Emergency" -> Just Emergency
  _           -> Nothing

-- | Render for cardano-tracer's alarm ingress wire format, e.g. @"notice"@.
severityToWireText :: Severity -> Text
severityToWireText = Text.toLower . Text.pack . show

-- | Parse the lowercase vocabulary: used both for cardano-tracer-facing
--   input (a @--rules@ YAML file's @severity:@ overrides, and
--   @--default-severity@ on the command line) since both describe the
--   *outgoing* alarm severity, not hermod's own @sev@ field.
severityFromWireText :: Text -> Maybe Severity
severityFromWireText t = case Text.toLower t of
  "debug"     -> Just Debug
  "info"      -> Just Info
  "notice"    -> Just Notice
  "warning"   -> Just Warning
  "error"     -> Just Error
  "critical"  -> Just Critical
  "alert"     -> Just Alert
  "emergency" -> Just Emergency
  _           -> Nothing
