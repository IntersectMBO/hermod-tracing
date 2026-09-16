-- | Delivers an 'IngressRequest' to cardano-tracer's alarm ingress
--   endpoint. The actual wire transport is a hand-written HTTP\/1.1 POST
--   over a raw 'Network.Socket.Socket' -- deliberately not using
--   @http-client@ or any other heavyweight HTTP-client dependency, to keep
--   this package's dependency footprint tiny.
--
--   The "how do I attempt one delivery" primitive ('DeliverOne') is a plain
--   function, injected everywhere it's used, so tests can substitute an
--   in-memory collector instead of a real socket. The retry\/backoff logic
--   ('deliverWithRetry') is itself pure-ish: both the delivery primitive
--   and the sleep action are parameters, so it too can be tested without
--   real sockets or real time delays.
module Hermod.AlarmBridge.Deliver
  ( DeliverResult (..)
  , DeliverOne
  , httpDeliverOne
  , parseStatusCode
  , classifyHttpResponse
  , RetryPolicy (..)
  , defaultRetryPolicy
  , backoffSchedule
  , deliverWithRetry
  , DeliveryQueue (..)
  , startDeliveryWorker
  , waitForQueueDrain
  ) where

import           Hermod.AlarmBridge.Classify (IngressRequest (..))

import           Control.Concurrent (forkIO, killThread, threadDelay)
import           Control.Concurrent.STM (atomically, modifyTVar', newTQueueIO, newTVarIO,
                   readTQueue, readTVarIO, writeTQueue)
import           Control.Exception (IOException, bracket, try)
import           Control.Monad (forever)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as BL
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import           Network.Socket (AddrInfo (..), HostName, PortNumber, Socket, SocketType (Stream),
                   close, connect, defaultHints, getAddrInfo, socket)
import qualified Network.Socket.ByteString as NSB
import           System.IO (hPutStrLn, stderr)
import           System.Timeout (timeout)

-- | The outcome of one delivery attempt.
data DeliverResult
  = Delivered
    -- ^ 2xx response.
  | RetryableFailure String
    -- ^ Connection failure, or a 5xx (or otherwise unparseable) response.
  | PermanentFailure String
    -- ^ 4xx response: logged once and dropped, never retried.
  deriving stock (Show, Eq)

-- | "Attempt to deliver this one request" -- swappable so tests can
--   substitute an in-memory collector for the real socket-based
--   implementation.
type DeliverOne = IngressRequest -> IO DeliverResult

-- | Overall wall-clock budget for one delivery attempt: connecting to the
--   tracer, sending the request, and reading the response to completion.
--   Applied as a single deadline around the whole exchange (via
--   'System.Timeout.timeout') rather than as separate connect\/send\/recv
--   socket options -- the @network@ package's cross-platform socket-option
--   support doesn't cover receive\/send timeouts uniformly, whereas
--   'System.Timeout.timeout' is a portable, dependency-free way to bound
--   any of these phases hanging (a reachable-but-wedged tracer that accepts
--   the connection but never responds, in particular). Comfortably above a
--   healthy round trip, and well under 'rpMaxBackoffUs', so a hang falls
--   back into the normal retry\/backoff path instead of overshadowing it.
httpTimeoutUs :: Int
httpTimeoutUs = 10000000 -- 10s

-- | The real implementation: hand-rolled HTTP\/1.1 POST to
--   @/alarms/v1/events@ over a plain TCP socket. @mToken@, when present, is
--   sent as @Authorization: Bearer \<token\>@, per the design doc's
--   Producer ingress section; 'Nothing' sends no @Authorization@ header at
--   all, which only cardano-tracer's "open producer" mode accepts.
httpDeliverOne :: HostName -> PortNumber -> Maybe Text -> DeliverOne
httpDeliverOne host port mToken req = do
  result <- try (timeout httpTimeoutUs attempt)
  case result of
    Left (e :: IOException) -> pure (RetryableFailure ("connection failure: " <> show e))
    Right Nothing            ->
      pure (RetryableFailure ("timed out after " <> show httpTimeoutUs <> "us waiting for cardano-tracer"))
    Right (Just respBytes)   -> pure (classifyHttpResponse respBytes)
 where
  attempt = withConnection host port $ \sock -> do
    NSB.sendAll sock requestBytes
    recvAll sock

  bodyBytes = BL.toStrict (Aeson.encode req)
  authHeader = case mToken of
    Nothing    -> mempty
    Just token -> "Authorization: Bearer " <> TE.encodeUtf8 token <> "\r\n"
  requestBytes = BS.concat
    [ "POST /alarms/v1/events HTTP/1.1\r\n"
    , "Host: ", BS8.pack host, "\r\n"
    , authHeader
    , "Content-Type: application/json\r\n"
    , "Content-Length: ", BS8.pack (show (BS.length bodyBytes)), "\r\n"
    , "Connection: close\r\n"
    , "\r\n"
    , bodyBytes
    ]

withConnection :: HostName -> PortNumber -> (Socket -> IO a) -> IO a
withConnection host port action = do
  addrInfos <- getAddrInfo (Just hints) (Just host) (Just (show port))
  case addrInfos of
    []               -> ioError (userError ("hermod-alarm-bridge: no address found for host " <> host))
    (addrInfo : _) -> bracket
      (socket (addrFamily addrInfo) (addrSocketType addrInfo) (addrProtocol addrInfo))
      close
      (\sock -> connect sock (addrAddress addrInfo) >> action sock)
 where
  hints = defaultHints { addrSocketType = Stream }

-- | Read until the peer closes the connection (we always send
--   @Connection: close@, so this is exactly the full response).
recvAll :: Socket -> IO BS.ByteString
recvAll sock = go mempty
 where
  chunkSize = 4096
  go acc = do
    chunk <- NSB.recv sock chunkSize
    if BS.null chunk then pure acc else go (acc <> chunk)

-- | Parse the numeric status code out of an HTTP\/1.x response's status
--   line, e.g. @"HTTP/1.1 201 Created\r\n..."@ -> @Just 201@. Pure, so it's
--   testable by feeding in canned response bytes without a real socket.
parseStatusCode :: BS.ByteString -> Maybe Int
parseStatusCode resp =
  case BS8.words (BS8.takeWhile (\c -> c /= '\r' && c /= '\n') resp) of
    (_httpVersion : codeBytes : _) -> readInt (BS8.unpack codeBytes)
    _                              -> Nothing
 where
  readInt s = case reads s of
    [(n, "")] -> Just n
    _         -> Nothing

-- | Map a raw HTTP response to a 'DeliverResult': 2xx succeeds, 4xx is
--   permanent (log-and-drop), 5xx (or an unparseable response) is
--   retryable.
classifyHttpResponse :: BS.ByteString -> DeliverResult
classifyHttpResponse resp = case parseStatusCode resp of
  Just code
    | code >= 200 && code < 300 -> Delivered
    | code >= 400 && code < 500 -> PermanentFailure ("HTTP " <> show code)
    | code >= 500 && code < 600 -> RetryableFailure ("HTTP " <> show code)
    | otherwise                 -> RetryableFailure ("unexpected HTTP status: " <> show code)
  Nothing -> RetryableFailure ("unparseable HTTP response (first 200 bytes): " <> show (BS.take 200 resp))

-- | Bounded, capped-exponential retry policy.
data RetryPolicy = RetryPolicy
  { rpMaxAttempts      :: !Int
    -- ^ Total attempts, including the first (not-yet-a-retry) one.
  , rpInitialBackoffUs :: !Int
  , rpMaxBackoffUs     :: !Int
  }
  deriving stock (Show, Eq)

defaultRetryPolicy :: RetryPolicy
defaultRetryPolicy = RetryPolicy
  { rpMaxAttempts      = 6
  , rpInitialBackoffUs = 500000
  , rpMaxBackoffUs     = 30000000
  }

-- | The (pure) sequence of backoff delays, in microseconds, between
--   successive retry attempts -- length @rpMaxAttempts - 1@.
backoffSchedule :: RetryPolicy -> [Int]
backoffSchedule RetryPolicy{..} =
  take (max 0 (rpMaxAttempts - 1)) (iterate (\d -> min rpMaxBackoffUs (d * 2)) rpInitialBackoffUs)

-- | Attempt to deliver one request, retrying a 'RetryableFailure' with
--   capped exponential backoff up to 'rpMaxAttempts' times in total, and
--   giving up immediately (logged once, not retried) on a
--   'PermanentFailure'. Returns 'True' iff eventually delivered.
--
--   Both @sleep@ and @deliverOne@ are injected, so this is testable without
--   real time delays or a real socket (e.g. @sleep = const (pure ())@ and
--   @deliverOne@ backed by an in-memory collector or a scripted sequence of
--   results).
deliverWithRetry :: RetryPolicy -> (Int -> IO ()) -> DeliverOne -> IngressRequest -> IO Bool
deliverWithRetry policy sleep deliverOne req = go (backoffSchedule policy)
 where
  eventId = Text.unpack (irSourceEventId req)

  go delays = do
    result <- deliverOne req
    case result of
      Delivered -> pure True
      PermanentFailure msg -> do
        hPutStrLn stderr $
          "hermod-alarm-bridge: dropping alarm " <> eventId <> " (permanent failure: " <> msg <> ")"
        pure False
      RetryableFailure msg -> case delays of
        [] -> do
          hPutStrLn stderr $
            "hermod-alarm-bridge: giving up on alarm " <> eventId
              <> " after exhausting retries (last failure: " <> msg <> ")"
          pure False
        (delayUs : rest) -> do
          hPutStrLn stderr $
            "hermod-alarm-bridge: transient failure delivering alarm " <> eventId
              <> " (" <> msg <> "), retrying in " <> show delayUs <> "us"
          sleep delayUs
          go rest

-- | A running delivery worker: an unbounded (bounded only by process
--   memory) in-memory queue of not-yet-delivered requests, drained
--   sequentially by a single background thread through 'deliverWithRetry'.
--   This is what keeps transient cardano-tracer unavailability from
--   dropping events or crashing the bridge -- a stuck delivery just makes
--   later events wait in memory instead.
data DeliveryQueue = DeliveryQueue
  { dqEnqueue      :: IngressRequest -> IO ()
    -- ^ Never blocks on delivery; just appends to the in-memory queue.
  , dqShutdown     :: IO ()
    -- ^ Stops the worker thread. Best-effort: does not wait for the queue
    --   to drain first (see 'waitForQueueDrain' for that).
  , dqPendingCount :: IO Int
    -- ^ Approximate number of items enqueued but not yet delivered or
    --   dropped.
  }

startDeliveryWorker :: RetryPolicy -> DeliverOne -> IO DeliveryQueue
startDeliveryWorker policy deliverOne = do
  queue      <- newTQueueIO
  pendingRef <- newTVarIO (0 :: Int)
  tid <- forkIO $ forever $ do
    req <- atomically (readTQueue queue)
    _   <- deliverWithRetry policy threadDelay deliverOne req
    atomically (modifyTVar' pendingRef (subtract 1))
  pure DeliveryQueue
    { dqEnqueue = \req -> atomically $ do
        writeTQueue queue req
        modifyTVar' pendingRef (+ 1)
    , dqShutdown = killThread tid
    , dqPendingCount = readTVarIO pendingRef
    }

-- | Best-effort: block (polling) until the queue drains to zero pending
--   items, or @maxWaitUs@ microseconds elapse, whichever comes first.
--   Intended to be called just before the bridge process exits, so
--   ordinarily queued alarms get a chance to be delivered.
waitForQueueDrain :: DeliveryQueue -> Int -> IO ()
waitForQueueDrain dq maxWaitUs = go (max 1 (maxWaitUs `div` pollIntervalUs))
 where
  pollIntervalUs = 100000 :: Int
  go :: Int -> IO ()
  go 0 = pure ()
  go n = do
    pending <- dqPendingCount dq
    if pending <= 0
      then pure ()
      else threadDelay pollIntervalUs >> go (n - 1)
