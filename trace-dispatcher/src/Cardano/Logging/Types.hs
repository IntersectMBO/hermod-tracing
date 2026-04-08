{-# LANGUAGE DeriveAnyClass           #-}
{-# LANGUAGE DeriveGeneric            #-}
{-# LANGUAGE DerivingStrategies       #-}
{-# LANGUAGE GADTs                    #-}
{-# LANGUAGE MultiWayIf               #-}
{-# LANGUAGE RankNTypes               #-}
{-# LANGUAGE RecordWildCards          #-}
{-# LANGUAGE ScopedTypeVariables      #-}
{-# LANGUAGE StandaloneKindSignatures #-}

{-# OPTIONS_GHC -Wno-partial-fields  #-}

module Cardano.Logging.Types (
    Trace(..)
  , LogFormatting(..)
  , Metric(..)
  , CounterIncrease(..)
  , getMetricName
  , LoggingContext(..)
  , emptyLoggingContext
  , Namespace(..)
  , nsReplacePrefix
  , nsReplaceInner
  , nsCast
  , nsPrependInner
  , nsGetComplete
  , nsGetTuple
  , nsRawToText
  , nsToText
  , MetaTrace(..)
  , DetailLevel(..)
  , Privacy(..)
  , SeverityS(..)
  , SeverityF(..)
  , ConfigOption(..)
  , FormatLogging(..)
  , ForwarderMode(..)
  , Verbosity(..)
  , TraceOptionForwarder(..)
  , defaultForwarder
  , ConfigReflection(..)
  , emptyConfigReflection
  , TraceConfig(..)
  , emptyTraceConfig
  , FormattedMessage(..)
  , TraceControl(..)
  , DocCollector(..)
  , LogDoc(..)
  , emptyLogDoc
  , BackendConfig(..)
  , Folding(..)
  , unfold
  , TraceObject(..)
  , PreFormatted(..)

  -- Re-exports from Cardano.Logging.Types.Configuration
  , HowToConnect(..)
) where

import           Cardano.Logging.Types.Configuration

import           Codec.Serialise                     (Serialise (..))
import           Control.DeepSeq                     (NFData)
import qualified Control.Tracer                      as T
import qualified Data.Aeson                          as AE
import           Data.Bool                           (bool)
import           Data.ByteString                     (ByteString)
import           Data.IORef
import           Data.Map.Strict                     (Map)
import qualified Data.Map.Strict                     as Map
import           Data.Set                            (Set)
import qualified Data.Set                            as Set
import           Data.Text                           as T (Text, intercalate,
                                                           null, pack,
                                                           singleton, unpack,
                                                           words)
import           Data.Text.Read                      as T (decimal)
import           Data.Time                           (UTCTime)
import           Data.Word                           (Word64)
import           GHC.Generics
import           Network.HostName                    (HostName)
import           Network.Socket                      (PortNumber)


-- | The Trace carries the underlying tracer Tracer from the contra-tracer package.
--   It adds a 'LoggingContext' and maybe a 'TraceControl' to every message.
newtype Trace m a = Trace
                            {unpackTrace :: T.Tracer m (LoggingContext, Either TraceControl a)}

-- | Contramap lifted to Trace
instance Monad m => T.Contravariant (Trace m) where
    contramap f (Trace tr) = Trace $
      T.contramap (\case
                      (lc, Right a) -> (lc, Right (f a))
                      (lc, Left tc) -> (lc, Left tc))
                  tr

-- | @tr1 <> tr2@ will run @tr1@ and then @tr2@ with the same input.
instance Monad m => Semigroup (Trace m a) where
  Trace a1 <> Trace a2 = Trace (a1 <> a2)

instance Monad m => Monoid (Trace m a) where
    mappend = (<>)
    mempty  = Trace T.nullTracer

-- | A unique identifier for every message, composed of text
-- A namespace can as well appear with the tracer name (e.g. "ChainDB.OpenEvent.OpenedDB"),
-- or more prefixes, in this moment it is a NamespaceOuter is used
data Namespace a = Namespace {
    nsPrefix :: [Text]
  , nsInner  :: [Text]}
  deriving stock Eq

instance Show (Namespace a) where
  show (Namespace [] []) = "emptyNS"
  show (Namespace [] nsInner') =
    unpack $ intercalate (singleton '.') nsInner'
  show (Namespace nsPrefix' nsInner') =
    unpack $ intercalate (singleton '.') (nsPrefix' ++ nsInner')

nsReplacePrefix :: [Text] -> Namespace a -> Namespace a
nsReplacePrefix o (Namespace _ i) =  Namespace o i

nsReplaceInner :: [Text] -> Namespace a -> Namespace a
nsReplaceInner i (Namespace o _) =  Namespace o i


nsPrependInner :: Text -> Namespace a -> Namespace b
nsPrependInner t (Namespace o i) =  Namespace o (t : i)

{-# INLINE nsCast #-}
nsCast :: Namespace a -> Namespace b
nsCast (Namespace o i) =  Namespace o i

nsGetComplete :: Namespace a -> [Text]
nsGetComplete (Namespace [] i) = i
nsGetComplete (Namespace o i)  = o ++ i

nsGetTuple :: Namespace a -> ([Text],[Text])
nsGetTuple (Namespace o i)  = (o,i)

nsRawToText :: ([Text], [Text]) -> Text
nsRawToText (ns1, ns2) = intercalate "." (ns1 ++ ns2)

nsToText :: Namespace a -> Text
nsToText (Namespace ns1 ns2) = intercalate "." (ns1 ++ ns2)

-- | Every message needs this to define how to represent itself
class LogFormatting a where
  -- | Machine readable representation with the possibility to represent with varying serialisations based on the detail level.
  -- This will result in JSON formatted log output.
  -- A @forMachine@ implementation is required for any instance definition.
  forMachine :: DetailLevel -> a -> AE.Object

  -- | Human-readable representation.
  -- The empty text indicates there's no specific human-readable formatting for that type - this is the default implementation.
  --
  -- If however human-readble output is explicitly requested, e.g. by logs, the system will fall back to a JSON object
  -- conforming to the @forMachine@ definition, and rendering it as a value in /{"data": <value>}`/
  -- Leaving out @forHuman@ in some instance definition will not lead to loss of log information that way.
  forHuman :: a -> Text
  forHuman _v = ""

  -- | Metrics representation.
  -- The default indicates that no metric is based on trace occurrences of that type.
  asMetrics :: a -> [Metric]
  asMetrics _v = []


class MetaTrace a where
  namespaceFor  :: a -> Namespace a

  severityFor   :: Namespace a -> Maybe a -> Maybe SeverityS

  privacyFor    :: Namespace a -> Maybe a -> Maybe Privacy
  privacyFor _  _ =  Just Public

  detailsFor    :: Namespace a -> Maybe a -> Maybe DetailLevel
  detailsFor _  _ =  Just DNormal

  documentFor   :: Namespace a -> Maybe Text

  metricsDocFor :: Namespace a -> [(Text,Text)]
  metricsDocFor _ = []

  allNamespaces :: [Namespace a]

-- | This type defines metrics, and how to update them.
--
--   The @Text@ field always contains the metric name.
--   Metric names are recommended to conform to the [Prometheus data model](https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels).
--   If you want to structure your metrics in namespaces, please use a dot separator, such as @"name.space.metricName"@.
--
--   Example, defining three metrics based on the occurrence of a single trace event:
--
-- > data Trace = BatchProcessed { batchSize :: Int }
-- >
-- > instance LogFormatting Trace where
-- >   asMetrics (BatchProcessed size) =
-- >     [ IntM     "batch.current" (fromIntegral size)              -- element count of the most recent batch
-- >     , CounterM "batchesTotal"  CounterIncrement                 -- total batches processed
-- >     , CounterM "batch.total"   (CounterAdd $ fromIntegral size) -- total elements processed
-- >     ]
--
data Metric
  -- | An integer gauge metric.
  --   Gauges are variable values.
    = IntM Text Integer
  -- | A floating-point gauge metric.
  --   Gauges are variable values.
    | DoubleM Text Double
  -- | A counter metric.
  --   Counters are non-negative, monotonically increasing values.
    | CounterM Text CounterIncrease
  -- | A label set containing the specified key-value pairs.
  --   The OpenMetrics standard permits empty label sets; the value of this labeled metric will always be "1".
  --
  --   For instance, a @LabelM "foo" [("key1", "value1"), ("key2", "value2")]@
  --   will be exposed as /"foo{key1=\"value1\",key2=\"value2\"} 1"/
    | LabelM Text [(Text, Text)]
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData


getMetricName :: Metric -> Text
getMetricName (IntM name _)     = name
getMetricName (DoubleM name _)  = name
getMetricName (CounterM name _) = name
getMetricName (LabelM name _)   = name

-- | Excplicit type on how to update a @CounterM@ metric (which may never decrease).
data CounterIncrease
  -- | Increment the counter by one
  = CounterIncrement
  -- | Increase the counter by some value
  | CounterAdd Word64
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | Context any log message carries
data LoggingContext = LoggingContext {
    lcNSInner  :: [Text]
  , lcNSPrefix :: [Text]
  , lcSeverity :: Maybe SeverityS
  , lcPrivacy  :: Maybe Privacy
  , lcDetails  :: Maybe DetailLevel
  }
  deriving stock
    (Show) -- TODO: Generic)
  --deriving anyclass
  --   Serialise

emptyLoggingContext :: LoggingContext
emptyLoggingContext = LoggingContext [] [] Nothing Nothing Nothing


-- | The detail level facilitates rendering the same trace value to messages with varying verbosities in its @instance LogFormatting@.
data DetailLevel =
      DMinimal
    | DNormal
    | DDetailed
    | DMaximum
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)
  deriving anyclass (AE.FromJSON, NFData)

instance AE.ToJSON DetailLevel where
  toEncoding = AE.genericToEncoding AE.defaultOptions

instance Serialise DetailLevel where
  encode = encode . fromEnum
  decode = decode >>= \val ->
    if val >= 0 && val <= 3
      then pure $ toEnum val
      else fail $ "hermod.DetailLevel.decode: Unknown value: " ++ show val

-- | Privacy of a message. Default is Public
data Privacy =
      Confidential              -- ^ confidential information - handle with care
    | Public                    -- ^ can be public.
  deriving stock (Eq, Ord, Show, Enum, Bounded)
  -- , Generic)
  -- TODO: deriving anyclass Serialise

-- | Severity of a message. These are defined alongside message namespaces in an @instance MetaTrace@.
--
-- The severities and their semantics adhere to those defined in the [Syslog Protocol](https://www.rfc-editor.org/rfc/rfc5424#section-6.2.1).
data SeverityS
    = Debug                   -- ^ Debug messages
    | Info                    -- ^ Informational - confirmation the program is working as expected
    | Notice                  -- ^ Normal, but significant conditions - may require special handling
    | Warning                 -- ^ General Warnings
    | Error                   -- ^ General Errors
    | Critical                -- ^ Severe situations
    | Alert                   -- ^ Take immediate action
    | Emergency               -- ^ System is unusable
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded, Generic)
  deriving anyclass (AE.FromJSON, NFData)

instance AE.ToJSON SeverityS where
    toEncoding = AE.genericToEncoding AE.defaultOptions

instance Serialise SeverityS where
  -- This ensures the binary representation is identical to the Syslog Protocol's numerical code
  encode = encode . (7 -) . fromEnum
  decode = decode >>= \val ->
    if val >= 0 && val <= 7
      then pure $ toEnum $ 7 - val
      else fail $ "hermod.SeverityS.decode: Unknown value: " ++ show val

-- | Severity for a filter. These are supplied by a concrete configuration of how to filter the entire message namespace at runtime.
--
-- @Nothing@ means: filter everything ('Silence').
--
-- @Just severity@ means: render messages with @SeverityS >= severity@.
newtype SeverityF = SeverityF (Maybe SeverityS)
  deriving stock Eq

instance Enum SeverityF where
  toEnum 8 = SeverityF Nothing
  toEnum i = SeverityF (Just (toEnum i))
  fromEnum (SeverityF Nothing)  = 8
  fromEnum (SeverityF (Just s)) = fromEnum s

instance AE.ToJSON SeverityF where
    toJSON (SeverityF (Just s)) = AE.String ((pack . show) s)
    toJSON (SeverityF Nothing)  = AE.String "Silence"

instance AE.FromJSON SeverityF where
    parseJSON (AE.String "Debug")     = pure (SeverityF (Just Debug))
    parseJSON (AE.String "Info")      = pure (SeverityF (Just Info))
    parseJSON (AE.String "Notice")    = pure (SeverityF (Just Notice))
    parseJSON (AE.String "Warning")   = pure (SeverityF (Just Warning))
    parseJSON (AE.String "Error")     = pure (SeverityF (Just Error))
    parseJSON (AE.String "Critical")  = pure (SeverityF (Just Critical))
    parseJSON (AE.String "Alert")     = pure (SeverityF (Just Alert))
    parseJSON (AE.String "Emergency") = pure (SeverityF (Just Emergency))
    parseJSON (AE.String "Silence")  = pure (SeverityF Nothing)
    parseJSON invalid = fail $ "hermod.SeverityF.parseJSON: unknown severity: " <> show invalid

instance Ord SeverityF where
  compare (SeverityF (Just s1)) (SeverityF (Just s2)) = compare s1 s2
  compare (SeverityF Nothing) (SeverityF Nothing)     = EQ
  compare (SeverityF (Just _s1)) (SeverityF Nothing)  = LT
  compare (SeverityF Nothing) (SeverityF (Just _s2))  = GT

instance Show SeverityF where
  show (SeverityF (Just s)) = show s
  show (SeverityF Nothing)  = "Silence"


----------------------------------------------------------------
-- Configuration

data ConfigReflection = ConfigReflection {
    crSilent     :: IORef (Set [Text])
  , crNoMetrics  :: IORef (Set [Text])
  , crAllTracers :: IORef (Set [Text])
  }

emptyConfigReflection :: IO ConfigReflection
emptyConfigReflection  = do
    silence     <- newIORef Set.empty
    hasMetrics  <- newIORef Set.empty
    allTracers  <- newIORef Set.empty
    pure $ ConfigReflection silence hasMetrics allTracers

data FormattedMessage =
      FormattedHuman Bool Text
      -- ^ The bool specifies if the formatting includes colours
    | FormattedMachine Text
    | FormattedMetrics [Metric]
    | FormattedForwarder TraceObject
    | FormattedCBOR ByteString
  deriving stock (Eq, Show)


data PreFormatted = PreFormatted {
    pfTime             :: !UTCTime
  , pfNamespace        :: !Text
  , pfThreadId         :: !Text
  , pfForHuman         :: !(Maybe Text)
  , pfForMachineObject :: AE.Object
}

-- | Used as interface object for ForwarderTracer
data TraceObject = TraceObject {
    toHuman     :: !(Maybe Text)
  , toMachine   :: !Text
  , toNamespace :: ![Text]
  , toSeverity  :: !SeverityS
  , toDetails   :: !DetailLevel
  , toTimestamp :: !UTCTime
  , toHostname  :: !Text
  , toThreadId  :: !Text
} deriving stock
    (Eq, Show, Generic)
  -- ^ Instances for 'TraceObject' to forward it using 'trace-forward' library.
  deriving anyclass
    (Serialise, NFData)

-- |
data BackendConfig =
    Forwarder
  | Stdout FormatLogging
  | EKGBackend
  | DatapointBackend
  | PrometheusSimple Bool (Maybe HostName) PortNumber   -- boolean: drop suffixes like "_int" in exposition; default: False
  deriving stock (Eq, Ord, Show, Generic)

instance AE.ToJSON BackendConfig where
  toJSON Forwarder  = AE.String "Forwarder"
  toJSON DatapointBackend = AE.String "DatapointBackend"
  toJSON EKGBackend = AE.String "EKGBackend"
  toJSON (Stdout f) = AE.String $ "Stdout " <> (pack . show) f
  toJSON (PrometheusSimple s h p) = AE.String $ "PrometheusSimple "
    <> bool mempty "nosuffix" s
    <> maybe mempty ((<> " ") . pack) h
    <> (pack . show) p

instance AE.FromJSON BackendConfig where
  parseJSON = AE.withText "BackendConfig" $ \case
    "Forwarder"                     -> pure Forwarder
    "EKGBackend"                    -> pure EKGBackend
    "DatapointBackend"              -> pure DatapointBackend
    "Stdout HumanFormatColoured"    -> pure $ Stdout HumanFormatColoured
    "Stdout HumanFormatUncoloured"  -> pure $ Stdout HumanFormatUncoloured
    "Stdout MachineFormat"          -> pure $ Stdout MachineFormat
    prometheus                      -> either (fail . ("hermod.BackendConfig.parseJSON: " ++)) pure (parsePrometheusString prometheus)

parsePrometheusString :: Text -> Either String BackendConfig
parsePrometheusString t = case T.words t of
  ["PrometheusSimple", portNo_] ->
    parsePort portNo_ >>= Right . PrometheusSimple False Nothing
  ["PrometheusSimple", arg, portNo_] ->
    parsePort portNo_ >>= Right . if validSuffix arg then PrometheusSimple (isNoSuffix arg) Nothing else PrometheusSimple False (Just $ unpack arg)
  ["PrometheusSimple", noSuff, host, portNo_]
    | validSuffix noSuff  -> parsePort portNo_ >>= Right . PrometheusSimple (isNoSuffix noSuff) (Just $ unpack host)
    | otherwise           -> Left $ "invalid modifier for PrometheusSimple: " ++ show noSuff
  _
    -> Left $ "unknown backend: " ++ show t
  where
    validSuffix s = s == "suffix" || s == "nosuffix"
    isNoSuffix    = (== "nosuffix")
    parsePort p = case T.decimal p of
      Right (portNo :: Word, rest)
        | T.null rest && 0 < portNo && portNo < 65536 -> Right $ fromIntegral portNo
      _                                               -> failure
      where failure = Left $ "invalid PrometheusSimple port: " ++ show p

data FormatLogging =
    HumanFormatColoured
  | HumanFormatUncoloured
  | MachineFormat
  deriving stock (Eq, Ord, Show)

-- Configuration options for individual namespace elements
data ConfigOption =
    -- | Severity level for a filter (default is Warning)
    ConfSeverity {severity :: SeverityF}
    -- | Detail level (default is DNormal)
  | ConfDetail {detail :: DetailLevel}
  -- | To which backend to pass
  --   Default is [EKGBackend, Forwarder, Stdout MachineFormat]
  | ConfBackend {backends :: [BackendConfig]}
  -- | Construct a limiter with limiting to the Double,
  -- which represents frequency in number of messages per second
  | ConfLimiter {maxFrequency :: Double}
  deriving stock (Eq, Ord, Show, Generic)

data ForwarderMode =
    -- | Forwarder works as a client: it initiates network connection with
    -- 'cardano-tracer' and/or another Haskell acceptor application.
    Initiator
    -- | Forwarder works as a server: it accepts network connection from
    -- 'cardano-tracer' and/or another Haskell acceptor application.
  | Responder
  deriving stock (Eq, Ord, Show, Generic)

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
  parseJSON other                 = fail $ "Parsing of Verbosity failed."
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
                     -- If the new field was provided we use it.
                     (Just qs) -> return qs
                     -- Else we look for the deprecated fields.
                     Nothing   -> do
                       connQueueSize    <- obj AE..:? "connQueueSize"    AE..!= 128
                       disconnQueueSize <- obj AE..:? "disconnQueueSize" AE..!= 192
                       return $ max connQueueSize disconnQueueSize
      verbosity         <- obj AE..:? "verbosity"         AE..!= Minimum
      maxReconnectDelay <- obj AE..:? "maxReconnectDelay" AE..!= 45
      return $ TraceOptionForwarder queueSize verbosity maxReconnectDelay

instance AE.ToJSON TraceOptionForwarder where
  toJSON TraceOptionForwarder{..} = AE.object
    [
      "queueSize"         AE..= tofQueueSize,
      "verbosity"         AE..= tofVerbosity,
      "maxReconnectDelay" AE..= tofMaxReconnectDelay
    ]

defaultForwarder :: TraceOptionForwarder
defaultForwarder = TraceOptionForwarder {
    tofQueueSize           = 192
  , tofVerbosity           = Minimum
  , tofMaxReconnectDelay   = 45
}

instance AE.FromJSON ForwarderMode where
  parseJSON (AE.String "Initiator") = pure Initiator
  parseJSON (AE.String "Responder") = pure Responder
  parseJSON other                   = fail $ "Parsing of ForwarderMode failed."
                        <> "Unknown ForwarderMode: " <> show other

data TraceConfig = TraceConfig {
     -- | Options specific to a certain namespace
    tcOptions                :: Map.Map [Text] [ConfigOption]
     -- | Options for the forwarder
  , tcForwarder              :: Maybe TraceOptionForwarder
    -- | Optional human-readable name of the node.
  , tcNodeName               :: Maybe Text
    -- | Optional prefix for metrics.
  , tcMetricsPrefix          :: Maybe Text
    -- | Optional resource trace frequency in milliseconds.
  , tcResourceFrequency      :: Maybe Int
    -- | Optional ledger metrics frequency in milliseconds.
  , tcLedgerMetricsFrequency :: Maybe Int
    -- | Optional parameter overrides for PrometheusSimple DoS protection
  , tcPrometheusSimpleRun    :: Maybe PrometheusSimpleRun
  }
  deriving stock Show

emptyTraceConfig :: TraceConfig
emptyTraceConfig = TraceConfig {
    tcOptions = Map.empty
  , tcForwarder = Nothing
  , tcNodeName = Nothing
  , tcMetricsPrefix = Nothing
  , tcResourceFrequency = Nothing
  , tcLedgerMetricsFrequency = Nothing
  , tcPrometheusSimpleRun = Nothing
  }

---------------------------------------------------------------------------
-- Control and Documentation

-- | When configuring a net of tracers, it should be run with Config on all
-- entry points first, and then with TCOptimize. When reconfiguring it needs to
-- run TCReset followed by Config followed by TCOptimize
data TraceControl where
    TCReset       :: TraceControl
    TCConfig      :: TraceConfig -> TraceControl
    TCOptimize    :: ConfigReflection -> TraceControl
    TCDocument    :: Int -> DocCollector -> TraceControl

newtype DocCollector = DocCollector (IORef (Map Int LogDoc))

data LogDoc = LogDoc {
    ldDoc           :: !Text
  , ldMetricsDoc    :: !(Map.Map Text Text)
  , ldNamespace     :: ![([Text],[Text])]
  , ldSeverityCoded :: !(Maybe SeverityS)
  , ldPrivacyCoded  :: !(Maybe Privacy)
  , ldDetailsCoded  :: !(Maybe DetailLevel)
  , ldDetails       :: ![DetailLevel]
  , ldBackends      :: ![BackendConfig]
  , ldFiltered      :: ![SeverityF]
  , ldLimiter       :: ![(Text, Double)]
  , ldSilent        :: Bool
} deriving stock (Eq, Show)

emptyLogDoc :: Text -> [(Text, Text)] -> LogDoc
emptyLogDoc d m = LogDoc d (Map.fromList m) [] Nothing Nothing Nothing [] [] [] [] False

-- | Type for the function foldTraceM from module Cardano/Logging/Trace
newtype Folding a b = Folding b

unfold :: Folding a b -> b
unfold (Folding b) = b

instance LogFormatting b => LogFormatting (Folding a b) where
  forMachine v (Folding b) =  forMachine v b
  forHuman (Folding b)     =  forHuman b
  asMetrics (Folding b)    =  asMetrics b
