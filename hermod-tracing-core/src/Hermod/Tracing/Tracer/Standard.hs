{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Hermod.Tracing.Tracer.Standard (
    standardTracer
  , stdoutThread   -- re-exported for tests
) where

import           Hermod.Tracing.DocuGenerator
import           Hermod.Tracing.Formatter (FormattedMessage (..))
import           Hermod.Tracing.Types
import           Hermod.Tracing.Utils (threadLabelMe, tryEvalNF)

import           Control.Concurrent.Async
import           Control.Concurrent.Chan.Unagi.Bounded
import           Control.Exception
import           Control.Monad (forever, void, when)
import           Control.Monad.IO.Class
import qualified Control.Tracer as T
import           Data.Bifunctor (first)
import           Data.IORef
import           Data.Maybe (isNothing)
import           Data.Text (Text)
import qualified Data.Text.IO as TIO
import           GHC.IO.Exception (IOErrorType (..))
import           System.IO (hFlush, hPutStrLn, stderr, stdout)
import           System.IO.Error (ioeGetErrorType)

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

-- | The new thread, which does the actual write from the queue.
--   Will safely terminate when all producers have gone out of scope.
stdoutThread :: OutChan Text -> IO ()
stdoutThread outChan =
  catch (loop outChan) \BlockedIndefinitelyOnMVar ->
    pure ()
  where
  loop :: OutChan Text -> IO ()
  loop chan = do
    t  <- readChan chan
    ok <- tryEvalNF t >>= \case
            Right t' -> emit t'
            -- Can't render the trace message. Report it on stderr
            -- as a bypass; if stderr itself refuses the write
            -- (closed, EPIPE, …), stay silent and keep going.
            Left ex  -> do
              _ <- try @IOException $ do
                     hPutStrLn stderr $
                       "Error rendering trace message: " ++ displayException ex
                     hFlush stderr
              pure True
    -- sink dead -> switch to drain
    (if ok then loop else drain) chan

  emit :: Text -> IO Bool
  emit str = do
    res <- try @IOException do
      TIO.hPutStrLn stdout str
      hFlush stdout
    case first @Either ioeGetErrorType res of
      Right ()              -> pure True
      Left InvalidArgument  -> pure True                  -- bad line: skip silently, keep printing
      Left ResourceVanished -> pure False                 -- EPIPE: sink gone
      Left IllegalOperation -> pure False                 -- closed handle: sink gone
      Left _                -> pure False                 -- unknown: treat as gone (conservative)

  -- no stdout, no stderr; still terminates
  drain :: OutChan a -> IO ()
  drain = forever . void . readChan

