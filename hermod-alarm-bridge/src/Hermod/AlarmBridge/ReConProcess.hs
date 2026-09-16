-- | Helpers for launching hermod-recon as a subprocess in @--exec@ mode:
--   deciding whether its own tracing needs a config injected so it emits
--   machine-format JSON, generating that config, and a small heuristic for
--   whether hermod-recon was run in @--mode online@ (which is meant to run
--   forever, so its own exit -- even a clean one -- is noteworthy).
module Hermod.AlarmBridge.ReConProcess
  ( needsTracingCfgInjection
  , machineFormatTracingConfigYaml
  , prepareReConArgs
  , isOnlineMode
  , writeGeneratedTracingConfig
  ) where

import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as TIO
import           System.Directory (getTemporaryDirectory)
import           System.IO (hClose, openTempFile)

-- | True when the user's own hermod-recon args don't already select a
--   tracing config file -- i.e. we should generate and inject one.
needsTracingCfgInjection :: [String] -> Bool
needsTracingCfgInjection args = "--hermod-tracing-cfg" `notElem` args

-- | The YAML content of the generated hermod-tracing config: forces a
--   "Stdout MachineFormat" backend at Info severity threshold on the
--   namespace root (see @hermod-tracing-core/doc/config.yaml@ for the
--   general config shape, and
--   @Hermod.Tracing.Types.Config.BackendConfig@\/@FormatLogging@ for the
--   exact @"Stdout MachineFormat"@ spelling this must match). Info
--   threshold lets every FormulaNegativeOutcome (Notice) and
--   FormulaPositiveOutcome\/FormulaStartCheck (Info) through, plus any
--   Warning\/Error Reflection diagnostic, while filtering out Debug-level
--   FormulaProgressDump\/ContextDump chatter.
machineFormatTracingConfigYaml :: Text
machineFormatTracingConfigYaml = Text.unlines
  [ "HermodTracing:"
  , "  Options:"
  , "    \"\":"
  , "      severity: Info"
  , "      backends:"
  , "        - Stdout MachineFormat"
  ]

-- | Write 'machineFormatTracingConfigYaml' to a fresh temp file and return
--   its path.
writeGeneratedTracingConfig :: IO FilePath
writeGeneratedTracingConfig = do
  tmpDir <- getTemporaryDirectory
  (path, h) <- openTempFile tmpDir "hermod-alarm-bridge-tracing.yaml"
  TIO.hPutStr h machineFormatTracingConfigYaml
  hClose h
  pure path

-- | Given the user's own hermod-recon args and the path of a generated
--   config file, append @--hermod-tracing-cfg <path>@ -- but only if the
--   user didn't already pass one themselves.
prepareReConArgs :: FilePath -> [String] -> [String]
prepareReConArgs genCfgPath args
  | needsTracingCfgInjection args = args ++ ["--hermod-tracing-cfg", genCfgPath]
  | otherwise                     = args

-- | Best-effort scan of the user's hermod-recon args for @--mode online@.
--   hermod-recon's own CLI takes @--mode <offline|online>@ as two separate
--   tokens, so this looks for the adjacent pair rather than any single
--   token (an @--mode=online@ spelling, if hermod-recon ever accepted one,
--   would not match; it currently only accepts the two-token form).
isOnlineMode :: [String] -> Bool
isOnlineMode ("--mode" : mode : _) = mode == "online"
isOnlineMode (_ : rest)            = isOnlineMode rest
isOnlineMode []                    = False
