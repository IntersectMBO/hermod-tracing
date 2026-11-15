{-# LANGUAGE NumericUnderscores  #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Reproduces IntersectMBO/hermod-tracing#28 through the public
-- 'mkTCPServerRunner'. Each connection's handler arranges for a
-- 'TimeoutThread' to be thrown to its own thread shortly after it
-- returns, while the close handler waits in 'gracefulClose' for the
-- client's FIN: the same interleaving as a late kill from
-- 'withHandleKillThread'. The per-host connection slot must still be
-- released, so the connection after the limit is served.
module Hermod.Tracing.Prometheus.Test.NetworkRun
  ( testReleaseAfterInterruptedClose
  ) where

import           Hermod.Tracing.Prometheus.NetworkRun

import           Control.Concurrent (forkIO, killThread, myThreadId, threadDelay, throwTo)
import qualified Control.Exception as E
import           Control.Monad (forM, void)
import qualified Data.ByteString.Char8 as BS
import           Network.Socket
import           Network.Socket.ByteString (recv, sendAll)
import qualified System.TimeManager as T
import           System.Timeout (timeout)

-- | Opens one connection more than 'runConnLimitPerHost' allows at once,
-- one after the other, and returns whether each one was served.
testReleaseAfterInterruptedClose :: IO [Bool]
testReleaseAfterInterruptedClose = do
  port   <- freePort
  runner <- mkTCPServerRunner params (Just host) port server
  E.bracket (forkIO runner) killThread $ \_ ->
    forM [0 .. runConnLimitPerHost params] $ \_ -> served port
  where
    host   = "127.0.0.1"
    params = (defaultRunParams "test-prometheus-28") { runRateLimit = 0.0 }

    -- Serve one byte, then have the timeout exception delivered to this
    -- thread 100 ms later, when it is waiting for the client's FIN.
    server :: TimeoutServer ()
    server _ _ conn = do
      sendAll conn (BS.pack "x")
      me <- myThreadId
      void . forkIO $ threadDelay 100_000 >> throwTo me T.TimeoutThread

    -- A connection is served when its byte arrives; a refused one is
    -- closed by the server at once. The client keeps its side open for
    -- 500 ms, longer than the delay above and shorter than the graceful
    -- close timeout, so the exception lands inside 'gracefulClose'.
    served :: PortNumber -> IO Bool
    served port = do
      addr <- head <$> getAddrInfo (Just defaultHints { addrSocketType = Stream }) (Just host) (Just $ show port)
      E.bracket (openSocket addr) close $ \sock -> do
        connect sock (addrAddress addr)
        reply <- E.try (timeout 2_000_000 $ recv sock 1)
        threadDelay 500_000
        pure $ case reply of
          Right (Just bs)               -> bs == BS.pack "x"
          Right Nothing                 -> False
          Left (_ :: E.IOException)     -> False

    freePort :: IO PortNumber
    freePort = do
      addr <- head <$> getAddrInfo (Just defaultHints { addrSocketType = Stream }) (Just host) (Just "0")
      E.bracket (openSocket addr) close $ \sock -> do
        bind sock (addrAddress addr)
        socketPort sock
