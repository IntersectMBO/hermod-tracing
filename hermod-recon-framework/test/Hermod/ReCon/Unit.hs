module Main (main) where

import qualified Hermod.ReCon.Integer.Polynomial.Semantics.Suite as PolySem
import qualified Hermod.ReCon.Integer.Polynomial.Syntax.Suite as PolySyn
import qualified Hermod.ReCon.LTL.Semantics.Suite as LTLSem
import qualified Hermod.ReCon.LTL.Syntax.Suite as LTLSyn
import qualified Hermod.ReCon.Presburger.Semantics.Suite as PSem
import qualified Hermod.ReCon.Presburger.Syntax.Suite as PSyn

import           GHC.IO.Encoding (setLocaleEncoding, utf8)
import           Test.Tasty

main :: IO ()
main = do
  setLocaleEncoding utf8
  defaultMain $ testGroup "Unit tests"
    [ testGroup "Integer.Polynomial"
        [ PolySyn.syntaxTests
        , PolySem.semanticsTests
        ]
    , testGroup "LTL"
        [ LTLSyn.syntaxTests
        , LTLSem.semanticsTests
        ]
    , testGroup "Presburger"
        [ PSyn.syntaxTests
        , PSem.semanticsTests
        ]
    ]
