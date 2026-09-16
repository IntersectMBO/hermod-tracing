-- | Unit tests for "Hermod.AlarmBridge.Severity": the two independent
--   textual codecs (hermod's own capitalized vocabulary, and cardano-tracer's
--   lowercase wire vocabulary) must each round-trip through 'Severity', and
--   must reject anything outside their own vocabulary.
module Hermod.AlarmBridge.Test.Severity (tests) where

import           Hermod.AlarmBridge.Severity

import qualified Data.Text as Text
import           Test.Tasty
import           Test.Tasty.HUnit

allSeverities :: [Severity]
allSeverities = [minBound .. maxBound]

tests :: TestTree
tests = testGroup "Severity"
  [ testCase "severityFromHermodText round-trips every constructor's Show rendering" $
      mapM_ (\s -> severityFromHermodText (Text.pack (show s)) @?= Just s) allSeverities

  , testCase "severityToWireText is exactly the lowercased Show rendering" $
      mapM_ (\s -> severityToWireText s @?= Text.toLower (Text.pack (show s))) allSeverities

  , testCase "severityFromWireText round-trips severityToWireText" $
      mapM_ (\s -> severityFromWireText (severityToWireText s) @?= Just s) allSeverities

  , testCase "severityFromWireText is case-insensitive" $
      mapM_ (\s -> severityFromWireText (Text.toUpper (severityToWireText s)) @?= Just s) allSeverities

  , testCase "severityFromHermodText rejects lowercase (wire-cased) text" $
      severityFromHermodText "warning" @?= Nothing

  , testCase "severityFromHermodText rejects unknown text" $
      severityFromHermodText "Urgent" @?= Nothing

  , testCase "severityFromWireText rejects unknown text" $
      severityFromWireText "urgent" @?= Nothing

  , testCase "severityFromHermodText rejects empty text" $
      severityFromHermodText "" @?= Nothing

  , testCase "eight-value RFC 5424 vocabulary, ordered least to most severe" $
      allSeverities @?=
        [Debug, Info, Notice, Warning, Error, Critical, Alert, Emergency]
  ]
