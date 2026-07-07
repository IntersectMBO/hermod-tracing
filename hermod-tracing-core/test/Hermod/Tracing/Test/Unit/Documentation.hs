{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Hermod.Tracing.Test.Unit.Documentation (
    docTracers
) where

import           Hermod.Tracing
import           Hermod.Tracing.DocuGenerator         (docuResultsToText,
                                                        documentTracer)
import           Hermod.Tracing.Test.Tracer
import           Hermod.Tracing.Test.Unit.TestObjects

import           Data.IORef
import qualified Data.Map                              as Map
import qualified Data.Text                             as T


docTracers :: IO T.Text
docTracers = do
  testTracerRef <- newIORef []
  tt <- testTracer testTracerRef
  t1   <- mkHermodTracer tt tt Nothing ["Node1"]
  t2   <- mkHermodTracer tt tt Nothing ["Node2"]
  confState <- emptyConfigReflection
  configureTracers confState config1 [t1, t2]
  b1 <- documentTracer (t1 :: Trace IO (TraceForgeEvent LogBlock))
  b2 <- documentTracer (t2 :: Trace IO (TraceForgeEvent LogBlock))
  pure (docuResultsToText (b1 <> b2) config1)

config1 :: TraceConfig
config1 = TraceConfig {
      tcOptions = Map.fromList
          [ ([], [ConfSeverity (SeverityF Nothing), ConfBackend [Stdout MachineFormat]])
          , (["node2"], [ConfSeverity (SeverityF (Just Info)),  ConfBackend [Stdout MachineFormat]])
          , (["node1"], [ConfSeverity (SeverityF (Just Warning)),  ConfBackend [Stdout MachineFormat]])
          ]
    , tcForwarder = Just TraceOptionForwarder {
        tofQueueSize = 1000
      , tofVerbosity = Minimum
      , tofMaxReconnectDelay = 60
      }
    , tcApplicationName = Nothing
    , tcMetricsPrefix = Just "cardano" -- representative prefix from Hermod's Cardano origins
    , tcPeriodicTracers = Map.empty
    , tcPrometheusSimpleRun = Nothing
    }

