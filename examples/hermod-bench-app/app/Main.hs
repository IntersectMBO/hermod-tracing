-- | A chatty application for benchmarking Hermod at application level.
--
--   Worker threads compute, keep a live heap busy and trace events of an
--   anime cast through tracers configured like cardano-node's.  Trace output
--   goes to stdout; at the end, one JSON line with the run's RTS statistics
--   goes to stderr.
module Main (main) where

import           Tracers
import           Workload

import           Hermod.Tracing

import           Data.Aeson (object, (.=))
import qualified Data.Aeson as AE
import qualified Data.ByteString.Lazy.Char8 as BL
import           Data.IORef
import           Data.Maybe (fromMaybe)
import           GHC.Stats
import           Options.Applicative
import           System.IO (stderr)
import           System.Mem (performMajorGC)
import qualified System.Metrics as Metrics


data Options = Options
  { oConfig   :: Maybe FilePath   -- ^ 'Nothing': no tracing
  , oLiveHeap :: Int
  , oParams   :: Params
  }

options :: Parser Options
options = Options
    <$> (Just <$> strOption (long "config" <> metavar "FILE" <> help "Hermod configuration (YAML or JSON)")
         <|> flag' Nothing (long "no-tracing" <> help "Trace nothing: the baseline without tracing"))
    <*> option auto (long "live-heap" <> metavar "MB" <> value 256 <> showDefault
                     <> help "Live data kept for the whole run")
    <*> params
  where
    params = Params
      <$> option auto (long "threads" <> metavar "N" <> value 4 <> showDefault
                       <> help "Worker threads")
      <*> mode
      <*> option auto (long "messages" <> metavar "K" <> value 10 <> showDefault
                       <> help "Messages traced per iteration")
      <*> option auto (long "work" <> metavar "W" <> value 2000 <> showDefault
                       <> help "Units of pure work per iteration")
      <*> option auto (long "churn-every" <> metavar "C" <> value 100 <> showDefault
                       <> help "Replace a live heap slot every C iterations (0: never)")
      <*> option auto (long "seed" <> metavar "S" <> value 42 <> showDefault)
    mode = iterations <|> rate
    iterations = Iterations
      <$> option auto (long "iterations" <> metavar "N" <> value 200000 <> showDefault
                       <> help "Iterations per worker (fixed work)")
    rate = Rate
      <$> option auto (long "rate" <> metavar "MSG/S" <> help "Messages per second, all workers (fixed rate)")
      <*> option auto (long "duration" <> metavar "SECONDS" <> help "Duration of a fixed-rate run")

main :: IO ()
main = do
    Options {oConfig, oLiveHeap, oParams} <- execParser $
      info (options <**> helper)
           (fullDesc <> progDesc "Trace an anime cast's events through Hermod, under load")
    enabled <- getRTSStatsEnabled
    if not enabled
      then BL.hPutStrLn stderr "hermod-bench-app needs the RTS option -T"
      else run oConfig oLiveHeap oParams

run :: Maybe FilePath -> Int -> Params -> IO ()
run mbConfigFile liveHeapMB p = do
    emitted  <- newIORef 0
    ts <- case mbConfigFile of
      Nothing -> pure noTracers
      Just configFile -> do
        trConfig <- readConfiguration (FromFile configFile)
        state    <- newIORef 0
        trStdout <- countEmitted emitted <$> standardTracer
        store    <- Metrics.newStore
        trEkg    <- ekgTracer trConfig store
        mkAppTracers trStdout (Just trEkg) trConfig state

    heap <- newLiveHeap liveHeapMB (pSeed p)

    performMajorGC
    s0 <- getRTSStats
    traced <- runWorkers p ts heap
    s1 <- getRTSStats
    nEmitted <- readIORef emitted

    BL.hPutStrLn stderr $ AE.encode $ object
      [ "config"          .= fromMaybe "none" mbConfigFile
      , "threads"         .= pThreads p
      , "mode"            .= modeText (pMode p)
      , "messages"        .= pMessages p
      , "work"            .= pWork p
      , "churnEvery"      .= pChurnEvery p
      , "liveHeapMB"      .= liveHeapMB
      , "traced"          .= sum traced
      , "emitted"         .= nEmitted
      , "wallSec"         .= secs (elapsed_ns s1 - elapsed_ns s0)
      , "cpuSec"          .= secs (cpu_ns s1 - cpu_ns s0)
      , "mutatorCpuSec"   .= secs (mutator_cpu_ns s1 - mutator_cpu_ns s0)
      , "gcCpuSec"        .= secs (gc_cpu_ns s1 - gc_cpu_ns s0)
      , "allocatedBytes"  .= (allocated_bytes s1 - allocated_bytes s0)
      , "copiedBytes"     .= (copied_bytes s1 - copied_bytes s0)
      , "gcs"             .= (gcs s1 - gcs s0)
      , "majorGcs"        .= (major_gcs s1 - major_gcs s0)
      , "maxLiveBytes"    .= max_live_bytes s1
      ]
  where
    secs :: RtsTime -> Double
    secs ns = fromIntegral ns / 1e9
    modeText :: Mode -> String
    modeText = \case
      Iterations n -> "iterations " <> show n
      Rate r d     -> "rate " <> show r <> " for " <> show d <> " s"
