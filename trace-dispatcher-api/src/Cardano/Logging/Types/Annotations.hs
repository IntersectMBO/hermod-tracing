{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Per-message annotation types: severity, privacy, detail level, namespace,
--   metrics, and the logging context that bundles them all.
--
--   These types are pure (no IO) and carry no configuration — they describe
--   individual trace messages, not the pipeline that processes them.
module Cardano.Logging.Types.Annotations (
    Namespace(..)
  , nsReplacePrefix
  , nsReplaceInner
  , nsCast
  , nsPrependInner
  , nsGetComplete
  , nsGetTuple
  , nsRawToText
  , nsToText
  , DetailLevel(..)
  , Privacy(..)
  , SeverityS(..)
  , SeverityF(..)
  , Metric(..)
  , getMetricName
  , LoggingContext(..)
  , emptyLoggingContext
) where

import           Codec.Serialise (Serialise (..))
import           Control.DeepSeq (NFData)
import qualified Data.Aeson      as AE
import           Data.Text       (Text)
import qualified Data.Text       as T
import           GHC.Generics


-- | A unique identifier for every message, composed of text.
--
--   A namespace can appear with a tracer name prefix
--   (e.g. @"ChainDB.OpenEvent.OpenedDB"@).
data Namespace a = Namespace {
    nsPrefix :: [Text]
  , nsInner  :: [Text]}
  deriving stock Eq

instance Show (Namespace a) where
  show (Namespace [] []) = "emptyNS"
  show (Namespace [] nsInner') =
    T.unpack $ T.intercalate (T.singleton '.') nsInner'
  show (Namespace nsPrefix' nsInner') =
    T.unpack $ T.intercalate (T.singleton '.') (nsPrefix' ++ nsInner')

nsReplacePrefix :: [Text] -> Namespace a -> Namespace a
nsReplacePrefix o (Namespace _ i) = Namespace o i

nsReplaceInner :: [Text] -> Namespace a -> Namespace a
nsReplaceInner i (Namespace o _) = Namespace o i

nsPrependInner :: Text -> Namespace a -> Namespace b
nsPrependInner t (Namespace o i) = Namespace o (t : i)

{-# INLINE nsCast #-}
nsCast :: Namespace a -> Namespace b
nsCast (Namespace o i) = Namespace o i

nsGetComplete :: Namespace a -> [Text]
nsGetComplete (Namespace [] i) = i
nsGetComplete (Namespace o i)  = o ++ i

nsGetTuple :: Namespace a -> ([Text], [Text])
nsGetTuple (Namespace o i) = (o, i)

nsRawToText :: ([Text], [Text]) -> Text
nsRawToText = nsToText . uncurry Namespace

nsToText :: Namespace a -> Text
nsToText (Namespace ns1 ns2) = T.intercalate "." (ns1 ++ ns2)


-- | The detail level facilitates rendering the same trace value to messages
--   with varying verbosities in its @instance LogFormatting@.
data DetailLevel =
      DMinimal
    | DNormal
    | DDetailed
    | DMaximum
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)
  deriving anyclass (Serialise, AE.FromJSON, NFData)

instance AE.ToJSON DetailLevel where
    toEncoding = AE.genericToEncoding AE.defaultOptions


-- | Privacy of a message. Default is 'Public'.
data Privacy =
      Confidential  -- ^ confidential information — handle with care
    | Public        -- ^ can be public
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)
  deriving anyclass Serialise


-- | Severity of a message. These are defined alongside message namespaces in
--   an @instance MetaTrace@.
--
--   The severities and their semantics adhere to those defined in the
--   [Syslog Protocol](https://www.rfc-editor.org/rfc/rfc5424#section-6.2.1).
data SeverityS
    = Debug      -- ^ Debug messages
    | Info       -- ^ Informational — confirmation the program is working as expected
    | Notice     -- ^ Normal, but significant conditions — may require special handling
    | Warning    -- ^ General Warnings
    | Error      -- ^ General Errors
    | Critical   -- ^ Severe situations
    | Alert      -- ^ Take immediate action
    | Emergency  -- ^ System is unusable
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded, Generic)
  deriving anyclass (AE.ToJSON, AE.FromJSON, Serialise, NFData)


-- | Severity for a filter. These are supplied by a concrete configuration of
--   how to filter the entire message namespace at runtime.
--
--   @Nothing@ means: filter everything ('Silence').
--
--   @Just severity@ means: render messages with @SeverityS >= severity@.
newtype SeverityF = SeverityF (Maybe SeverityS)
  deriving stock Eq

instance Enum SeverityF where
  toEnum 8 = SeverityF Nothing
  toEnum i = SeverityF (Just (toEnum i))
  fromEnum (SeverityF Nothing)  = 8
  fromEnum (SeverityF (Just s)) = fromEnum s

instance AE.ToJSON SeverityF where
    toJSON (SeverityF (Just s)) = AE.String (T.pack (show s))
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
    parseJSON (AE.String "Silence")   = pure (SeverityF Nothing)
    parseJSON invalid = fail $ "Parsing of filter Severity failed."
                          <> "Unknown severity: " <> show invalid

instance Ord SeverityF where
  compare (SeverityF (Just s1)) (SeverityF (Just s2)) = compare s1 s2
  compare (SeverityF Nothing)   (SeverityF Nothing)   = EQ
  compare (SeverityF (Just _))  (SeverityF Nothing)   = LT
  compare (SeverityF Nothing)   (SeverityF (Just _))  = GT

instance Show SeverityF where
  show (SeverityF (Just s)) = show s
  show (SeverityF Nothing)  = "Silence"


-- | This type defines metrics, and how to update them.
--
--   The @Text@ field always contains the metric name.
--   Metric names are recommended to conform to the
--   [Prometheus data model](https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels).
--   If you want to structure your metrics in namespaces, please use a dot separator,
--   such as @"name.space.metricName"@.
--
--   Example, defining three metrics based on the occurrence of a single trace event:
--
-- > data Trace = BatchProcessed { batchSize :: Int }
-- >
-- > instance LogFormatting Trace where
-- >   asMetrics (BatchProcessed size) =
-- >     [ IntM       "batch.current" (fromIntegral size)        -- element count of the most recent batch
-- >     , CounterM   "batchesTotal"  Nothing                    -- total batches processed (increment by 1)
-- >     , CounterM   "batch.total"   (Just $ fromIntegral size) -- total elements processed
-- >     ]
data Metric
    = IntM Text Integer
    -- ^ An integer gauge metric. Gauges are variable values.
    | DoubleM Text Double
    -- ^ A floating-point gauge metric. Gauges are variable values.
    | CounterM Text (Maybe Int)
    -- ^ A counter metric. Counters are non-negative, monotonically increasing values.
    | PrometheusM Text [(Text, Text)]
    -- ^ A label set containing the specified key-value pairs.
    --   The OpenMetrics standard permits empty label sets; the value of this labeled
    --   metric will always be @\"1\"@.
    --
    --   For instance, a @PrometheusM "foo" [("key1", "value1"), ("key2", "value2")]@
    --   will be exposed as /"foo{key1=\"value1\",key2=\"value2\"} 1"/
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

getMetricName :: Metric -> Text
getMetricName (IntM name _)        = name
getMetricName (DoubleM name _)     = name
getMetricName (CounterM name _)    = name
getMetricName (PrometheusM name _) = name


-- | Context every log message carries.
data LoggingContext = LoggingContext {
    lcNSInner  :: [Text]
  , lcNSPrefix :: [Text]
  , lcSeverity :: Maybe SeverityS
  , lcPrivacy  :: Maybe Privacy
  , lcDetails  :: Maybe DetailLevel
  }
  deriving stock (Show, Generic)
  deriving anyclass Serialise

emptyLoggingContext :: LoggingContext
emptyLoggingContext = LoggingContext [] [] Nothing Nothing Nothing
