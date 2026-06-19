{-# LANGUAGE DerivingStrategies #-}

-- | In-process documentation and reflection types.
--
--   'DocCollector' and 'LogDoc' are written by the doc-generator pass
--   (triggered by a 'Cardano.Logging.Types.TCDocument' control message) and
--   read back by tooling to produce human-readable documentation of a live
--   tracer configuration.
--
--   'ConfigReflection' is filled by the 'Cardano.Logging.Types.TCOptimize'
--   pass: it records which namespaces are silenced or metric-less so that the
--   optimised tracer can skip unnecessary work at runtime.
module Cardano.Logging.Types.Doc (
    ConfigReflection(..)
  , emptyConfigReflection
  , DocCollector(..)
  , LogDoc(..)
  , emptyLogDoc
) where

import           Cardano.Logging.Types.Annotations (DetailLevel, Privacy,
                   SeverityF, SeverityS)
import           Cardano.Logging.Types.Config      (BackendConfig)

import           Data.IORef
import           Data.Map.Strict                   (Map)
import qualified Data.Map.Strict                   as Map
import           Data.Set                          (Set)
import qualified Data.Set                          as Set
import           Data.Text                         (Text)


-- | Mutable sets written during the 'TCOptimize' pass.
--
--   After optimisation, 'crSilent' contains the namespaces whose effective
--   severity filter is @Silence@, and 'crNoMetrics' those that produce no
--   metrics — allowing tracers to skip formatting work for those paths.
data ConfigReflection = ConfigReflection {
    crSilent     :: IORef (Set [Text])
  , crNoMetrics  :: IORef (Set [Text])
  , crAllTracers :: IORef (Set [Text])
  }

emptyConfigReflection :: IO ConfigReflection
emptyConfigReflection = do
    silence    <- newIORef Set.empty
    hasMetrics <- newIORef Set.empty
    allTracers <- newIORef Set.empty
    pure $ ConfigReflection silence hasMetrics allTracers


-- | A mutable map from namespace index to 'LogDoc', populated by the
--   'TCDocument' control pass.
newtype DocCollector = DocCollector (IORef (Map Int LogDoc))


-- | Documentation record for a single traced namespace.
data LogDoc = LogDoc {
    ldDoc           :: !Text
  , ldMetricsDoc    :: !(Map Text Text)
  , ldNamespace     :: ![([Text], [Text])]
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
emptyLogDoc d m =
    LogDoc d (Map.fromList m) [] Nothing Nothing Nothing [] [] [] [] False
