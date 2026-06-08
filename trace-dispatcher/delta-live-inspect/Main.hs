module Main (main) where

import           Cardano.Logging
import           Control.Exception    (evaluate)
import           Control.Monad        (replicateM)
import           Control.Tracer.Arrow (TracerA (..))
import           Data.Map.Strict      (fromList)
import           Data.Text            (Text)
import           GHC.Stats            (GCDetails (..), RTSStats (..), getRTSStats,
                                       getRTSStatsEnabled)
import           System.Mem           (performMajorGC)

data DemoMsg = DemoAlert Int | DemoInfo Text | DemoDebug Text deriving Show

instance LogFormatting DemoMsg where
  forMachine _ _ = mempty
  forHuman _     = ""

instance MetaTrace DemoMsg where
  namespaceFor (DemoAlert _) = Namespace [] ["DemoAlert"]
  namespaceFor (DemoInfo  _) = Namespace [] ["DemoInfo"]
  namespaceFor (DemoDebug _) = Namespace [] ["DemoDebug"]
  severityFor (Namespace _ ["DemoAlert"]) _ = Just Warning
  severityFor (Namespace _ ["DemoInfo"])  _ = Just Info
  severityFor (Namespace _ ["DemoDebug"]) _ = Just Debug
  severityFor _                           _ = Nothing
  documentFor _ = Nothing
  allNamespaces = [Namespace [] ["DemoAlert"], Namespace [] ["DemoInfo"], Namespace [] ["DemoDebug"]]

demoCfg :: TraceConfig
demoCfg = emptyTraceConfig
  { tcOptions = fromList
      [( [], [ ConfSeverity (SeverityF (Just Debug))
             , ConfDetail DNormal
             , ConfBackend [Stdout HumanFormatColoured]
             ])]
  }

liveBytes :: IO Int
liveBytes = do
  performMajorGC
  fromIntegral . gcdetails_live_bytes . gc <$> getRTSStats

-- Build a tracer that is the left-associative <> composition of n independent
-- configured tracers.  foldl1 avoids touching mempty, so the noEmitK contains
-- exactly n levels of (lp *** lp) without spurious Squelching wrappers.
mkScaled :: Int -> IO (Trace IO DemoMsg)
mkScaled n = do
  configState <- emptyConfigReflection
  trs <- replicateM (max 1 n) $ do
    tr <- mkCardanoTracer (mempty :: Trace IO FormattedMessage)
                          (mempty :: Trace IO FormattedMessage) Nothing ["Demo"]
          :: IO (Trace IO DemoMsg)
    configureTracers configState demoCfg [tr]
    return tr
  return (foldl1 (<>) trs)

isolateEmit :: Int -> IO (IO ())
isolateEmit n = do
  tr <- mkScaled n
  case runTracer (unpackTrace tr) of
    -- evaluate keeps emitK alive as a GC root until the returned action is executed.
    Emitting emitK _ -> return (evaluate emitK >> return ())
    _                -> return (return ())

isolateNoEmit :: Int -> IO (IO ())
isolateNoEmit n = do
  tr <- mkScaled n
  case runTracer (unpackTrace tr) of
    -- evaluate keeps noEmitK alive as a GC root until the returned action is executed.
    Emitting _ noEmitK -> return (evaluate noEmitK >> return ())
    _                  -> return (return ())

-- Measure retained bytes of the closure produced by mkHold.
-- Compares live heap with the closure held vs after it falls out of scope;
-- any background residue that is alive in both measurements cancels out.
sizeOf :: IO (IO ()) -> IO Int
sizeOf mkHold = do
  liveWith <- do
    hold <- mkHold
    live <- liveBytes   -- hold (and its captured closures) is alive here
    hold                -- last use of hold
    return live
  -- hold is now out of scope; the next GC will collect it
  liveWithout <- liveBytes
  return (liveWith - liveWithout)

measure :: Int -> IO (Int, Int)
measure n = do
  e  <- sizeOf (isolateEmit   n)
  ne <- sizeOf (isolateNoEmit n)
  return (e, ne)

main :: IO ()
main = do
  enabled <- getRTSStatsEnabled
  putStrLn $ "RTS stats enabled: " ++ show enabled

  -- Warmup: force common CAFs before any measurement.
  _ <- measure 1

  putStrLn ""
  putStrLn "n\temit (bytes)\tno-emit (bytes)"
  mapM_ (\n -> do
    (e, ne) <- measure n
    putStrLn $ show n ++ "\t" ++ show e ++ "\t" ++ show ne
    ) [1, 2, 4, 8, 16, 32, 64]
