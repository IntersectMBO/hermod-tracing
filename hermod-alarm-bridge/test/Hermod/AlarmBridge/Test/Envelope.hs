-- | Unit tests for "Hermod.AlarmBridge.Envelope": decoding hermod-recon's
--   documented JSON-lines wire format, including the "malformed/non-JSON
--   stdout line" case that the rest of the bridge relies on being handled
--   without crashing (a 'Left', never an exception).
module Hermod.AlarmBridge.Test.Envelope (tests) where

import           Hermod.AlarmBridge.Envelope
import           Hermod.AlarmBridge.Severity (Severity (..))

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString as BS
import           Data.Text (Text)
import qualified Data.Text.Encoding as TE
import           Test.Tasty
import           Test.Tasty.HUnit

-- | A well-formed line, matching the wire format documented at the top of
--   the module under test verbatim.
wellFormedLine :: BS.ByteString
wellFormedLine = TE.encodeUtf8
  "{\"at\":\"2025-12-01T07:06:48.001779Z\",\"ns\":\"ReCon.FormulaNegativeOutcome\",\
  \\"data\":{\"formula\":\"...\",\"relevance\":\"...\",\"index\":3},\
  \\"sev\":\"Notice\",\"thread\":\"50\",\"host\":\"some-host\"}"

mkLineWithSev :: Text -> BS.ByteString
mkLineWithSev sevTxt = TE.encodeUtf8 $
  "{\"at\":\"2025-12-01T07:06:48Z\",\"ns\":\"Placeholder\",\"data\":{},\"sev\":\"" <> sevTxt
    <> "\",\"thread\":\"1\",\"host\":\"h\"}"

lineMissingHost :: BS.ByteString
lineMissingHost = TE.encodeUtf8
  "{\"at\":\"2025-12-01T07:06:48Z\",\"ns\":\"Placeholder\",\"data\":{},\"sev\":\"Info\",\"thread\":\"1\"}"

tests :: TestTree
tests = testGroup "Envelope"
  [ testCase "decodes a well-formed line" $
      case decodeHermodLine wellFormedLine of
        Left err -> assertFailure ("expected Right, got Left " <> err)
        Right hl -> do
          hlNs hl     @?= "ReCon.FormulaNegativeOutcome"
          hlSev hl    @?= Notice
          hlThread hl @?= "50"
          hlHost hl   @?= "some-host"
          KeyMap.lookup "index" (hlData hl) @?= Just (Aeson.toJSON (3 :: Int))

  , testCase "rejects a completely non-JSON line, without throwing" $
      case decodeHermodLine (TE.encodeUtf8 "not json at all") of
        Left _  -> pure () -- documented behaviour: a clear Left, never an exception
        Right _ -> assertFailure "expected Left for a non-JSON line"

  , testCase "rejects an empty line" $
      case decodeHermodLine BS.empty of
        Left _  -> pure ()
        Right _ -> assertFailure "expected Left for an empty line"

  , testCase "rejects valid JSON that isn't an object" $
      case decodeHermodLine (TE.encodeUtf8 "[1,2,3]") of
        Left _  -> pure ()
        Right _ -> assertFailure "expected Left for a JSON array"

  , testCase "rejects a line with an unknown hermod severity" $
      case decodeHermodLine (mkLineWithSev "Urgent") of
        Left _  -> pure ()
        Right _ -> assertFailure "expected Left for an unrecognised sev"

  , testCase "rejects a line missing a required field (host)" $
      case decodeHermodLine lineMissingHost of
        Left _  -> pure ()
        Right _ -> assertFailure "expected Left for a line missing \"host\""

  , testCase "accepts every hermod-capitalised severity spelling" $
      mapM_ (\(txt, sev) ->
               case decodeHermodLine (mkLineWithSev txt) of
                 Right hl -> hlSev hl @?= sev
                 Left err -> assertFailure ("expected Right for sev=" <> show txt <> ", got " <> err))
            [ ("Debug", Debug), ("Info", Info), ("Notice", Notice), ("Warning", Warning)
            , ("Error", Error), ("Critical", Critical), ("Alert", Alert), ("Emergency", Emergency)
            ]
  ]
