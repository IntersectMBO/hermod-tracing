-- | Unit tests for "Hermod.AlarmBridge.Startup": the pure startup
--   self-check state machine (decoupled from IO/timing).
module Hermod.AlarmBridge.Test.Startup (tests) where

import           Hermod.AlarmBridge.Startup

import           Control.Monad (foldM_)
import           Test.Tasty
import           Test.Tasty.HUnit

tests :: TestTree
tests = testGroup "Startup"
  [ testCase "initialStartupCheck starts unpassed with zero failures" $
      initialStartupCheck @?= StartupCheck { scPassed = False, scFailures = 0 }

  , testCase "a single successful line immediately passes" $
      stepStartupCheck initialStartupCheck True @?=
        (StartupCheck { scPassed = True, scFailures = 0 }, StartupOk)

  , testCase "a single failed line is pending, not yet failed" $
      stepStartupCheck initialStartupCheck False @?=
        (StartupCheck { scPassed = False, scFailures = 1 }, StartupPending)

  , testCase (show (startupCheckLimit - 1) <> " consecutive failures are still pending") $ do
      let (sc, verdict) = iterate (\(sc', _) -> stepStartupCheck sc' False)
                                   (initialStartupCheck, StartupPending)
                            !! (startupCheckLimit - 1)
      scFailures sc @?= startupCheckLimit - 1
      verdict       @?= StartupPending

  , testCase (show startupCheckLimit <> " consecutive failures fail the check") $ do
      let (sc, verdict) = iterate (\(sc', _) -> stepStartupCheck sc' False)
                                   (initialStartupCheck, StartupPending)
                            !! startupCheckLimit
      scFailures sc @?= startupCheckLimit
      verdict       @?= StartupFailed

  , testCase "startupCheckLimit is 5 (guards against a silent threshold change)" $
      startupCheckLimit @?= 5

  , testCase "once passed, scPassed latches True forever -- a later isolated failure is not fatal" $ do
      let (afterPass, okVerdict) = stepStartupCheck initialStartupCheck True
      afterPass @?= StartupCheck { scPassed = True, scFailures = 0 }
      okVerdict @?= StartupOk
      -- Feed startupCheckLimit-many failures after the pass: verdict must stay
      -- StartupOk throughout, never StartupFailed, and scPassed must stay True.
      foldM_ (\sc _ -> do
                let (sc', verdict) = stepStartupCheck sc False
                verdict   @?= StartupOk
                scPassed sc' @?= True
                pure sc')
             afterPass
             [1 .. startupCheckLimit + 5]

  , testCase "failures don't accumulate once passed (scFailures stays at its pre-pass value)" $ do
      let (sc1, _) = stepStartupCheck initialStartupCheck False -- scFailures = 1
          (sc2, _) = stepStartupCheck sc1 True                  -- passes, scFailures untouched
          (sc3, _) = stepStartupCheck sc2 False                 -- post-pass failure: a no-op state change
      scFailures sc3 @?= scFailures sc2
  ]
