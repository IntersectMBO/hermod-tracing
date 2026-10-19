{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

-- | Reproduces IntersectMBO/hermod-tracing#22:
-- On Windows with a non-UTF-8 stdout encoding (CP437 under a console,
-- CP1252 otherwise), writing a Hiragana character throws
-- @commitAndReleaseBuffer: invalid argument (cannot encode character)@.
-- The legacy 'Cardano.Logging.Tracer.Standard.stdoutThread' let that
-- exception propagate through its @link@ and kill the process. The
-- hermod rewrite classifies it as @InvalidArgument@, skips the bad
-- line, and keeps printing.
--
-- The test redirects the real @stdout@ to a temp file, forces
-- @latin1@ on the stdout Handle (which can't encode さ, U+3055),
-- then runs the same harness twice:
--
--   * 'testStdoutTracerHiraganaSurvives' drives the production
--     'stdoutThread': thread survives, surrounding ASCII lines make
--     it to the file, no exception propagates.
--   * 'testStdoutTracerHiraganaDies' drives 'stdoutThreadWith' with
--     a catch-less emit (mirroring @trace-dispatcher-2.13.0@).
--     Thread dies on the Hiragana — asserted so, so this is the
--     "test the test" negative that pins the harness.
--
-- 'testStdoutTracerHiraganaFull' is survives AND NOT dies: both a
-- hermod regression that stops catching, AND a proposal to go back
-- to the catch-less legacy, break the suite.
module Hermod.Tracing.Test.Unit.StdoutTracer
  ( testStdoutTracerHiraganaFull
  ) where

import           Hermod.Tracing.Tracer.Standard (stdoutThread, stdoutThreadWith)

import           Control.Concurrent (threadDelay)
import           Control.Concurrent.Async (async, cancel, poll, waitCatch)
import           Control.Concurrent.Chan.Unagi.Bounded (OutChan, newChan, writeChan)
import           Control.Exception (bracket)
import           Data.Functor ((<&>))
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import           GHC.IO.Handle (hDuplicate, hDuplicateTo)
import           System.Directory (getTemporaryDirectory, removeFile)
import           System.IO (Handle, hClose, hFlush, hSetEncoding, latin1, openTempFile, stdout)

testStdoutTracerHiraganaFull :: IO Bool
testStdoutTracerHiraganaFull = and <$> sequenceA
  [ testStdoutTracerHiraganaSurvives
  , testStdoutTracerHiraganaDies <&> not
  ]

testStdoutTracerHiraganaSurvives :: IO Bool
testStdoutTracerHiraganaSurvives = testStdoutTracerHiragana stdoutThread

testStdoutTracerHiraganaDies :: IO Bool
testStdoutTracerHiraganaDies = testStdoutTracerHiragana $ stdoutThreadWith \str -> do
  TIO.hPutStrLn stdout str   -- no try
  hFlush stdout
  pure True

testStdoutTracerHiragana :: (OutChan T.Text -> IO ()) -> IO Bool
testStdoutTracerHiragana thread = do
  tmp           <- getTemporaryDirectory
  (path, tempH) <- openTempFile tmp "hermod-stdout-latin1-.log"

  -- Save stdout aside; redirect the real stdout FD to the temp file
  -- AND force latin1 on the stdout Handle (hDuplicateTo only moves
  -- the FD; the Handle's encoding is separate). Restore no matter what.

  let
    acquire :: IO Handle
    acquire = hDuplicate stdout

    release :: Handle -> IO ()
    release saved = do
      hDuplicateTo saved stdout
      hClose saved

  bracket acquire release \_ -> do
    hDuplicateTo tempH stdout
    hClose tempH
    hSetEncoding stdout latin1           -- CP1252-like: no Hiragana

    (inChan, outChan) <- newChan 2048
    as <- async (thread outChan)
    -- No `link`: we want to observe exceptions, not re-raise them.

    writeChan inChan "ASCII before"
    writeChan inChan "\12373\12435"      -- U+3055 U+3093 = さん
    writeChan inChan "ASCII after"

    threadDelay 200_000                  -- let the writer drain

    stillAlive <- poll as >>= \case
      Nothing         -> pure True
      Just (Right ()) -> pure False      -- unexpected clean exit
      Just (Left _)   -> pure False      -- EXCEPTION escaped — regression

    cancel as
    _ <- waitCatch @() as
    hFlush stdout

    contents <- TIO.readFile path
    removeFile path

    pure $ and
      [ stillAlive
      , T.isInfixOf "ASCII before" contents
      , T.isInfixOf "ASCII after"  contents
      , not (T.isInfixOf "\12373"  contents)
      ]
