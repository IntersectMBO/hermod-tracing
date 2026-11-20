import           Test.Tasty
import           Test.Tasty.HUnit

import           Hermod.Tracing.Prometheus.Test.NetworkRun


main :: IO ()
main = defaultMain tests

-- The suite takes a few seconds; a hang fails it after one minute instead
-- of blocking CI.
tests :: TestTree
tests = localOption (mkTimeout (60 * 1000000)) $ testGroup "hermod-tracing-prometheus"
  [ testCase "testReleaseAfterInterruptedClose" $ do
      res <- testReleaseAfterInterruptedClose
      assertEqual "every connection served" (map (const True) res) res
  ]
