-- | Unit tests for "Hermod.AlarmBridge.Rules": parsing the optional
--   @--rules@ YAML file into per-formula-index overrides.
module Hermod.AlarmBridge.Test.Rules (tests) where

import           Hermod.AlarmBridge.Rules
import           Hermod.AlarmBridge.Severity (Severity (..))

import           Control.Exception (bracket)
import           Data.Either (isLeft)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import           Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import           System.Directory (getTemporaryDirectory, removeFile)
import           System.IO (hClose, openTempFile)
import           Test.Tasty
import           Test.Tasty.HUnit

-- | Exactly the example from "Hermod.AlarmBridge.Rules"'s own module
--   docstring.
validYaml :: BS.ByteString
validYaml = BS8.pack $ unlines
  [ "0:"
  , "  ruleId: node-set-invariant"
  , "  severity: warning"
  , "  summary: \"Node set contains an unexpected node\""
  , "2:"
  , "  severity: critical"
  ]

tests :: TestTree
tests = testGroup "Rules"
  [ parseTests
  , loadTests
  ]

parseTests :: TestTree
parseTests = testGroup "parseRuleOverrides (pure)"
  [ testCase "parses the documented example into the expected overrides" $
      case parseRuleOverrides validYaml of
        Left err -> assertFailure ("expected Right, got Left " <> err)
        Right m  -> do
          Map.keys m @?= [0, 2]
          lookupOverride 0 m @?= Just RuleOverride
            { roRuleId   = Just "node-set-invariant"
            , roSeverity = Just Warning
            , roSummary  = Just "Node set contains an unexpected node"
            }
          lookupOverride 2 m @?= Just RuleOverride
            { roRuleId = Nothing, roSeverity = Just Critical, roSummary = Nothing }

  , testCase "a formula index with no override present falls back to Nothing (caller applies defaults)" $
      case parseRuleOverrides validYaml of
        Left err -> assertFailure ("expected Right, got Left " <> err)
        Right m  -> lookupOverride 99 m @?= Nothing

  , testCase "an empty object parses to emptyRuleOverrides" $
      parseRuleOverrides "{}" @?= Right emptyRuleOverrides

  , testCase "a non-integer top-level key is a hard error, not silently dropped" $
      case parseRuleOverrides (BS8.pack "O:\n  severity: warning\n") of
        Left err -> assertBool ("error should mention the offending key, got: " <> err)
                      ("non-integer" `isInfixOf` err || "O" `isInfixOf` err)
        Right m  -> assertFailure ("expected Left for a non-integer key, got Right " <> show m)

  , testCase "one bad key among otherwise-good ones is still a hard error (never a partial map)" $
      case parseRuleOverrides (validYaml <> BS8.pack "notAnInt:\n  severity: error\n") of
        Left _  -> pure ()
        Right m -> assertFailure ("expected Left, got Right " <> show m)

  , testCase "an unknown severity inside an override is rejected" $
      assertBool "expected Left for an unrecognised severity in the rules file" $
        isLeft (parseRuleOverrides (BS8.pack "0:\n  severity: urgent\n"))

  , testCase "malformed YAML syntax is rejected with an error, not an exception" $
      assertBool "expected Left for unparseable YAML" $
        isLeft (parseRuleOverrides (BS8.pack "0: [unterminated\n"))

  , testCase "an empty document fails to parse (Null, not an object) -- documented limitation" $
      assertBool "expected Left for an empty rules file" $
        isLeft (parseRuleOverrides BS.empty)

  , testCase "a bare \"null\" document also fails to parse" $
      assertBool "expected Left for a null rules document" $
        isLeft (parseRuleOverrides (BS8.pack "null\n"))
  ]

loadTests :: TestTree
loadTests = testGroup "loadRuleOverrides (IO)"
  [ testCase "loads and parses a well-formed file from disk" $
      withTempFile validYaml $ \fp -> do
        result <- loadRuleOverrides fp
        case result of
          Left err -> assertFailure ("expected Right, got Left " <> err)
          Right m  -> Map.keys m @?= [0, 2]

  , testCase "surfaces a parse error from a malformed file, rather than throwing" $
      withTempFile (BS8.pack "not: [valid\n") $ \fp -> do
        result <- loadRuleOverrides fp
        case result of
          Left _  -> pure ()
          Right m -> assertFailure ("expected Left, got Right " <> show m)
  ]

-- | Write the given bytes to a fresh temp file for the duration of the
--   action, then remove it -- mirrors the pattern
--   "Hermod.AlarmBridge.ReConProcess.writeGeneratedTracingConfig" uses in
--   the library itself.
withTempFile :: BS.ByteString -> (FilePath -> IO a) -> IO a
withTempFile contents action = do
  tmpDir <- getTemporaryDirectory
  bracket
    (openTempFile tmpDir "hermod-alarm-bridge-rules-test.yaml")
    (\(fp, _) -> removeFile fp)
    (\(fp, h) -> do
        hClose h
        BS.writeFile fp contents
        action fp)
