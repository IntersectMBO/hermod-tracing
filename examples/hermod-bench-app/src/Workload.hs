-- | The application's work: worker threads that compute, keep a live heap
--   busy, and trace events drawn from the cast.
module Workload
  ( Params (..)
  , Mode (..)
  , LiveHeap
  , newLiveHeap
  , runWorkers
  ) where

import           Cast
import           Tracers

import           Hermod.Tracing (traceWith)

import           Control.Concurrent (threadDelay)
import           Control.Concurrent.Async (forConcurrently)
import           Control.Exception (evaluate)
import           Control.Monad (when)
import           Data.Array (Array, listArray, (!))
import           Data.Array.IO (IOArray, getBounds, newListArray, writeArray)
import           Data.Bits (shiftL, shiftR, xor)
import qualified Data.Map.Strict as Map
import           Data.Word (Word64)
import           GHC.Clock (getMonotonicTimeNSec)


-- | How long the workers run.
data Mode
  = Iterations Int         -- ^ a fixed number of iterations per worker
  | Rate Double Double     -- ^ messages per second (all workers), for seconds

data Params = Params
  { pThreads    :: Int     -- ^ worker threads
  , pMode       :: Mode
  , pMessages   :: Int     -- ^ messages traced per iteration
  , pWork       :: Int     -- ^ units of pure work per iteration
  , pChurnEvery :: Int     -- ^ replace a live heap slot every that many iterations (0: never)
  , pSeed       :: Word64
  }

-- | Data that stays live for the whole run, slowly replaced, so that major
--   collections have something to copy.
newtype LiveHeap = LiveHeap (IOArray Int (Map.Map Int Int))

-- | One slot holds 1000 small boxed entries, about 80 KB.
slotEntries :: Int
slotEntries = 1000

mkSlot :: Word64 -> Map.Map Int Int
mkSlot s = Map.fromList
    [ (k, fromIntegral (w `shiftR` 16)) | (k, w) <- zip [0 .. slotEntries - 1] (iterate xorshift s) ]

-- | A live heap of about the given number of MB.
newLiveHeap :: Int -> Word64 -> IO LiveHeap
newLiveHeap mb seed = do
    let slots = max 1 (mb * 1024 * 1024 `div` (slotEntries * 80))
    xs <- mapM (evaluate . mkSlot) (take slots (iterate xorshift (seed + 1)))
    LiveHeap <$> newListArray (0, slots - 1) xs

churn :: LiveHeap -> Word64 -> IO ()
churn (LiveHeap arr) s = do
    (lo, hi) <- getBounds arr
    let i = lo + fromIntegral (s `mod` fromIntegral (hi - lo + 1))
    slot <- evaluate (mkSlot s)
    writeArray arr i slot

xorshift :: Word64 -> Word64
xorshift x0 =
    let x1 = x0 `xor` (x0 `shiftL` 13)
        x2 = x1 `xor` (x1 `shiftR` 7)
    in  x2 `xor` (x2 `shiftL` 17)

-- | Pure work that doesn't allocate.
work :: Int -> Word64 -> Word64
work n s0 = go n s0
  where
    go 0 !s = s
    go k !s = go (k - 1) (xorshift s)

-- | The events of all characters, each slot of the array a draw.
type Draws = Array Int (Word64 -> IO ())

mkDraws :: AppTracers -> Draws
mkDraws ts =
    let evs = concat
          [ lift naruto narutoEvents, lift kakashi kakashiEvents
          , lift sailorMoon sailorMoonEvents, lift sailorMercury sailorMercuryEvents
          , lift chihiro chihiroEvents, lift noFace noFaceEvents
          , lift goku gokuEvents, lift vegeta vegetaEvents
          , lift eren erenEvents, lift levi leviEvents ]
        slots = concat [ replicate w f | (w, f) <- evs ]
    in  listArray (0, length slots - 1) slots
  where
    lift sel = map (\(w, mk) -> (w, traceWith (sel ts) . mk))

-- | Runs the workers; returns the number of messages each traced.
runWorkers :: Params -> AppTracers -> LiveHeap -> IO [Int]
runWorkers p ts heap = do
    t0 <- getMonotonicTimeNSec
    forConcurrently [1 .. pThreads p] $ \w ->
      worker t0 (pSeed p + fromIntegral w * 0x9E3779B97F4A7C15)
  where
    draws = mkDraws ts
    nDraws = fromIntegral (length draws) :: Word64
    k = pMessages p

    worker t0 seed = go (0 :: Int) seed
      where
        go !i !s = do
          continue <- case pMode p of
            Iterations n -> pure (i < n)
            Rate rate secs -> do
              now <- getMonotonicTimeNSec
              let elapsed = fromIntegral (now - t0) / 1e9 :: Double
                  due = fromIntegral (i * k) / (rate / fromIntegral (pThreads p))
              when (due > elapsed) $ threadDelay (round ((due - elapsed) * 1e6))
              pure (elapsed < secs)
          if not continue
            then pure (i * k)
            else do
              let !s1 = work (pWork p) s
              s2 <- emit k s1
              when (pChurnEvery p > 0 && i `mod` pChurnEvery p == 0) $ churn heap s2
              go (i + 1) s2

    emit :: Int -> Word64 -> IO Word64
    emit 0 !s = pure s
    emit n !s = do
      let !s' = xorshift s
      (draws ! fromIntegral (s' `mod` nDraws)) (xorshift s')
      emit (n - 1) s'
