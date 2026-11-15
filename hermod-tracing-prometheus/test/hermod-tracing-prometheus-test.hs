import           Test.Tasty
import           Test.Tasty.HUnit

import           Hermod.Tracing.Prometheus.Test.NetworkRun


main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "hermod-tracing-prometheus"
  [ testCase "testReleaseAfterInterruptedClose" $ do
      res <- testReleaseAfterInterruptedClose
      assertEqual "every connection served" (map (const True) res) res
  ]
