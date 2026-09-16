-- | Wires everything in "Hermod.AlarmBridge.*" together: parse the CLI,
--   spawn hermod-recon (or read this process's own stdin), read its output
--   line by line, classify each line, and deliver the resulting alarms.
--
--   This module is deliberately thin IO glue; the actual decision logic
--   (classification, the startup self-check state machine, retry/backoff,
--   HTTP response interpretation, ...) all lives in pure(-ish), injectable
--   functions in the library modules, so it can be unit tested without
--   spawning real subprocesses or opening real sockets.
module Main (main) where

import           Hermod.AlarmBridge.Cli (CliOptions (..), RunMode (..), TokenSource (..), opts)
import           Hermod.AlarmBridge.Classify (IngressRequest, classifyHermodLine,
                   classifyReConStopped, classifyStderrLine)
import           Hermod.AlarmBridge.Deliver (DeliveryQueue (..), defaultRetryPolicy,
                   deliverWithRetry, httpDeliverOne, startDeliveryWorker, waitForQueueDrain)
import           Hermod.AlarmBridge.Envelope (decodeHermodLine)
import           Hermod.AlarmBridge.ReConProcess (isOnlineMode, needsTracingCfgInjection,
                   prepareReConArgs, writeGeneratedTracingConfig)
import           Hermod.AlarmBridge.Rules (RuleOverrides, emptyRuleOverrides, loadRuleOverrides)
import           Hermod.AlarmBridge.Severity (Severity)
import           Hermod.AlarmBridge.Startup (StartupCheck (..), StartupVerdict (..),
                   initialStartupCheck, startupCheckLimit, stepStartupCheck)

import           Control.Concurrent (threadDelay)
import           Control.Concurrent.Async (concurrently_)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import           Data.Char (isSpace)
import           Data.IORef (atomicModifyIORef', newIORef)
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import           Data.Text.Encoding.Error (lenientDecode)
import           Data.Time.Clock (NominalDiffTime, addUTCTime, getCurrentTime)
import           Options.Applicative (execParser)
import           System.Exit (ExitCode (..), die, exitSuccess, exitWith)
import           System.IO (Handle, hIsEOF, hPutStrLn, hSetBinaryMode, stderr, stdin)
import           System.Process (CreateProcess (..), StdStream (CreatePipe, Inherit), createProcess,
                   proc, waitForProcess)

-- | How long to keep the startup self-check "open": a non-empty line
--   arriving after this window elapses no longer counts towards
--   'startupCheckLimit', so a genuinely sparse @--mode online@ stream isn't
--   killed hours later just because it slowly accumulated a few isolated
--   bad lines.
startupGraceSeconds :: NominalDiffTime
startupGraceSeconds = 5

-- | Best-effort time budget to let the in-memory delivery queue drain
--   before the bridge process exits.
shutdownDrainMicros :: Int
shutdownDrainMicros = 5000000

main :: IO ()
main = do
  CliOptions{..} <- execParser opts

  overrides <- case rulesFile of
    Nothing -> pure emptyRuleOverrides
    Just fp -> do
      result <- loadRuleOverrides fp
      case result of
        Left err -> die ("hermod-alarm-bridge: failed to load --rules file " <> fp <> ": " <> err)
        Right m  -> pure m

  token <- resolveProducerToken producerToken

  let policy     = defaultRetryPolicy
      deliverOne = httpDeliverOne tracerHost (fromIntegral tracerPort) token

  dq <- startDeliveryWorker policy deliverOne

  case runMode of
    ReadStdin -> do
      hSetBinaryMode stdin True
      runIngestLoop overrides defaultSeverity (dqEnqueue dq) stdin
      waitForQueueDrain dq shutdownDrainMicros
      dqShutdown dq

    ExecReCon cmd args -> do
      finalArgs <-
        if needsTracingCfgInjection args
          then do
            cfgPath <- writeGeneratedTracingConfig
            pure (prepareReConArgs cfgPath args)
          else pure args

      (_, mOut, mErr, ph) <- createProcess
        (proc cmd finalArgs) { std_out = CreatePipe, std_err = CreatePipe, std_in = Inherit }

      case (mOut, mErr) of
        (Just outH, Just errH) -> do
          hSetBinaryMode outH True
          concurrently_
            (runIngestLoop overrides defaultSeverity (dqEnqueue dq) outH)
            (runStderrLoop (dqEnqueue dq) errH)
        _ ->
          die "hermod-alarm-bridge: internal error: expected piped stdout/stderr from hermod-recon"

      exitCode <- waitForProcess ph
      now <- getCurrentTime
      let online = isOnlineMode args
          stopBridge finish = do
            waitForQueueDrain dq shutdownDrainMicros
            dqShutdown dq
            finish

      case exitCode of
        ExitFailure n -> do
          _ <- deliverWithRetry policy threadDelay deliverOne (classifyReConStopped now n)
          stopBridge (exitWith exitCode)
        ExitSuccess
          -- hermod-recon in --mode online is meant to run forever; even a
          -- clean exit is anomalous and worth alarming on.
          | online -> do
              _ <- deliverWithRetry policy threadDelay deliverOne (classifyReConStopped now 0)
              stopBridge exitSuccess
          | otherwise ->
              stopBridge exitSuccess

-- | Resolve the CLI's @--token@\/@--token-file@ choice (see
--   'Hermod.AlarmBridge.Cli.TokenSource') into the actual bearer token text
--   to send. Mirrors cardano-tracer's own
--   'Cardano.Tracer.Handlers.Alarms.Auth.readTokenFile': read once at
--   startup, stripped of surrounding whitespace (a trailing newline from an
--   editor or @echo@ is the common way a token file gets corrupted).
resolveProducerToken :: Maybe TokenSource -> IO (Maybe Text)
resolveProducerToken Nothing                  = pure Nothing
resolveProducerToken (Just (TokenLiteral t))  = pure (Just t)
resolveProducerToken (Just (TokenFile fp))    = Just . Text.strip . Text.pack <$> readFile fp

-- | True for a line that is empty, or contains only whitespace.
isBlankLine :: BS.ByteString -> Bool
isBlankLine = BS8.all isSpace

-- | Read newline-delimited hermod-recon JSON lines from a handle until
--   EOF, classifying and enqueueing each for delivery.
--
--   Startup self-check: the first several non-empty lines are watched
--   (bounded by 'startupGraceSeconds', or by end-of-stream in a short
--   finite/offline run) -- if they *all* fail to parse as hermod JSON, this
--   exits the whole process with a clear, actionable error, since that
--   means hermod-recon almost certainly isn't emitting Stdout
--   MachineFormat. Once a single line has parsed successfully, a later
--   isolated bad line is just logged to this bridge's own stderr and
--   skipped -- never fatal.
runIngestLoop :: RuleOverrides -> Severity -> (IngressRequest -> IO ()) -> Handle -> IO ()
runIngestLoop overrides defSev enqueue h = do
  now <- getCurrentTime
  go (addUTCTime startupGraceSeconds now) initialStartupCheck
 where
  go deadline sc = do
    eof <- hIsEOF h
    if eof
      then atEof sc
      else do
        raw <- BS8.hGetLine h
        if isBlankLine raw
          then go deadline sc
          else case decodeHermodLine raw of
            Right hl -> do
              mapM_ enqueue (classifyHermodLine overrides defSev hl)
              let (sc', _verdict) = stepStartupCheck sc True
              go deadline sc'
            Left err
              | scPassed sc -> do
                  hPutStrLn stderr ("hermod-alarm-bridge: skipping unparseable line: " <> err)
                  go deadline sc
              | otherwise -> do
                  nowLine <- getCurrentTime
                  if nowLine > deadline
                    then do
                      hPutStrLn stderr
                        "hermod-alarm-bridge: startup self-check window elapsed without a clear \
                        \verdict; no longer treating parse failures as a startup problem"
                      hPutStrLn stderr ("hermod-alarm-bridge: skipping unparseable line: " <> err)
                      go deadline sc { scPassed = True }
                    else case stepStartupCheck sc False of
                      (_, StartupFailed) -> fatalStartupError err
                      (sc', _)           -> do
                        hPutStrLn stderr $
                          "hermod-alarm-bridge: warning: startup self-check " <> show (scFailures sc')
                            <> "/" <> show startupCheckLimit
                            <> " lines failed to parse as JSON: " <> err
                        go deadline sc'

  atEof sc
    | scPassed sc || scFailures sc == 0 = pure ()
    | otherwise = fatalStartupError "input stream ended before producing any valid hermod JSON line"

fatalStartupError :: String -> IO a
fatalStartupError lastErr = do
  hPutStrLn stderr $ unlines
    [ "hermod-alarm-bridge: fatal: hermod-recon does not appear to be emitting Stdout MachineFormat JSON."
    , "  (last parse error: " <> lastErr <> ")"
    , ""
    , "  Fix: pass hermod-recon a config (--hermod-tracing-cfg FILE) that selects a"
    , "  \"Stdout MachineFormat\" backend, e.g.:"
    , ""
    , "    HermodTracing:"
    , "      Options:"
    , "        \"\":"
    , "          severity: Info"
    , "          backends:"
    , "            - Stdout MachineFormat"
    , ""
    , "  (see hermod-tracing-core/doc/config.yaml for the full config shape), or omit"
    , "  --hermod-tracing-cfg from the args after --exec -- and let this bridge generate"
    , "  one for you automatically."
    ]
  exitWith (ExitFailure 2)

-- | Read raw (never JSON-parsed) lines from hermod-recon's stderr until
--   EOF, classifying each via 'classifyStderrLine' and enqueueing it.
runStderrLoop :: (IngressRequest -> IO ()) -> Handle -> IO ()
runStderrLoop enqueue h = do
  counterRef <- newIORef (0 :: Int)
  go counterRef
 where
  go counterRef = do
    eof <- hIsEOF h
    if eof
      then pure ()
      else do
        raw <- BS.hGetLine h
        if isBlankLine raw
          then go counterRef
          else do
            n   <- atomicModifyIORef' counterRef (\c -> (c + 1, c + 1))
            now <- getCurrentTime
            let lineText = TE.decodeUtf8With lenientDecode raw
            enqueue (classifyStderrLine n now lineText)
            go counterRef
