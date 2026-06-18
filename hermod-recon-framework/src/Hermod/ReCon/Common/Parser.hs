module Hermod.ReCon.Common.Parser (parseIdentifier, parseIntValue, parseNatValue, parseBinRel) where

import           Hermod.ReCon.Common.Types (BinRel (..), IntValue, NatValue, Parser, VariableIdentifier)

import           Data.Char (isAlpha, isAlphaNum)
import           Data.Functor
import qualified Data.Text as Text
import           Text.Megaparsec
import           Text.Megaparsec.Char (string)
import           Text.Megaparsec.Char.Lexer (decimal, signed)

isSubscriptDigit :: Char -> Bool
isSubscriptDigit c = c >= '₀' && c <= '₉'

parseIdentifier :: Parser VariableIdentifier
parseIdentifier =
  Text.pack <$> ((:) <$> firstChar <*> many nextChar) <?> "identifier"
  where
    firstChar = satisfy (\c -> isAlpha c || c == '_')
    nextChar  = satisfy (\c -> isAlphaNum c || c == '_' || isSubscriptDigit c)

parseIntValue :: Parser IntValue
parseIntValue = signed (pure ()) decimal

parseNatValue :: Parser NatValue
parseNatValue = decimal

parseLt :: Parser ()
parseLt = void $ string "<"

parseGt :: Parser ()
parseGt = void $ string ">"

parseEq :: Parser ()
parseEq = void $ string "="

parseLte :: Parser ()
parseLte = void $ string "≤" <|> string "<="

parseGte :: Parser ()
parseGte = void $ string "≥" <|> string ">="

parseBinRel :: Parser BinRel
parseBinRel =
      Lte <$ parseLte
  <|> Gte <$ parseGte
  <|> Eq  <$ parseEq
  <|> Lt  <$ parseLt
  <|> Gt  <$ parseGt
