module Hermod.ReCon.LTL.Syntax.Suite (syntaxTests) where

import           Hermod.ReCon.LTL.Check (Error (..), checkFormula)
import           Hermod.ReCon.LTL.Formula
import           Hermod.ReCon.LTL.Formula.Parser (Context (..))
import qualified Hermod.ReCon.LTL.Formula.Parser as Parser
import qualified Hermod.ReCon.LTL.Formula.Prec as Prec
import           Hermod.ReCon.LTL.Formula.Pretty (prettyFormula)

import qualified Data.Map.Strict as Map
import           Data.Set (fromList)
import           Data.Text (Text, unpack)
import qualified Data.Text as Text
import           Text.Megaparsec

import           Test.Tasty
import           Test.Tasty.HUnit

syn1 :: Formula event ()
syn1 = PropTextForall "i" (Atom () (fromList [TextPropConstraint "idx" (TextVar "i")]))

syn2 :: Formula event ()
syn2 = PropTextForall "i" (Atom () (fromList [TextPropConstraint "idx" (TextVar "j")]))

syn3 :: Formula event ()
syn3 = PropTextExists "i" (Atom () (fromList [TextPropConstraint "idx" (TextVar "i")]))

syn4 :: Formula event ()
syn4 = PropTextExists "i" (Atom () (fromList [TextPropConstraint "idx" (TextVar "j")]))

formula0 :: Text
formula0 = "☐ ᪲ (∀x ∈ Text. \"Forge.Loop.StartLeadershipCheck\"{\"slot\" = x} ⇒ \
  \♢³⁰⁰⁰ (\"Forge.Loop.NodeIsLeader\"{\"slot\" = x} ∨ \"Forge.Loop.NodeNotLeader\"{\"slot\" = x}))"

formula1 :: Text
formula1 =
  "☐ ᪲₄₂ (∀i ∈ Text. (¬ (\"NodeIsLeader\"{\"slot\" = i} ∨ \"NodeNotLeader\"{\"slot\" = i}) |¹²³ \"StartLeadershipCheck\"{\"slot\" = i}))"

formula2 :: Text
formula2 =
  "☐² (⊥ ∨ ◯ ⊤ ∧ ◯² (◯¹ (◯⁰ ⊤)))"

formula3 :: Text
formula3 = "☐ ᪲₁ ⊤"

formula4 :: Text
formula4 = "∀x ∈ ℤ. x = 1"

formula5 :: Text
formula5 = "∀x ∈ {1, 2, 3}. x = 1 ∨ x = 2 ∨ x = 3"

formula6 :: Text
formula6 = "∃x ∈ {1, 2, 3}. x = 1"

emptyCtx :: Context
emptyCtx = Context { interpDomain = [], varKinds = Map.empty }

pF :: Text -> Either String (Formula () Text)
pF src = case parse (Parser.formula @Text @() emptyCtx Parser.name) "input" src of
  Right x  -> Right x
  Left err -> Left (show err)

(@==) :: Text -> Formula () Text -> Assertion
input @== expected = pF input @?= Right expected
infix 1 @==

syntaxTests :: TestTree
syntaxTests = testGroup "Syntax"
  [ syntacticTests
  , parserTests
  , asciiTests
  ]

syntacticTests :: TestTree
syntacticTests = testGroup "Syntactic checks"
  [
    testCase (unpack $ prettyFormula syn1 Prec.Universe <> " is syntactically valid") $
      [] @?= checkFormula mempty syn1
  ,
    testCase (unpack $ prettyFormula syn2 Prec.Universe <> " is syntactically invalid") $
      [UnboundVariableIdentifier "j"] @?= checkFormula mempty syn2
  , testCase (unpack $ prettyFormula syn3 Prec.Universe <> " is syntactically valid") $
      [] @?= checkFormula mempty syn3
  ,
    testCase (unpack $ prettyFormula syn4 Prec.Universe <> " is syntactically invalid") $
      [UnboundVariableIdentifier "j"] @?= checkFormula mempty syn4
  ]

parserTests :: TestTree
parserTests = testGroup "Parsing"
  [
    testCase (Text.unpack formula0) $
      parse (Parser.formula @Text @() emptyCtx Parser.name) "input" formula0 @?=
        Right
          (Forall
            0
            (PropTextForall
              "x"
              (Implies
                (Atom "Forge.Loop.StartLeadershipCheck" (fromList [TextPropConstraint "slot" (TextVar "x")]))
                (ExistsN
                  3000
                  (Or
                    (Atom "Forge.Loop.NodeIsLeader" (fromList [TextPropConstraint "slot" (TextVar "x")]))
                    (Atom "Forge.Loop.NodeNotLeader" (fromList [TextPropConstraint "slot" (TextVar "x")])))))))
  ,
    testCase (Text.unpack formula1) $
      parse (Parser.formula @Text @() emptyCtx Parser.name) "input" formula1 @?=
        Right
          (Forall
            42
            (PropTextForall
              "i"
              (UntilN
                123
                (Not
                  (Or
                    (Atom "NodeIsLeader" (fromList [TextPropConstraint "slot" (TextVar "i")]))
                    (Atom "NodeNotLeader" (fromList [TextPropConstraint "slot" (TextVar "i")]))))
                (Atom "StartLeadershipCheck" (fromList [TextPropConstraint "slot" (TextVar "i")])))))
  ,
    testCase (Text.unpack formula2) $
      parse (Parser.formula @Text @() emptyCtx Parser.name) "input" formula2 @?=
        Right (ForallN 2 (Or Bottom (And (Next Top) (NextN 2 (NextN 1 (NextN 0 Top))))))
  ,
    testCase (Text.unpack formula3) $
      parse (Parser.formula @Text @() emptyCtx Parser.name) "input" formula3 @?=
        Right (Forall 1 Top)
  ,
    testCase (Text.unpack formula4) $
      parse (Parser.formula @Text @() emptyCtx Parser.name) "input" formula4 @?=
        Right
          (PropIntForall
            "x"
            (PropIntBinRel Eq (fromList []) (IntVar 1 "x") (IntConst 1)))
  ,
    testCase (Text.unpack formula5) $
      parse (Parser.formula @Text @() emptyCtx Parser.name) "input" formula5 @?=
        Right
          (PropIntForallN
            "x"
            (fromList [1, 2, 3])
            (Or
              (PropIntBinRel Eq (fromList []) (IntVar 1 "x") (IntConst 1))
              (Or
                (PropIntBinRel Eq (fromList []) (IntVar 1 "x") (IntConst 2))
                (PropIntBinRel Eq (fromList []) (IntVar 1 "x") (IntConst 3)))))
  ,
    testCase (Text.unpack formula6) $
      parse (Parser.formula @Text @() emptyCtx Parser.name) "input" formula6 @?=
        Right
          (PropIntExistsN
            "x"
            (fromList [1, 2, 3])
            (PropIntBinRel Eq (fromList []) (IntVar 1 "x") (IntConst 1))
          )
  ]

asciiTests :: TestTree
asciiTests = testGroup "ASCII syntax"
  [ testGroup "Atoms"
      [ testCase "\\bottom"  $ "\\bottom" @== Bottom
      , testCase "\\top"     $ "\\top"    @== Top
      ]
  , testGroup "Temporal operators"
      [ testCase "\\next"              $ "\\next \\top"         @== Next Top
      , testCase "\\next with (N)"     $ "\\next(2) \\top"      @== NextN 2 Top
      , testCase "\\finallyN with (N)" $ "\\finallyN(300) \\top" @== ExistsN 300 Top
      , testCase "\\globallyN with (N)" $ "\\globallyN(2) \\top" @== ForallN 2 Top
      , testCase "\\globally"          $ "\\globally \\top"     @== Forall 0 Top
      , testCase "\\globally with (N)" $ "\\globally(42) \\top" @== Forall 42 Top
      ]
  , testGroup "Connectives"
      [ testCase "\\not"  $ "\\not \\top"            @== Not Top
      , testCase "&&"     $ "\\top && \\bottom"       @== And Top Bottom
      , testCase "||"     $ "\\top || \\bottom"       @== Or  Top Bottom
      , testCase "=>"     $ "\\top => \\bottom"       @== Implies Top Bottom
      ]
  , testGroup "Quantifiers"
      [ testCase "\\forall x : \\Int"  $ "\\forall x : \\Int. x = 1"  @==
          PropIntForall "x" (PropIntBinRel Eq (fromList []) (IntVar 1 "x") (IntConst 1))
      , testCase "\\forall x : Int"    $ "\\forall x : Int. x = 1"    @==
          PropIntForall "x" (PropIntBinRel Eq (fromList []) (IntVar 1 "x") (IntConst 1))
      , testCase "\\exists x : \\Int"  $ "\\exists x : \\Int. x = 1"  @==
          PropIntExists "x" (PropIntBinRel Eq (fromList []) (IntVar 1 "x") (IntConst 1))
      , testCase "\\forall x : \\Text" $ "\\forall x : \\Text. \\top" @==
          PropTextForall "x" Top
      , testCase "\\exists x : \\Text" $ "\\exists x : \\Text. \\top" @==
          PropTextExists "x" Top
      ]
  ]
