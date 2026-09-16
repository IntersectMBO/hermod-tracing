-- | Unit tests for "Hermod.AlarmBridge.ReConProcess": deciding whether
--   hermod-recon needs a generated tracing config injected, and the
--   best-effort @--mode online@ scan.
module Hermod.AlarmBridge.Test.ReConProcess (tests) where

import           Hermod.AlarmBridge.ReConProcess

import           Control.Exception (bracket)
import qualified Data.Text as Text
import qualified Data.Text.IO as TIO
import           System.Directory (removeFile)
import           Test.Tasty
import           Test.Tasty.HUnit

tests :: TestTree
tests = testGroup "ReConProcess"
  [ needsTracingCfgInjectionTests
  , prepareReConArgsTests
  , isOnlineModeTests
  , generatedConfigTests
  ]

needsTracingCfgInjectionTests :: TestTree
needsTracingCfgInjectionTests = testGroup "needsTracingCfgInjection"
  [ testCase "no args at all -> needs injection" $
      needsTracingCfgInjection [] @?= True
  , testCase "other flags present, but not --hermod-tracing-cfg -> needs injection" $
      needsTracingCfgInjection ["--formulas", "f.yaml", "--mode", "offline"] @?= True
  , testCase "already present -> no injection needed" $
      needsTracingCfgInjection ["--hermod-tracing-cfg", "existing.yaml"] @?= False
  , testCase "present among other flags -> no injection needed" $
      needsTracingCfgInjection ["--mode", "online", "--hermod-tracing-cfg", "x.yaml"] @?= False
  , testCase "a merely similar token (not an exact match) still needs injection" $
      needsTracingCfgInjection ["--hermod-tracing-cfgX"] @?= True
  ]

prepareReConArgsTests :: TestTree
prepareReConArgsTests = testGroup "prepareReConArgs"
  [ testCase "appends the generated config when none was given" $
      prepareReConArgs "/tmp/gen.yaml" ["--mode", "offline"] @?=
        ["--mode", "offline", "--hermod-tracing-cfg", "/tmp/gen.yaml"]
  , testCase "leaves the user's own args untouched when already present" $
      prepareReConArgs "/tmp/gen.yaml" ["--hermod-tracing-cfg", "user.yaml"] @?=
        ["--hermod-tracing-cfg", "user.yaml"]
  , testCase "appending to an empty arg list" $
      prepareReConArgs "/tmp/gen.yaml" [] @?= ["--hermod-tracing-cfg", "/tmp/gen.yaml"]
  ]

isOnlineModeTests :: TestTree
isOnlineModeTests = testGroup "isOnlineMode"
  [ testCase "--mode online present" $
      isOnlineMode ["--formulas", "f.yaml", "--mode", "online"] @?= True
  , testCase "--mode offline present" $
      isOnlineMode ["--mode", "offline"] @?= False
  , testCase "no --mode at all" $
      isOnlineMode ["--formulas", "f.yaml"] @?= False
  , testCase "empty args" $
      isOnlineMode [] @?= False
  , testCase "a dangling --mode with nothing after it is not online" $
      isOnlineMode ["--mode"] @?= False
  , testCase "--mode online followed by other args" $
      isOnlineMode ["--mode", "online", "--extra", "thing"] @?= True
  , testCase "--mode appearing later in the arg list is still found" $
      isOnlineMode ["--formulas", "f.yaml", "--mode", "online", "--extra"] @?= True
  ]

generatedConfigTests :: TestTree
generatedConfigTests = testGroup "machineFormatTracingConfigYaml / writeGeneratedTracingConfig"
  [ testCase "the generated YAML selects an Info-severity Stdout MachineFormat backend at the root namespace" $ do
      assertBool "should select the MachineFormat backend"
        (Text.isInfixOf "Stdout MachineFormat" machineFormatTracingConfigYaml)
      assertBool "should set an Info severity threshold"
        (Text.isInfixOf "severity: Info" machineFormatTracingConfigYaml)
      assertBool "should apply at the namespace root (\"\")"
        (Text.isInfixOf "\"\":" machineFormatTracingConfigYaml)

  , testCase "writeGeneratedTracingConfig writes exactly that YAML to a fresh file" $
      bracket writeGeneratedTracingConfig removeFile $ \fp -> do
        contents <- TIO.readFile fp
        contents @?= machineFormatTracingConfigYaml

  , testCase "two calls to writeGeneratedTracingConfig produce distinct files" $
      bracket writeGeneratedTracingConfig removeFile $ \fp1 ->
        bracket writeGeneratedTracingConfig removeFile $ \fp2 ->
          assertBool "temp files should be distinct" (fp1 /= fp2)
  ]
