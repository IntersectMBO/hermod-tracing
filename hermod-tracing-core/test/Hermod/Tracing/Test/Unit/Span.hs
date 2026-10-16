{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Hermod.Tracing.Test.Unit.Span
  ( testSpanHappy
  , testSpanSyncException
  , testSpanAsyncFromOtherThread
  , testSpanAndMetric
  , testSpanNested
  , testSpanForceCatchesLazyCrash
  , testSpanLazyLetsCrashEscape
  ) where

import           Hermod.Tracing
import           Hermod.Tracing.Span (SpanError (..), SpanTrace (..), withSpan,
                   withSpanAndMetric, withSpanLazy)

import           Control.Concurrent (forkIO, killThread, myThreadId, threadDelay)
import           Control.Concurrent.MVar (newEmptyMVar, putMVar, readMVar)
import           Control.Exception (SomeException, try)
import           Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import qualified Data.Text as Text

-- Tracer that captures raw SpanTrace values into an IORef.
captureTrace :: IORef [SpanTrace] -> Trace IO SpanTrace
captureTrace ref = Trace $ arrow $ emit $ \case
  (_, Right s) -> modifyIORef' ref (s :)
  (_, Left _)  -> pure ()

testSpanHappy :: IO Bool
testSpanHappy = do
  ref <- newIORef []
  let tr = captureTrace ref
  _ <- withSpan tr "happy" $ do
    threadDelay 5_000
    pure (42 :: Int)
  evs <- reverse <$> readIORef ref
  pure $ case evs of
    [SpanBegin _ "happy", SpanEnd _ "happy" ms Nothing] -> ms > 0
    _ -> False

testSpanSyncException :: IO Bool
testSpanSyncException = do
  ref <- newIORef []
  let tr = captureTrace ref
  r <- try @SomeException $ withSpan tr "boom" (error "oops" :: IO Int)
  evs <- reverse <$> readIORef ref
  pure $ case (r, evs) of
    ( Left _
      , [ SpanBegin _ "boom"
        , SpanEnd _ "boom" _ (Just (SpanError "ErrorCall" ""))
        ]
      ) -> True
    _ -> False

-- Sibling thread kills the span-running thread. Expect SpanBegin +
-- SpanEnd with an "async:" exception tag, and the exception rethrown.
testSpanAsyncFromOtherThread :: IO Bool
testSpanAsyncFromOtherThread = do
  ref         <- newIORef []
  let tr      = captureTrace ref
  childTidMV  <- newEmptyMVar
  outcomeMV   <- newEmptyMVar
  _ <- forkIO $ do
    tid <- myThreadId
    putMVar childTidMV tid
    r <- try @SomeException $ withSpan tr "longRunning" $ do
      threadDelay 2_000_000
      pure ()
    putMVar outcomeMV r
  childTid <- readMVar childTidMV
  threadDelay 50_000           -- let SpanBegin fire first
  killThread childTid
  outcome <- readMVar outcomeMV
  threadDelay 10_000
  evs <- reverse <$> readIORef ref
  pure $ case (outcome, evs) of
    ( Left _
      , [ SpanBegin _ "longRunning"
        , SpanEnd _ "longRunning" _ (Just (SpanError tag ""))
        ]
      ) -> "async:" `Text.isPrefixOf` tag
    _ -> False

testSpanAndMetric :: IO Bool
testSpanAndMetric = do
  ref <- newIORef []
  let tr = captureTrace ref
  _ <- withSpanAndMetric tr "metric" (pure (0 :: Int))
  evs <- reverse <$> readIORef ref
  pure $ case evs of
    [SpanBegin _ "metric", SpanEndWithMetric _ "metric" _ Nothing] -> True
    _ -> False

testSpanNested :: IO Bool
testSpanNested = do
  ref <- newIORef []
  let tr = captureTrace ref
  _ <- withSpan tr "outer" $
         withSpan tr "inner" (pure (0 :: Int))
  evs <- reverse <$> readIORef ref
  pure $ case evs of
    [ SpanBegin outerA "outer"
      , SpanBegin innerA "inner"
      , SpanEnd   innerB "inner" _ Nothing
      , SpanEnd   outerB "outer" _ Nothing
      ] -> outerA == outerB && innerA == innerB && outerA /= innerA
    _ -> False

-- withSpan forces the result: a crash-on-force thunk is attributed to the span.
testSpanForceCatchesLazyCrash :: IO Bool
testSpanForceCatchesLazyCrash = do
  ref <- newIORef []
  let tr = captureTrace ref
  r <- try @SomeException $ withSpan tr "lazyCrash" $
         pure (error "deferred boom" :: Int)
  evs <- reverse <$> readIORef ref
  pure $ case (r, evs) of
    ( Left _
      , [ SpanBegin _ "lazyCrash"
        , SpanEnd _ "lazyCrash" _ (Just (SpanError "ErrorCall" ""))
        ]
      ) -> True
    _ -> False

-- withSpanLazy skips the force; the span looks clean and the caller crashes.
testSpanLazyLetsCrashEscape :: IO Bool
testSpanLazyLetsCrashEscape = do
  ref <- newIORef []
  let tr = captureTrace ref
  thunk <- withSpanLazy tr "lazyEscape" $
             pure (error "deferred boom" :: Int)
  evs <- reverse <$> readIORef ref
  crashed <- try @SomeException (pure $! thunk)
  pure $ case (crashed, evs) of
    ( Left _
      , [ SpanBegin _ "lazyEscape"
        , SpanEnd _ "lazyEscape" _ Nothing
        ]
      ) -> True
    _ -> False
