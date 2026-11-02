-- | Compares builds of hermod-bench-app.
--
--   The binaries run interleaved, in alternating order, for every
--   configuration; their trace output goes to the null device.  Printed are
--   mean ± standard error per metric and the difference against the first
--   binary.  The configuration @none@, the baseline without tracing, always
--   runs: against it, each configuration's table shows tracing's own cost per
--   message and its share of the CPU, per binary.  Where the binaries come
--   from doesn't matter: revisions (see
--   @build.sh@), GHC versions or flags.  Each binary's GHC version and
--   built-in RTS options are read from @+RTS --info@ and recorded with its
--   results.
module Main (main) where

import           Control.Monad (forM, forM_, unless)
import qualified Data.Aeson as AE
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy.Char8 as BL
import           Data.Char (isSpace)
import           Data.List (isSuffixOf)
import           Data.Maybe (fromMaybe)
import           Options.Applicative
import           System.Exit (ExitCode (..), die)
import           System.FilePath (takeFileName, (<.>), (</>))
import           System.Info (os)
import           System.IO
import           System.Process
import           Text.Printf (hPrintf, printf)


data Binary = Binary
  { bName       :: String
  , bPath       :: FilePath
  , bGhcVersion :: String   -- ^ from @+RTS --info@
  , bRtsOpts    :: String   -- ^ built in with @-with-rtsopts@
  }

data Options = Options
  { oBinaries  :: [(String, FilePath)]
  , oRounds    :: Int
  , oConfigs   :: [String]
  , oConfigDir :: FilePath
  , oRts       :: String
  , oOut       :: Maybe FilePath
  , oAppArgs   :: [String]
  }

options :: Parser Options
options = Options
    <$> some (option (eitherReader binary)
               (long "bin" <> metavar "NAME=PATH"
                <> help "A build of hermod-bench-app (repeat; the first is the baseline)"))
    <*> option auto (long "rounds" <> metavar "N" <> value 5 <> showDefault)
    <*> (defaultConfigs <$> many (strOption
               (long "config" <> metavar "CONFIG"
                <> help "A name in the configuration directory, a path, or 'none' for no tracing \
                        \(repeat; default: quiet, mixed; 'none' always runs, as the baseline)")))
    <*> strOption (long "config-dir" <> metavar "DIR" <> value "examples/hermod-bench-app/config"
                   <> showDefault)
    <*> strOption (long "rts" <> metavar "OPTS" <> value ""
                   <> help "RTS options, in addition to each binary's built-in ones")
    <*> optional (strOption (long "out" <> metavar "FILE"
                             <> help "Write all summaries as JSON lines to this file"))
    <*> many (strArgument (metavar "-- APP-ARGS..." <> help "Arguments for the app"))
  where
    binary s = case break (== '=') s of
      (name, '=' : path) | not (null name), not (null path) -> Right (name, path)
      (path, "")         | not (null path)                  -> Right (path, path)
      _                                                     -> Left "expected NAME=PATH"
    defaultConfigs [] = ["quiet", "mixed"]
    defaultConfigs cs = cs

main :: IO ()
main = do
    hSetEncoding stdout utf8
    o <- execParser $ info (options <**> helper)
           (fullDesc <> progDesc "Run builds of hermod-bench-app interleaved and compare them")
    bins <- forM (oBinaries o) $ \(name, path) -> do
      (ghc, rtsOpts) <- binaryInfo path
      hPutStrLn stderr $ name <> ": GHC " <> ghc <> ", -with-rtsopts " <> show rtsOpts <> ", " <> path
      pure (Binary name path ghc rtsOpts)
    let given   = map (configPath (oConfigDir o)) (oConfigs o)
        configs | "none" `elem` given = given
                | otherwise           = "none" : given
        withOut act = case oOut o of
          Nothing -> act Nothing
          Just f  -> withFile f WriteMode (act . Just)

    withOut $ \mbOut -> do
      results <- fmap concat $ forM [0 .. oRounds o - 1] $ \rnd ->
        fmap concat $ forM configs $ \c ->
          forM (if even rnd then bins else reverse bins) $ \b -> do
            s <- runOnce o b c
            let s' = KM.union (KM.fromList
                       [ ("bin", AE.toJSON (bName b)), ("binPath", AE.toJSON (bPath b))
                       , ("ghcVersion", AE.toJSON (bGhcVersion b))
                       , ("withRtsOpts", AE.toJSON (bRtsOpts b)), ("rts", AE.toJSON (oRts o))
                       , ("round", AE.toJSON rnd) ]) s
            mapM_ (\h -> BL.hPutStrLn h (AE.encode s') >> hFlush h) mbOut
            hPrintf stderr "round %d/%d %s %s: %.3f s CPU, %.0f B/msg\n"
              (rnd + 1) (oRounds o) (takeFileName c) (bName b)
              (field "cpuSec" s) (field "allocatedBytes" s / field "traced" s)
            pure (c, bName b, s)
      let resultsFor c = [ (n, s) | (c', n, s) <- results, c' == c ]
      forM_ configs $ \c -> printTable o bins c (resultsFor c) (resultsFor "none")

-- | The GHC version and built-in RTS options of a binary.
binaryInfo :: FilePath -> IO (String, String)
binaryInfo path = do
    out <- readProcess path ["+RTS", "--info", "-RTS"] ""
    case [ xs | (xs, rest) <- reads out, all isSpace rest ] of
      [kvs :: [(String, String)]] -> pure ( fromMaybe "unknown" (lookup "GHC version" kvs)
                                          , fromMaybe "" (lookup "Flag -with-rtsopts" kvs) )
      _ -> die $ path <> ": unreadable +RTS --info"

configPath :: FilePath -> String -> FilePath
configPath dir c
  | c == "none" || '/' `elem` c || any (`isSuffixOf` c) [".yaml", ".json"] = c
  | otherwise = dir </> c <.> "yaml"

-- | Runs a binary once and returns the summary it prints last on stderr.
runOnce :: Options -> Binary -> FilePath -> IO AE.Object
runOnce o b config =
    withFile nullDevice WriteMode $ \devNull -> do
      (_, _, Just err, ph) <- createProcess (proc (bPath b) args)
                                { std_out = UseHandle devNull, std_err = CreatePipe }
      stderrText <- BS.hGetContents err
      code <- waitForProcess ph
      unless (code == ExitSuccess) $
        die $ unwords (bPath b : args) <> ": " <> show code <> "\n" <> BC.unpack stderrText
      case reverse (BC.lines stderrText) of
        l : _ | Just s <- AE.decodeStrict l -> pure s
        _ -> die $ bPath b <> ": no summary on stderr"
  where
    args = tracing <> oAppArgs o <> rts
    tracing | config == "none" = ["--no-tracing"]
            | otherwise        = ["--config", config]
    rts | null (words (oRts o)) = []
        | otherwise             = "+RTS" : words (oRts o) <> ["-RTS"]
    nullDevice | os == "mingw32" = "NUL"
               | otherwise       = "/dev/null"

-- | (label, value of a summary, unit)
metrics :: [(String, AE.Object -> Double, String)]
metrics =
    [ ("CPU per traced message",  cpuPerMessage,                   "ns")
    , ("mutator CPU per message", perMessage 1e9 "mutatorCpuSec",  "ns")
    , ("GC CPU per message",      perMessage 1e9 "gcCpuSec",       "ns")
    , ("allocation per message",  perMessage 1 "allocatedBytes",   "B")
    , ("wall time",               field "wallSec",                 "s")
    , ("GCs",                     field "gcs",                     "")
    , ("major GCs",               field "majorGcs",                "")
    , ("emitted share",           perMessage 100 "emitted",        "%")
    ]
  where
    perMessage scale k s = scale * field k s / field "traced" s

cpuPerMessage :: AE.Object -> Double
cpuPerMessage s = 1e9 * field "cpuSec" s / field "traced" s

field :: String -> AE.Object -> Double
field k s = case KM.lookup (Key.fromString k) s of
    Just (AE.Number n) -> realToFrac n
    _                  -> 0 / 0

-- | How a row's difference against the baseline binary reads.
data Delta = Relative | Points

-- | One configuration's table; the second list holds the runs of @none@.
printTable
  :: Options -> [Binary] -> FilePath -> [(String, AE.Object)] -> [(String, AE.Object)] -> IO ()
printTable o bins c results baseline = do
    printf "\n%s  (%d rounds; mean ± standard error; Δ against %s)\n"
      (takeFileName c) (oRounds o) (bName base)
    putStrLn $ printf "  %-26s" ("" :: String)
      <> concat [ printf "%26s" (take 24 (bName b)) | b <- bins ]
      <> concat [ printf "%18s" ("Δ " <> take 14 (bName b)) | b <- others ]
    forM_ metrics $ \(label, f, unit) -> row label unit (meanSE . sample f results) Relative
    unless (c == "none") $ do
      putStrLn "  above the no-tracing baseline of the same binary:"
      row "  tracing's CPU per message" "ns" ownCost Relative
      row "  tracing's share of CPU" "%" share Points
  where
    (base, others) = case bins of
      b : bs -> (b, bs)
      []     -> error "printTable: no binaries"
    sample f rs b = [ f s | (n, s) <- rs, n == bName b ]

    row :: String -> String -> (Binary -> (Double, Double)) -> Delta -> IO ()
    row label unit stats d = do
      let (baseMean, _) = stats base
          cell b = let (m, se) = stats b in printf "%14.2f ± %-6.2f%3s" m se unit
          delta b = case d of
            Relative | baseMean /= 0 -> printf "%+17.1f%%" ((fst (stats b) - baseMean) / baseMean * 100)
                     | otherwise     -> replicate 18 ' '
            Points                   -> printf "%+15.1f pp" (fst (stats b) - baseMean)
      putStrLn $ printf "  %-26s" label <> concatMap cell bins <> concatMap delta others

    -- the difference of two means; their standard errors add in quadrature
    ownCost b =
      let (m, se)   = meanSE (sample cpuPerMessage results b)
          (m0, se0) = meanSE (sample cpuPerMessage baseline b)
      in  (m - m0, sqrt (se * se + se0 * se0))
    share b =
      let (own, se) = ownCost b
          (total, _) = meanSE (sample cpuPerMessage results b)
      in  (100 * own / total, 100 * se / total)

meanSE :: [Double] -> (Double, Double)
meanSE xs = (m, se)
  where
    n  = fromIntegral (length xs)
    m  = sum xs / n
    se | length xs > 1 = sqrt (sum [ (x - m) * (x - m) | x <- xs ] / (n - 1) / n)
       | otherwise     = 0 / 0
