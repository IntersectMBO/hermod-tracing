module Main (main) where

import qualified Hermod.ReCon.Integration.Suite as Suite
import           GHC.IO.Encoding (setLocaleEncoding, utf8)
import           Test.Tasty

main :: IO ()
main = do
  setLocaleEncoding utf8
  tree <- Suite.integrationTests
  defaultMain tree