{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE DerivingStrategies  #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-# OPTIONS_GHC -Wno-partial-fields #-}

-- | Configuration types for the tracing pipeline: backend selection, forwarder
--   options, Prometheus tuning, and the per-namespace config map.
--
--   These types are consumed by @trace-dispatcher@ when wiring up backends and
--   applying a @TraceConfig@ to a live tracer net.  Tracer authors writing
--   'Cardano.Logging.Types.LogFormatting' or 'Cardano.Logging.Types.MetaTrace'
--   instances typically do not need this module directly.
module Cardano.Logging.Types.Config (
    FormatLogging(..)
  , ConfigOption(..)
  , ForwarderAddr(..)
  , ForwarderMode(..)
  , Verbosity(..)
  , TraceOptionForwarder(..)
  , defaultForwarder
  , BackendConfig(..)
  , parsePrometheusString
  , PrometheusSimpleRun(..)
  , prometheusSimpleNoOverrides
  , TraceConfig(..)
  , emptyTraceConfig
) where

import           Cardano.Logging.Types.Annotations (DetailLevel, SeverityF)

import qualified Data.Aeson       as AE
import           Data.Bool        (bool)
import           Data.Map.Strict  (Map)
import qualified Data.Map.Strict  as Map
import           Data.Text        (Text)
import qualified Data.Text        as T
import           Data.Text.Read   (decimal)
import           GHC.Generics
import           Network.HostName (HostName)
import           Network.Socket   (PortNumber)


data FormatLogging =
    HumanFormatColoured
  | HumanFormatUncoloured
  | MachineFormat
  deriving stock (Eq, Ord, Show)


-- | Configuration options for individual namespace elements.
data ConfigOption =
    -- | Severity level for a filter (default is Warning).
    ConfSeverity {severity :: SeverityF}
    -- | Detail level (default is DNormal).
  | ConfDetail {detail :: DetailLevel}
    -- | To which backend to pass.
    --   Default is @[EKGBackend, Forwarder, Stdout MachineFormat]@.
  | ConfBackend {backends :: [BackendConfig]}
    -- | Construct a limiter with limiting to the Double,
    --   which represents frequency in number of messages per second.
  | ConfLimiter {maxFrequency :: Double}
  deriving stock (Eq, Ord, Show, Generic)


-- | Which network address the forwarder connects to.
newtype ForwarderAddr
  = LocalSocket FilePath
  deriving stock (Eq, Ord, Show)

instance AE.FromJSON ForwarderAddr where
  parseJSON = AE.withObject "ForwarderAddr" $ \o ->
    LocalSocket <$> o AE..: "filePath"


-- | Whether the forwarder acts as client (Initiator) or server (Responder).
data ForwarderMode =
    -- | Forwarder works as a client: it initiates network connection with
    --   @cardano-tracer@ and/or another Haskell acceptor application.
    Initiator
    -- | Forwarder works as a server: it accepts network connection from
    --   @cardano-tracer@ and/or another Haskell acceptor application.
  | Responder
  deriving stock (Eq, Ord, Show, Generic)

instance AE.FromJSON ForwarderMode where
  parseJSON (AE.String "Initiator") = pure Initiator
  parseJSON (AE.String "Responder") = pure Responder
  parseJSON other = fail $ "Parsing of ForwarderMode failed."
                    <> "Unknown ForwarderMode: " <> show other


data Verbosity =
    -- | Maximum verbosity for all tracers in the forwarding protocols.
    Maximum
    -- | Minimum verbosity, the forwarding will work as silently as possible.
  | Minimum
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass AE.ToJSON

instance AE.FromJSON Verbosity where
  parseJSON (AE.String "Maximum") = pure Maximum
  parseJSON (AE.String "Minimum") = pure Minimum
  parseJSON other = fail $ "Parsing of Verbosity failed."
                    <> "Unknown Verbosity: " <> show other


data TraceOptionForwarder = TraceOptionForwarder {
    tofQueueSize         :: Word
  , tofVerbosity         :: Verbosity
  , tofMaxReconnectDelay :: Word
  } deriving stock (Eq, Ord, Show, Generic)

-- A word regarding queue size:
--
-- In case of a missing forwarding service consumer, traces messages will be
-- buffered. This mitigates short forwarding interruptions, or delays at startup
-- time.
--
-- The queue capacity should thus correlate to the expected log lines per second
-- given a particular tracing configuration - to avoid unnecessarily increasing
-- memory footprint.
--
-- The default values here are chosen to accomodate verbose tracing output
-- (i.e., buffering 1min worth of trace data given ~32 messages per second). A
-- config that results in less than 5 msgs per second should also provide
-- `TraceOptionForwarder` a queue size value considerably lower.
--
-- The queue size ties in with the max number of trace objects cardano-tracer
-- requests periodically, the default for that being 100. Here, the queue can
-- hold enough traces for 10 subsequent polls by cardano-tracer.
instance AE.FromJSON TraceOptionForwarder where
    parseJSON = AE.withObject "TraceOptionForwarder" $ \obj -> do
      -- Field "queueSize" is the new field that replaces and unifies
      -- both "connQueueSize" and "disconnQueueSize".
      maybeQueueSize <- obj AE..:? "queueSize"
      queueSize <- case maybeQueueSize of
                     (Just qs) -> return qs
                     Nothing   -> do
                       connQueueSize    <- obj AE..:? "connQueueSize"    AE..!= 128
                       disconnQueueSize <- obj AE..:? "disconnQueueSize" AE..!= 192
                       return $ max connQueueSize disconnQueueSize
      verbosity         <- obj AE..:? "verbosity"         AE..!= Minimum
      maxReconnectDelay <- obj AE..:? "maxReconnectDelay" AE..!= 45
      return $ TraceOptionForwarder queueSize verbosity maxReconnectDelay

instance AE.ToJSON TraceOptionForwarder where
  toJSON TraceOptionForwarder{..} = AE.object
    [ "queueSize"         AE..= tofQueueSize
    , "verbosity"         AE..= tofVerbosity
    , "maxReconnectDelay" AE..= tofMaxReconnectDelay
    ]

defaultForwarder :: TraceOptionForwarder
defaultForwarder = TraceOptionForwarder
  { tofQueueSize         = 192
  , tofVerbosity         = Minimum
  , tofMaxReconnectDelay = 45
  }


data BackendConfig =
    Forwarder
  | Stdout FormatLogging
  | EKGBackend
  | DatapointBackend
  | PrometheusSimple Bool (Maybe HostName) PortNumber
    -- ^ Boolean: drop suffixes like @_int@ in exposition; default: False.
  deriving stock (Eq, Ord, Show, Generic)

instance AE.ToJSON BackendConfig where
  toJSON Forwarder          = AE.String "Forwarder"
  toJSON DatapointBackend   = AE.String "DatapointBackend"
  toJSON EKGBackend         = AE.String "EKGBackend"
  toJSON (Stdout f)         = AE.String $ "Stdout " <> T.pack (show f)
  toJSON (PrometheusSimple s h p) = AE.String $ "PrometheusSimple "
    <> bool mempty "nosuffix" s
    <> maybe mempty ((<> " ") . T.pack) h
    <> T.pack (show p)

instance AE.FromJSON BackendConfig where
  parseJSON = AE.withText "BackendConfig" $ \case
    "Forwarder"                     -> pure Forwarder
    "EKGBackend"                    -> pure EKGBackend
    "DatapointBackend"              -> pure DatapointBackend
    "Stdout HumanFormatColoured"    -> pure $ Stdout HumanFormatColoured
    "Stdout HumanFormatUncoloured"  -> pure $ Stdout HumanFormatUncoloured
    "Stdout MachineFormat"          -> pure $ Stdout MachineFormat
    prometheus                      -> either fail pure (parsePrometheusString prometheus)

parsePrometheusString :: Text -> Either String BackendConfig
parsePrometheusString t = case T.words t of
  ["PrometheusSimple", portNo_] ->
    parsePort portNo_ >>= Right . PrometheusSimple False Nothing
  ["PrometheusSimple", arg, portNo_] ->
    parsePort portNo_ >>= Right .
      if validSuffix arg
        then PrometheusSimple (isNoSuffix arg) Nothing
        else PrometheusSimple False (Just $ T.unpack arg)
  ["PrometheusSimple", noSuff, host, portNo_]
    | validSuffix noSuff -> parsePort portNo_ >>= Right . PrometheusSimple (isNoSuffix noSuff) (Just $ T.unpack host)
    | otherwise          -> Left $ "invalid modifier for PrometheusSimple: " ++ show noSuff
  _ -> Left $ "unknown backend: " ++ show t
  where
    validSuffix s  = s == "suffix" || s == "nosuffix"
    isNoSuffix     = (== "nosuffix")
    parsePort p    = case decimal p of
      Right (portNo :: Word, rest)
        | T.null rest && 0 < portNo && portNo < 65536 -> Right $ fromIntegral portNo
      _ -> Left $ "invalid PrometheusSimple port: " ++ show p


-- | Parameter overrides for PrometheusSimple DoS protection.
data PrometheusSimpleRun = PrometheusSimpleRun
  { connTimeout      :: Maybe Word    -- ^ Release socket after inactivity (seconds); default: 22
  , connCountGlobal  :: Maybe Word    -- ^ Limit total number of incoming connections; default: 16
  , connCountPerHost :: Maybe Word    -- ^ Limit number of incoming connections from the same host; default: 5
  , connPerSecond    :: Maybe Double  -- ^ Limit requests per second (may be < 1.0); default: 8.0
  }
  deriving stock (Show, Generic)
  deriving anyclass (AE.FromJSON, AE.ToJSON)

prometheusSimpleNoOverrides :: PrometheusSimpleRun
prometheusSimpleNoOverrides = PrometheusSimpleRun Nothing Nothing Nothing Nothing


data TraceConfig = TraceConfig {
    -- | Options specific to a certain namespace.
    tcOptions                :: Map [Text] [ConfigOption]
    -- | Options for the forwarder.
  , tcForwarder              :: Maybe TraceOptionForwarder
    -- | Optional human-readable name of the node.
  , tcNodeName               :: Maybe Text
    -- | Optional prefix for metrics.
  , tcMetricsPrefix          :: Maybe Text
    -- | Optional resource trace frequency in milliseconds.
  , tcResourceFrequency      :: Maybe Int
    -- | Optional ledger metrics frequency in milliseconds.
  , tcLedgerMetricsFrequency :: Maybe Int
    -- | Optional parameter overrides for PrometheusSimple DoS protection.
  , tcPrometheusSimpleRun    :: Maybe PrometheusSimpleRun
  }
  deriving stock Show

emptyTraceConfig :: TraceConfig
emptyTraceConfig = TraceConfig
  { tcOptions                = Map.empty
  , tcForwarder              = Nothing
  , tcNodeName               = Nothing
  , tcMetricsPrefix          = Nothing
  , tcResourceFrequency      = Nothing
  , tcLedgerMetricsFrequency = Nothing
  , tcPrometheusSimpleRun    = Nothing
  }
