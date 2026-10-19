module Hermod.Tracing.Test.Unit.Reconfiguration (
    testReconfigurationLiveHeap
  ) where

import           Hermod.Tracing
import           Hermod.Tracing.Test.Config (config1, config2)
import           Hermod.Tracing.Test.Types

import           Control.Monad (forM_, replicateM_, unless)
import           GHC.Stats
import           System.Mem (performMajorGC)

import           Test.Tasty.HUnit


-- | Reconfiguring a tracer must not grow the live heap: the configured stages
--   keep the tracers built for the current configuration and replace them on
--   every reset.  Alternates a uniform and a mixed configuration, tracing
--   between reconfigurations, and compares the live heap after a warm-up with
--   the live heap after many more rounds.
testReconfigurationLiveHeap :: Assertion
testReconfigurationLiveHeap = do
    enabled <- getRTSStatsEnabled
    unless enabled $ assertFailure "needs the RTS option -T"
    cr <- emptyConfigReflection
    tr <- mkHermodTracer sink sink Nothing ["Test"]
    let round' = forM_ [config1, config2] $ \config -> do
          configureTracers cr config [tr]
          replicateM_ 10 $ forM_ messages (traceWith tr)
    replicateM_ 100 round'
    before <- liveBytes
    replicateM_ 2000 round'
    after <- liveBytes
    -- keeps the tracer alive across the measurement
    traceWith tr (Message1 1 1)
    assertBool ("live heap grew from " <> show before <> " to " <> show after <> " bytes")
      (after <= before + 64 * 1024)
  where
    sink = mkTrace (\_ -> pure ())
    messages = [Message1 1 1, Message2 1 "text", Message3 1 1.0]
    liveBytes = do
      performMajorGC
      gcdetails_live_bytes . gc <$> getRTSStats
