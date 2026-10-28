{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Reproduces IntersectMBO/hermod-tracing#22 by driving the public
-- 'standardTracer' end-to-end: redirects the real @stdout@ to a temp
-- file, forces @latin1@ on the stdout Handle (which can't encode さ,
-- U+3055), and sends ASCII \/ Hiragana \/ ASCII messages through the
-- tracer. The thread must survive the Hiragana write; the surrounding
-- ASCII lines must land in the file.
module Hermod.Tracing.Test.Unit.StdoutTracer
  ( testStdoutTracerHiraganaSurvives
  ) where

import           Hermod.Tracing

import qualified Control.Tracer as CT

import           Control.Concurrent (threadDelay)
import           Control.Exception (bracket)
import qualified Data.Text as Text
import qualified Data.Text.IO as TIO
import           GHC.IO.Handle (hDuplicate, hDuplicateTo)
import           System.Directory (getTemporaryDirectory, removeFile)
import           System.IO (Handle, hClose, hFlush, hSetEncoding, latin1, openTempFile, stdout)

testStdoutTracerHiraganaSurvives :: IO Bool
testStdoutTracerHiraganaSurvives = do
  tmp           <- getTemporaryDirectory
  (path, tempH) <- openTempFile tmp "hermod-stdout-latin1-.log"

  let
    acquire :: IO Handle
    acquire = hDuplicate stdout

    release :: Handle -> IO ()
    release saved = do
      hDuplicateTo saved stdout
      hClose saved

  bracket acquire release $ \_ -> do
    hDuplicateTo tempH stdout
    hClose tempH
    hSetEncoding stdout latin1           -- CP1252-like: no Hiragana

    tr <- standardTracer :: IO (Trace IO FormattedMessage)
    -- Spawn the stdout writer thread. 'standardTracer' only spawns on
    -- 'TCReset'; the public 'traceWith' carries only Right-side data,
    -- so we inject the control message through the underlying
    -- contra-tracer directly.
    let Trace underlying = tr
    CT.traceWith underlying (emptyLoggingContext, Left TCReset)

    traceWith tr (FormattedHuman False "ASCII before")
    traceWith tr (FormattedHuman False "\12373\12435")   -- U+3055 U+3093 = さん
    traceWith tr (FormattedHuman False "ASCII after")

    threadDelay 2_000_000                -- bumped for slow CI machines

    hFlush stdout
    contents <- TIO.readFile path
    removeFile path

    pure $ and
      [ Text.isInfixOf "ASCII before" contents
      , Text.isInfixOf "ASCII after"  contents
      , not (Text.isInfixOf "\12373"  contents)
      ]
