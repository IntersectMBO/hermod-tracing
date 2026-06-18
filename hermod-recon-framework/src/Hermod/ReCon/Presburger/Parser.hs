{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use <$>" #-}
module Hermod.ReCon.Presburger.Parser (Parser, formula, intTerm) where

import           Hermod.ReCon.Common.Parser
import           Hermod.ReCon.Common.Types
import           Hermod.ReCon.Integer.Polynomial.Parser (intTerm)
import           Hermod.ReCon.Presburger.Formula (Formula (..))

import           Data.Functor (void)
import           Text.Megaparsec
import           Text.Megaparsec.Char (char, space, string)

-- ---------------------------------------------------------------------------
-- Formula parser
-- ---------------------------------------------------------------------------

-- | @d ∣ t@: divisibility constraint.  @d@ must be a non-zero nat.
intDivConstraint :: Parser Formula
intDivConstraint = do
  d <- parseNatValue
  space
  void $ char '∣'
  space
  t <- intTerm
  pure (IntDiv d t)

-- | @t₁ rel t₂@: binary relation constraint.
intRelConstraint :: Parser Formula
intRelConstraint = do
  lhs <- intTerm
  space
  rel <- parseBinRel
  space
  rhs <- intTerm
  pure (IntBinRel rel lhs rhs)

formulaBottom :: Parser ()
formulaBottom = void $ string "⊥" <|> string "\\bottom"

formulaTop :: Parser ()
formulaTop = void $ string "⊤" <|> string "\\top"

-- | Atom: ⊥, ⊤, parenthesised formula, or an arithmetic constraint.
formulaAtom :: Parser Formula
formulaAtom =
      Bottom <$ formulaBottom
  <|> Top    <$ formulaTop
  <|> (char '(' *> space *> formula <* space <* char ')')
  <|> try intDivConstraint
  <|> intRelConstraint

formulaNotOp :: Parser ()
formulaNotOp = void $ string "¬" <|> string "\\not"

-- | Prefix negation applied to a single atom.
formulaNot :: Parser Formula
formulaNot =
      Not <$> (formulaNotOp *> space *> formulaAtom)
  <|> formulaAtom

formulaAndOp :: Parser ()
formulaAndOp = void $ string "∧" <|> string "&&"

-- | Right-associative conjunction @φ ∧ ψ@.
formulaAnd :: Parser Formula
formulaAnd = apply <$> (formulaNot <* space) <*> optional rhs
  where
    rhs = formulaAndOp *> space *> formulaAnd
    apply phi Nothing    = phi
    apply phi (Just psi) = And phi psi

formulaOrOp :: Parser ()
formulaOrOp = void $ string "∨" <|> string "||"

-- | Right-associative disjunction @φ ∨ ψ@.
formulaOr :: Parser Formula
formulaOr = apply <$> (formulaAnd <* space) <*> optional rhs
  where
    rhs = formulaOrOp *> space *> formulaOr
    apply phi Nothing    = phi
    apply phi (Just psi) = Or phi psi

formulaImpliesOp :: Parser ()
formulaImpliesOp = void $ string "⇒" <|> string "=>"

-- | Right-associative implication @φ ⇒ ψ@.
formulaImplies :: Parser Formula
formulaImplies = apply <$> (formulaOr <* space) <*> optional rhs
  where
    rhs = formulaImpliesOp *> space *> formulaImplies
    apply phi Nothing    = phi
    apply phi (Just psi) = Implies phi psi

formulaForallOp :: Parser ()
formulaForallOp = void $ string "∀" <|> string "\\forall"

-- | @∀x. φ@: universal integer quantification.
formulaForall :: Parser Formula
formulaForall = do
  formulaForallOp
  space
  x <- parseIdentifier
  space
  void $ char '.'
  space
  phi <- formula
  pure (IntForall x phi)

formulaExistsOp :: Parser ()
formulaExistsOp = void $ string "∃" <|> string "\\exists"

-- | @∃x. φ@: existential integer quantification.
formulaExists :: Parser Formula
formulaExists = do
  formulaExistsOp
  space
  x <- parseIdentifier
  space
  void $ char '.'
  space
  phi <- formula
  pure (IntExists x phi)

-- | Parse a Presburger arithmetic formula.
--
-- Precedence table (outermost / lowest binding first):
--
-- @
--   ∀x. φ   ∃x. φ     quantifiers
--   φ ⇒ ψ             implication (right-associative)
--   φ ∨ ψ             disjunction (right-associative)
--   φ ∧ ψ             conjunction (right-associative)
--   ¬ φ               negation    (prefix, binds to single atom)
--   ⊥  ⊤  (φ)  d∣t  t rel t     atoms
-- @
--
-- Note: to combine a quantifier with a connective write
-- @φ ∧ (∀x. ψ)@ — quantifiers inside sub-formulas must be parenthesised.
formula :: Parser Formula
formula =
      formulaForall
  <|> formulaExists
  <|> formulaImplies
