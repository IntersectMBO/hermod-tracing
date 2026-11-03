-- | The stages of a configured tracer, built up one at a time, each tracing a
--   message that the severity filter drops ('Message1' is 'Debug', the
--   configured threshold 'Info').  Comparing neighbouring benchmarks shows
--   what each stage adds to the cost of a dropped message.
--
--   Then the full tracer with an EKG backend, as most applications run it: a
--   dropped message still goes through the metrics branch, with metrics
--   ('Message1') or, as most messages, without ('Message2').
module FilterStages (
    filterStageBenchmarks
  ) where

import           Hermod.Tracing
import           Hermod.Tracing.Test.Config (config2)
import           Hermod.Tracing.Test.Tracer
import           Hermod.Tracing.Test.Types
import           Hermod.Tracing.Trace.Annotations (withNames, withSeverity)

import           Data.IORef
import           Data.Map.Strict (fromList)
import           System.Metrics (newStore)

import           Criterion.Main


filterStageBenchmarks :: IO Benchmark
filterStageBenchmarks = do
    dynamic    <- configured uniformInfo . annotate =<< filterSeverityFromConfig sink
    silenced   <- configured uniformInfo
                    =<< maybeSilent isSilentTracer prefix False . annotate
                    =<< filterSeverityFromConfig sink
    fullUni    <- configured uniformInfo =<< fullTracer
    fullMixed  <- configured config2 =<< fullTracer
    ekgUni     <- configured uniformWarning =<< fullTracerEKG
    ekgMixed   <- configured config2 =<< fullTracerEKG
    pure $ bgroup "droppedMessage"
      [ bench "1 sink"                                $ send sink
      , bench "2 names, severity"                     $ send (annotate sink)
      , bench "3 filterSeverityFromConfig"            $ send dynamic
      , bench "4 3 + maybeSilent"                     $ send silenced
      , bench "5 4 <> mempty"                         $ send (silenced <> mempty)
      , bench "6 mkHermodTracer, uniform config"      $ send fullUni
      , bench "7 mkHermodTracer, mixed config"        $ send fullMixed
      , bench "8 mkHermodTracer + EKG, uniform config, with metrics"
                                                      $ send ekgUni
      , bench "9 mkHermodTracer + EKG, uniform config, no metrics"
                                                      $ sendNoMetrics ekgUni
      , bench "10 mkHermodTracer + EKG, mixed config, no metrics"
                                                      $ sendNoMetrics ekgMixed
      ]
  where
    prefix = ["Test"]

    send tr = whnfIO (traceWith tr (Message1 1 1))
    -- 'Message2' is 'Info': dropped by 'uniformWarning' and by 'config2'
    sendNoMetrics tr = whnfIO (traceWith tr (Message2 1 "text"))

    -- What 'mkHermodTracer' puts in front of the severity filter.
    annotate :: Trace IO Message -> Trace IO Message
    annotate = withNames prefix . withSeverity

    sink :: Trace IO Message
    sink = mkTrace (\_ -> pure ())

    fullTracer :: IO (Trace IO Message)
    fullTracer = do
      stdoutTr  <- testTracer =<< newIORef []
      forwardTr <- testTracer =<< newIORef []
      mkHermodTracer stdoutTr forwardTr Nothing prefix

    fullTracerEKG :: IO (Trace IO Message)
    fullTracerEKG = do
      stdoutTr  <- testTracer =<< newIORef []
      forwardTr <- testTracer =<< newIORef []
      ekgTr     <- ekgTracer emptyTraceConfig =<< newStore
      mkHermodTracer stdoutTr forwardTr (Just ekgTr) prefix

    configured :: TraceConfig -> Trace IO Message -> IO (Trace IO Message)
    configured config tr = do
      cr <- emptyConfigReflection
      configureTracers cr config [tr]
      pure tr

-- | The same severity for all namespaces, so the configured filter holds a
--   single value (no per-namespace lookup).
uniformInfo :: TraceConfig
uniformInfo = emptyTraceConfig {
  tcOptions = fromList
    [([],
         [ ConfSeverity (SeverityF (Just Info))
         , ConfDetail DNormal
         , ConfBackend [Forwarder]
         ])
    ]
  }

-- | 'Warning' for all namespaces: 'Message1' and 'Message2' are dropped,
--   'Message3' ('Error') passes, so the tracer is not silent.
uniformWarning :: TraceConfig
uniformWarning = emptyTraceConfig {
  tcOptions = fromList
    [([],
         [ ConfSeverity (SeverityF (Just Warning))
         , ConfDetail DNormal
         , ConfBackend [Forwarder, EKGBackend]
         ])
    ]
  }
