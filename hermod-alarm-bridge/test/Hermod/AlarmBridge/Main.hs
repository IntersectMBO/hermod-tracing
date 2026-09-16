module Main (main) where

import qualified Hermod.AlarmBridge.Test.Classify as Classify
import qualified Hermod.AlarmBridge.Test.Deliver as Deliver
import qualified Hermod.AlarmBridge.Test.Envelope as Envelope
import qualified Hermod.AlarmBridge.Test.Integration as Integration
import qualified Hermod.AlarmBridge.Test.ReConProcess as ReConProcess
import qualified Hermod.AlarmBridge.Test.Rules as Rules
import qualified Hermod.AlarmBridge.Test.Severity as Severity
import qualified Hermod.AlarmBridge.Test.Startup as Startup

import           GHC.IO.Encoding (setLocaleEncoding, utf8)
import           Test.Tasty

main :: IO ()
main = do
  setLocaleEncoding utf8
  defaultMain $ testGroup "hermod-alarm-bridge"
    [ testGroup "Unit"
        [ Severity.tests
        , Envelope.tests
        , Classify.tests
        , Rules.tests
        , Startup.tests
        , Deliver.tests
        , ReConProcess.tests
        ]
    , Integration.tests
    ]
