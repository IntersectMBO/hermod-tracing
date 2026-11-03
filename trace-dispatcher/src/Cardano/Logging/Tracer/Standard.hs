{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Cardano.Logging.Tracer.Standard (
    standardTracer
) where

import           Cardano.Logging.DocuGenerator
import           Cardano.Logging.Types
import           Cardano.Logging.Utils (threadLabelMe, tryEvalNF)

import           Control.Concurrent.Async
import           Control.Concurrent.Chan.Unagi.Bounded
import           Control.Exception
import           Control.Monad (void, when)
import           Control.Monad.IO.Class
import qualified Control.Tracer as T
import           Data.IORef
import           Data.Maybe (isNothing)
import           Data.Text (Text)
import qualified Data.Text.IO as TIO
import           System.IO (hFlush, hPutStrLn, stderr, stdout)

-- | The state of a standard tracer
newtype StandardTracerState =  StandardTracerState {
    stRunning :: Maybe (InChan Text, OutChan Text, Async ())
}

emptyStandardTracerState :: StandardTracerState
emptyStandardTracerState = StandardTracerState Nothing

-- | The standardTracer handles stdout logging in a thread-safe manner.
--   It is strongly advised to construct only one standardTracer for any application.
standardTracer :: forall m. (MonadIO m)
  => m (Trace m FormattedMessage)
standardTracer = do
    stateRef <- liftIO $ newIORef emptyStandardTracerState
    pure $ Trace $ T.arrow $ T.emit $ uncurry (output stateRef)
  where
    output ::
         IORef StandardTracerState
      -> LoggingContext
      -> Either TraceControl FormattedMessage
      -> m ()
    output stateRef LoggingContext{} (Right (FormattedHuman _c msg)) = liftIO $ do
      st  <- readIORef stateRef
      case stRunning st of
        Just (inChannel, _, _) -> writeChan inChannel msg
        Nothing                -> pure ()
    output stateRef LoggingContext{} (Right (FormattedMachine msg)) = liftIO $ do
      st  <- readIORef stateRef
      case stRunning st of
        Just (inChannel, _, _) -> writeChan inChannel msg
        Nothing                -> pure ()
    output stateRef LoggingContext{} (Left TCReset) = liftIO $ do
      st <- readIORef stateRef
      when (isNothing $ stRunning st) $
        startStdoutThread stateRef
    output _ lk c@(Left TCDocument {}) =
       docIt
        (Stdout MachineFormat)
        (lk, c)
    output _stateRef LoggingContext {} _ = pure ()

-- | Forks a new thread, which writes messages to stdout
startStdoutThread :: IORef StandardTracerState -> IO ()
startStdoutThread stateRef = do
    (inChan, outChan) <- newChan 2048
    as <- async $ threadLabelMe "StdoutTrace" >> stdoutThread outChan
    link as
    atomicWriteIORef stateRef $ StandardTracerState (Just (inChan, outChan, as))

-- | Writer thread: pulls rendered messages off the channel and writes
--   them to stdout. Safely terminates when all producers have gone out
--   of scope ('BlockedIndefinitelyOnMVar').
--
--   On a write failure (encode error, EPIPE, closed handle, …) the
--   first failure is reported on stderr; subsequent consecutive
--   failures are silent until a write succeeds again. On a rendering
--   failure (NF-force throws), the exception is reported on stderr and
--   the loop continues. Writes to stderr are themselves wrapped so a
--   broken stderr does not escalate.
stdoutThread :: OutChan Text -> IO ()
stdoutThread outChan =
  handle (\BlockedIndefinitelyOnMVar -> pure ()) (loop True)
  where
  loop :: Bool -> IO ()
  loop ok =
    readChan outChan >>= tryEvalNF >>= \case
      Right t ->
        guarded ok (TIO.putStrLn t >> hFlush stdout) >>=
          loop
      Left except -> do
        reportErr $ "Error rendering trace message: " ++ displayException except
        loop ok

  -- Report only the first failure after a successful write.
  guarded :: Bool -> IO () -> IO Bool
  guarded ok act = try @IOException act >>= \case
    Right () ->
      pure True
    Left except -> do
      when ok $
        reportErr $ "Error writing trace message to stdout: " ++ displayException except
      pure False

  reportErr :: String -> IO ()
  reportErr = void . try @IOException . hPutStrLn stderr
