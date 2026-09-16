-- | Parses hermod-recon's documented JSON-lines wire format:
--
--   > {"at":"2025-12-01T07:06:48.001779Z","ns":"ReCon.FormulaNegativeOutcome",
--   >  "data":{"formula":"...","relevance":"...","index":3},
--   >  "sev":"Notice","thread":"50","host":"some-host"}
--
--   Each line on hermod-recon's stdout (when its own tracing config selects
--   a machine-format stdout backend) is one such JSON object. This module
--   deliberately hand-writes the 'FromJSON' instance rather than deriving it
--   generically: the wire field names (@at@, @ns@, @data@, @sev@, @thread@,
--   @host@) don't map cleanly onto idiomatic Haskell record field names.
--
--   This is intentionally the /only/ thing hermod-alarm-bridge knows about
--   hermod-recon: there is no dependency on hermod-recon-framework's
--   (unexported, app-local) 'Hermod.ReCon.TraceMessage' type or any of its
--   other internals.
module Hermod.AlarmBridge.Envelope
  ( HermodLine (..)
  , decodeHermodLine
  ) where

import           Hermod.AlarmBridge.Severity (Severity, severityFromHermodText)

import           Data.Aeson (FromJSON (..), Object, withObject, (.:))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import           Data.Text (Text)
import           Data.Time.Clock (UTCTime)

-- | One decoded line of hermod-recon's machine-format JSON output.
data HermodLine = HermodLine
  { hlAt     :: !UTCTime
    -- ^ ISO8601 UTC timestamp, e.g. from the @at@ field.
  , hlNs     :: !Text
    -- ^ Dot-joined namespace, e.g. @"ReCon.FormulaNegativeOutcome"@.
  , hlData   :: !Object
    -- ^ The free-form @data@ payload; shape depends on 'hlNs'.
  , hlSev    :: !Severity
  , hlThread :: !Text
  , hlHost   :: !Text
  }
  deriving stock (Show, Eq)

instance FromJSON HermodLine where
  parseJSON = withObject "HermodLine" $ \o -> do
    at'     <- o .: "at"
    ns      <- o .: "ns"
    d       <- o .: "data"
    sevText <- o .: "sev"
    sev     <- maybe
                 (fail ("Hermod.AlarmBridge.Envelope: unknown hermod severity: " <> show (sevText :: Text)))
                 pure
                 (severityFromHermodText sevText)
    thread  <- o .: "thread"
    host    <- o .: "host"
    pure HermodLine
      { hlAt = at', hlNs = ns, hlData = d, hlSev = sev, hlThread = thread, hlHost = host }

-- | Decode one line's worth of bytes (as read off a handle, without the
--   trailing newline) as a 'HermodLine'. Returns 'Left' with a human
--   readable parse error on failure -- used both for the startup
--   self-check and for skipping an isolated bad line later on.
decodeHermodLine :: BS.ByteString -> Either String HermodLine
decodeHermodLine = Aeson.eitherDecodeStrict'
