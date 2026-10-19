-- | Cost per message of combining traces with '<>'.
--
-- Can be run with:
-- cabal bench hermod-tracing-api-bench --benchmark-option='-o benchmark-api.html'
--
-- Allocation per iteration is reported with --benchmark-option='--regress allocated:iters'.
module Main (main) where

import           Hermod.Tracing.API

import           Data.IORef (newIORef, readIORef)

import           Criterion.Main


main :: IO ()
main = do
    sink' <- opaque sink
    null' <- opaque nullTrace
    let both   = sink' <> sink'
        right  = sink' <> null'
        left   = null' <> sink'
        none   = null' <> null'
        four   = mconcat [sink', sink', sink', sink']
    defaultMain
      [ bgroup "semigroup"
          [ bench "1 sink"                        $ send sink'
          , bench "2 sink <> sink"                $ send both
          , bench "3 sink <> null"                $ send right
          , bench "4 null <> sink"                $ send left
          , bench "5 null <> null"                $ send none
          , bench "6 mconcat of 4 sinks"          $ send four
          , bench "7 premapM over sink <> null"   $ send (premapM pure right)
          , bench "8 premapM over null <> null"   $ send (premapM pure none)
          ]
      ]
  where
    send :: Trace IO Int -> Benchmarkable
    send tr = whnfIO (traceWith tr 1)

    sink :: Trace IO Int
    sink = mkTrace (\_ -> pure ())

    -- Hides a value from the optimiser, so that traces are combined at
    -- runtime, as in an application, not at compile time.
    opaque :: a -> IO a
    opaque x = newIORef x >>= readIORef
