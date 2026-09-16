-- | Unit tests for "Hermod.AlarmBridge.Deliver": the pure HTTP-response
--   classification, the pure backoff schedule, and the injectable
--   retry/queue logic -- all exercised without any real socket or real time
--   delay.
module Hermod.AlarmBridge.Test.Deliver (tests) where

import           Hermod.AlarmBridge.Classify (IngressRequest (..), classifyReConStopped)
import           Hermod.AlarmBridge.Deliver

import           Data.IORef
import           Data.Time.Calendar (fromGregorian)
import           Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import qualified Data.Text.Encoding as TE
import           Test.Tasty
import           Test.Tasty.HUnit

t0 :: UTCTime
t0 = UTCTime (fromGregorian 2025 12 1) (secondsToDiffTime 0)

sampleRequest :: IngressRequest
sampleRequest = classifyReConStopped t0 1

tests :: TestTree
tests = testGroup "Deliver"
  [ parseStatusCodeTests
  , classifyHttpResponseTests
  , backoffScheduleTests
  , deliverWithRetryTests
  , deliveryQueueTests
  ]

--------------------------------------------------------------------------------
-- parseStatusCode
--------------------------------------------------------------------------------

parseStatusCodeTests :: TestTree
parseStatusCodeTests = testGroup "parseStatusCode"
  [ testCase "parses a 200 status line" $
      parseStatusCode (TE.encodeUtf8 "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n") @?= Just 200
  , testCase "parses a 404 status line" $
      parseStatusCode (TE.encodeUtf8 "HTTP/1.1 404 Not Found\r\n\r\n") @?= Just 404
  , testCase "parses a status line with no reason phrase" $
      parseStatusCode (TE.encodeUtf8 "HTTP/1.1 204\r\n\r\n") @?= Just 204
  , testCase "returns Nothing for garbage input" $
      parseStatusCode (TE.encodeUtf8 "not an http response") @?= Nothing
  , testCase "returns Nothing for empty input" $
      parseStatusCode (TE.encodeUtf8 "") @?= Nothing
  , testCase "returns Nothing when the status code isn't numeric" $
      parseStatusCode (TE.encodeUtf8 "HTTP/1.1 OK Fine\r\n\r\n") @?= Nothing
  ]

--------------------------------------------------------------------------------
-- classifyHttpResponse
--------------------------------------------------------------------------------

classifyHttpResponseTests :: TestTree
classifyHttpResponseTests = testGroup "classifyHttpResponse"
  [ testCase "2xx is Delivered" $
      mapM_ (\line -> classifyHttpResponse (TE.encodeUtf8 line) @?= Delivered)
            ["HTTP/1.1 200 OK\r\n\r\n", "HTTP/1.1 201 Created\r\n\r\n", "HTTP/1.1 299 Weird\r\n\r\n"]

  , testCase "4xx is a PermanentFailure" $
      case classifyHttpResponse (TE.encodeUtf8 "HTTP/1.1 404 Not Found\r\n\r\n") of
        PermanentFailure msg -> assertBool "message should mention the status" ("404" `elem` words msg)
        other                -> assertFailure ("expected PermanentFailure, got " <> show other)

  , testCase "5xx is a RetryableFailure" $
      case classifyHttpResponse (TE.encodeUtf8 "HTTP/1.1 503 Service Unavailable\r\n\r\n") of
        RetryableFailure msg -> assertBool "message should mention the status" ("503" `elem` words msg)
        other                -> assertFailure ("expected RetryableFailure, got " <> show other)

  , testCase "an unparseable response is a RetryableFailure" $
      case classifyHttpResponse (TE.encodeUtf8 "garbage") of
        RetryableFailure _ -> pure ()
        other               -> assertFailure ("expected RetryableFailure, got " <> show other)

  , testCase "a 1xx status is a RetryableFailure (not 2xx success)" $
      case classifyHttpResponse (TE.encodeUtf8 "HTTP/1.1 100 Continue\r\n\r\n") of
        RetryableFailure _ -> pure ()
        other               -> assertFailure ("expected RetryableFailure, got " <> show other)
  ]

--------------------------------------------------------------------------------
-- backoffSchedule
--------------------------------------------------------------------------------

backoffScheduleTests :: TestTree
backoffScheduleTests = testGroup "backoffSchedule"
  [ testCase "defaultRetryPolicy's fields" $ do
      rpMaxAttempts defaultRetryPolicy      @?= 6
      rpInitialBackoffUs defaultRetryPolicy @?= 500000
      rpMaxBackoffUs defaultRetryPolicy     @?= 30000000

  , testCase "defaultRetryPolicy's schedule doubles, has length maxAttempts-1" $ do
      let sched = backoffSchedule defaultRetryPolicy
      length sched @?= 5
      sched @?= [500000, 1000000, 2000000, 4000000, 8000000]

  , testCase "the schedule is capped at rpMaxBackoffUs" $ do
      let policy = RetryPolicy { rpMaxAttempts = 8, rpInitialBackoffUs = 10, rpMaxBackoffUs = 15 }
      backoffSchedule policy @?= [10, 15, 15, 15, 15, 15, 15]

  , testCase "zero or one max attempts yields an empty schedule" $ do
      backoffSchedule (defaultRetryPolicy { rpMaxAttempts = 0 }) @?= []
      backoffSchedule (defaultRetryPolicy { rpMaxAttempts = 1 }) @?= []
  ]

--------------------------------------------------------------------------------
-- deliverWithRetry
--------------------------------------------------------------------------------

-- | A scripted 'DeliverOne': pops one result off the front of an 'IORef'
--   list per call (and errors loudly if the test asked for more attempts
--   than it scripted -- a bug in the test, not the code under test), while
--   also recording how many times it was called.
scriptedDeliverOne :: IORef [DeliverResult] -> IORef Int -> DeliverOne
scriptedDeliverOne resultsRef countRef _req = do
  modifyIORef' countRef (+ 1)
  results <- readIORef resultsRef
  case results of
    (r : rest) -> writeIORef resultsRef rest >> pure r
    []         -> error "scriptedDeliverOne: ran out of scripted results"

-- | Records every delay it's asked to \"sleep\" for, without actually
--   sleeping.
recordingSleep :: IORef [Int] -> Int -> IO ()
recordingSleep delaysRef d = modifyIORef' delaysRef (++ [d])

deliverWithRetryTests :: TestTree
deliverWithRetryTests = testGroup "deliverWithRetry"
  [ testCase "succeeds immediately with no retries needed" $ do
      resultsRef <- newIORef [Delivered]
      countRef   <- newIORef 0
      delaysRef  <- newIORef []
      ok <- deliverWithRetry defaultRetryPolicy (recordingSleep delaysRef)
              (scriptedDeliverOne resultsRef countRef) sampleRequest
      ok @?= True
      readIORef countRef  >>= (@?= 1)
      readIORef delaysRef >>= (@?= [])

  , testCase "retries a RetryableFailure, using the documented backoff schedule, then succeeds" $ do
      resultsRef <- newIORef [RetryableFailure "x", RetryableFailure "x", Delivered]
      countRef   <- newIORef 0
      delaysRef  <- newIORef []
      ok <- deliverWithRetry defaultRetryPolicy (recordingSleep delaysRef)
              (scriptedDeliverOne resultsRef countRef) sampleRequest
      ok @?= True
      readIORef countRef  >>= (@?= 3)
      readIORef delaysRef >>= (@?= take 2 (backoffSchedule defaultRetryPolicy))

  , testCase "gives up immediately on a PermanentFailure, without sleeping or retrying" $ do
      resultsRef <- newIORef [PermanentFailure "bad request"]
      countRef   <- newIORef 0
      delaysRef  <- newIORef []
      ok <- deliverWithRetry defaultRetryPolicy (recordingSleep delaysRef)
              (scriptedDeliverOne resultsRef countRef) sampleRequest
      ok @?= False
      readIORef countRef  >>= (@?= 1)
      readIORef delaysRef >>= (@?= [])

  , testCase "gives up after exhausting all retries, having attempted exactly rpMaxAttempts times" $ do
      resultsRef <- newIORef (replicate (rpMaxAttempts defaultRetryPolicy) (RetryableFailure "still down"))
      countRef   <- newIORef 0
      delaysRef  <- newIORef []
      ok <- deliverWithRetry defaultRetryPolicy (recordingSleep delaysRef)
              (scriptedDeliverOne resultsRef countRef) sampleRequest
      ok @?= False
      readIORef countRef  >>= (@?= rpMaxAttempts defaultRetryPolicy)
      readIORef delaysRef >>= (@?= backoffSchedule defaultRetryPolicy)
  ]

--------------------------------------------------------------------------------
-- DeliveryQueue / startDeliveryWorker
--------------------------------------------------------------------------------

deliveryQueueTests :: TestTree
deliveryQueueTests = testGroup "startDeliveryWorker / waitForQueueDrain"
  [ testCase "enqueued requests are delivered and the queue drains to zero" $ do
      deliveredRef <- newIORef []
      let alwaysDeliver req = modifyIORef' deliveredRef (++ [req]) >> pure Delivered
      dq <- startDeliveryWorker defaultRetryPolicy alwaysDeliver
      mapM_ (dqEnqueue dq) [sampleRequest, sampleRequest, sampleRequest]
      waitForQueueDrain dq 2000000 -- 2s, generous for three immediate successes
      pending <- dqPendingCount dq
      dqShutdown dq
      pending @?= 0
      delivered <- readIORef deliveredRef
      length delivered @?= 3
  ]
