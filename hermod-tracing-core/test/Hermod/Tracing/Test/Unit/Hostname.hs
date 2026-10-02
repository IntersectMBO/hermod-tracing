-- | The host name in a trace message is read from the environment once, by
--   the 'NOINLINE' CAF @hostname@ in "Hermod.Tracing.Formatter". To test its
--   environment-variable precedence, the test executable re-runs itself with
--   a controlled environment and reads the host name it prints.
module Hermod.Tracing.Test.Unit.Hostname (
    hostnameChildVar
  , hostnameChild
  , hostnameTests
) where

import           Hermod.Tracing
import           Hermod.Tracing.Test.Tracer
import           Hermod.Tracing.Test.Unit.TestObjects

import           Data.IORef
import qualified Data.Text.IO as T
import           Network.HostName (getHostName)
import           System.Environment (getEnvironment, getExecutablePath)
import           System.Process (env, proc, readCreateProcess)
import           Test.Tasty
import           Test.Tasty.HUnit


-- | When set, the test executable runs 'hostnameChild' instead of the suite.
hostnameChildVar :: String
hostnameChildVar = "HERMOD_TRACING_TEST_HOSTNAME_CHILD"

modernVar, legacyVar :: String
modernVar = "HERMOD_TRACING_LOGGING_HOSTNAME"
legacyVar = "TRACE_DISPATCHER_LOGGING_HOSTNAME"

-- | Emit one forwarded message and print the host name it carries.
hostnameChild :: IO ()
hostnameChild = do
    testTracerRef <- newIORef []
    testTracer' <- testTracer testTracerRef
    let simpleTracer = forwardFormatter testTracer'
    confState <- emptyConfigReflection
    configureTracers confState emptyTraceConfig [simpleTracer]
    traceWith simpleTracer message1
    msgs <- readIORef testTracerRef
    case msgs of
      [FormattedForwarder to] -> T.putStr (toHostname to)
      _ -> error $ "hostnameChild: expected one forwarded message, got " ++ show (length msgs)

-- | Run 'hostnameChild' with exactly the given hostname variables set.
hostnameWith :: [(String, String)] -> IO String
hostnameWith vars = do
    exe <- getExecutablePath
    inherited <- filter ((`notElem` [modernVar, legacyVar, hostnameChildVar]) . fst)
                   <$> getEnvironment
    readCreateProcess
      (proc exe []) { env = Just ((hostnameChildVar, "1") : vars ++ inherited) }
      ""

hostnameTests :: TestTree
hostnameTests = testGroup "Hostname"
    [ testCase "neither variable set" $ do
        expected <- takeWhile (/= '.') <$> getHostName
        hostnameWith [] >>= assertEqual "system host name" expected
    , testCase "modern variable only" $
        hostnameWith [(modernVar, "modern-host")]
          >>= assertEqual modernVar "modern-host"
    , testCase "deprecated variable only" $
        hostnameWith [(legacyVar, "legacy-host")]
          >>= assertEqual legacyVar "legacy-host"
    , testCase "both set: modern wins" $
        hostnameWith [(modernVar, "modern-host"), (legacyVar, "legacy-host")]
          >>= assertEqual modernVar "modern-host"
    ]
