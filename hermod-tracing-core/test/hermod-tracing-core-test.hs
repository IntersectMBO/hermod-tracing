{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-unused-imports  #-}

import           Prelude hiding (readFile, writeFile)

import           Data.Aeson
import qualified Data.ByteString.Char8 as BS
import           Data.Text (Text, breakOn, replace, stripEnd)
import           Data.Text.Encoding
import           Data.Text.IO (readFile)
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck

import           Hermod.Tracing
import           Hermod.Tracing.Test.Oracles
import           Hermod.Tracing.Test.Script
import           Hermod.Tracing.Test.Tracer
import           Hermod.Tracing.Test.Unit.Aggregation
import           Hermod.Tracing.Test.Unit.ConfigFile
import           Hermod.Tracing.Test.Unit.Configuration
import           Hermod.Tracing.Test.Unit.DataPoint
import           Hermod.Tracing.Test.Unit.Documentation
import           Hermod.Tracing.Test.Unit.EKG
import           Hermod.Tracing.Test.Unit.FrequencyLimiting
import           Hermod.Tracing.Test.Unit.Routing
import           Hermod.Tracing.Test.Unit.Trivial


main :: IO ()
main = defaultMain tests

-- Add unitTests to the main test group
tests :: TestTree
tests = testGroup "Tests"
  [ unitTests
  , localTests
  ]

unitTests :: TestTree
unitTests = testGroup "hermod-tracing-core-unit-tests"
    [
        testCase "testTrivial1" $ do
        res <- test1
        bres <- testLoggingMessagesEq res test1Res
        assertBool "testTrivial1" bres
    , testCase "testTrivial2" $ do
        res <- test2
        bres <- testLoggingMessagesEq res test2Res
        assertBool "testTrivial2" bres
    , testCase "testAggregation" $ do
        res <- testAggregation
        bres <- testLoggingMessagesEq res testAggResult
        assertBool "testAggregation" bres
    , testCase "testRouting" $ do
        res <- testRouting
        bres <- testLoggingMessagesEq res testRoutingResult
        assertBool "testRouting" bres
    , testCase "testConfig" $ do
        res <- testConfig
        bres <- testLoggingMessagesEq res testConfigResult
        assertBool "testConfig" bres
    , testCase "testConfigFileParsing" $ do
        res <- testConfigFileParsing
        assertEqual "testConfigFileParsing"
            (show testConfigFileParsingResult)
            (show res)
    , testCase "testDocGeneration" $ do
        actual <- docTracers
        expected <- readFile "test/data/docGeneration.md"
        let actual' = fst $ breakOn "Configuration:" actual
        assertEqual "testDocGeneration"
            (stripEnd expected)
            (stripEnd actual')
    , testCase "testEKG" $ do
        res <- testEKG
        assertBool "testEKG" (res == 1000)
    , testCase "testDatapoint" $ do
        res <- testDataPoint
        assertBool "testDatapoint" (show res == testDataPointResult)
    , testCase "testLimiting" $ do
        _res <- testLimiting
        assertBool "testLimiting" True -- currently not verified
    ]

localTests :: TestTree
localTests = localOption (QuickCheckTests 10) $ testGroup "hermod-tracing-core"
    [ testProperty "single-threaded send tests" $
        runScriptSimple 1.0 oracleMessages
    , testProperty "multi-threaded send tests" $
        runScriptMultithreaded 1.0 oracleMessages
    --  , testProperty "multi-threaded send tests with reconfiguration" $
    --      runScriptMultithreadedWithReconfig 1.0 oracleMessages
    , testProperty "reconfiguration stress test" $
        runScriptMultithreadedWithConstantReconfig 1.0 (\ _ _ -> property True)
    ]
