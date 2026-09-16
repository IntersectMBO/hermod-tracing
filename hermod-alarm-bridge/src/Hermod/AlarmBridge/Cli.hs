-- | Command-line interface, in the same @optparse-applicative@ style as
--   @hermod-recon-framework@'s own 'Hermod.ReCon.Cli'.
module Hermod.AlarmBridge.Cli
  ( RunMode (..)
  , TokenSource (..)
  , CliOptions (..)
  , opts
  ) where

import           Hermod.AlarmBridge.Severity (Severity (Error), severityFromWireText,
                   severityToWireText)

import           Data.Text (Text, pack, unpack)
import           Options.Applicative

-- | Exactly one of these is required: either spawn hermod-recon ourselves
--   (@--exec -- <cmd> <args...>@), or read already-running hermod-recon's
--   output from this bridge's own stdin (@--stdin@ -- the caller is then
--   responsible for hermod-recon's own @--hermod-tracing-cfg@).
data RunMode
  = ExecReCon FilePath [String]
    -- ^ The hermod-recon executable, and the arguments to run it with.
  | ReadStdin
  deriving stock (Show, Eq)

-- | How the producer bearer token cardano-tracer's alarm ingress expects
--   (@Authorization: Bearer \<producer token\>@, per the design doc's
--   Producer ingress section) is supplied. Reading it from a file is the
--   preferred form -- it matches cardano-tracer's own
--   'Cardano.Tracer.Handlers.Alarms.Auth.loadCredentials', which reads
--   producer\/reader tokens from config-supplied files rather than inline
--   config, per the design doc's Security section ("Secrets should be read
--   from protected files"). @--token@ is offered too, for quick manual
--   testing, but it is visible to anyone who can list processes on the
--   host, so @--token-file@ should be preferred in production.
data TokenSource
  = TokenLiteral Text
  | TokenFile FilePath
  deriving stock (Show, Eq)

data CliOptions = CliOptions
  { tracerHost      :: String
  , tracerPort      :: Int
  , rulesFile       :: Maybe FilePath
  , defaultSeverity :: Severity
  , producerToken   :: Maybe TokenSource
    -- ^ 'Nothing' sends no @Authorization@ header at all, matching
    --   cardano-tracer's "open producer" mode (see
    --   'Cardano.Tracer.Handlers.Alarms.Auth.openProducer') -- only valid
    --   against a tracer configured with @allowInsecure: true@ and no
    --   token on the matching producer entry. Any normal, token-authenticated
    --   producer requires @--token@ or @--token-file@.
  , runMode         :: RunMode
  }

readSeverity :: ReadM Severity
readSeverity = eitherReader $ \s ->
  maybe (Left ("unknown severity: " <> s)) Right (severityFromWireText (pack s))

parseTracerHost :: Parser String
parseTracerHost = strOption $
     long "tracer-host"
  <> metavar "HOST"
  <> showDefault
  <> value "127.0.0.1"
  <> help "cardano-tracer alarm ingress host"

parseTracerPort :: Parser Int
parseTracerPort = option auto $
     long "tracer-port"
  <> metavar "PORT"
  <> help "cardano-tracer alarm ingress port"

parseRulesFile :: Parser (Maybe FilePath)
parseRulesFile = optional $ strOption $
     long "rules"
  <> metavar "FILE"
  <> help "YAML file mapping formula index -> {ruleId?, severity?, summary?} overrides"

parseDefaultSeverity :: Parser Severity
parseDefaultSeverity = option readSeverity $
     long "default-severity"
  <> metavar "<debug|info|notice|warning|error|critical|alert|emergency>"
  <> showDefaultWith (unpack . severityToWireText)
  <> value Error
  <> help "default outgoing alarm severity for a FormulaNegativeOutcome with no --rules override"

parseTokenFile :: Parser TokenSource
parseTokenFile = TokenFile <$> strOption
  (  long "token-file"
  <> metavar "FILE"
  <> help "file containing the producer bearer token for cardano-tracer's alarm \
          \ingress (preferred over --token: not visible in the process list)"
  )

parseTokenLiteral :: Parser TokenSource
parseTokenLiteral = TokenLiteral . pack <$> strOption
  (  long "token"
  <> metavar "TOKEN"
  <> help "producer bearer token for cardano-tracer's alarm ingress, given \
          \directly (prefer --token-file where possible)"
  )

-- | At most one of @--token-file@\/@--token@; omitting both sends no
--   @Authorization@ header (see 'producerToken').
parseProducerToken :: Parser (Maybe TokenSource)
parseProducerToken = optional (parseTokenFile <|> parseTokenLiteral)

-- | @--exec -- <cmd> <args...>@: 'flag'' requires @--exec@ to actually be
--   present (unlike a plain 'switch', which would silently default to
--   picking this branch even when absent). Everything after a literal
--   @--@ on the command line is treated by optparse-applicative as
--   positional, bypassing option parsing -- so hermod-recon's own flags
--   (@--formulas@, @--mode@, ...) pass through untouched.
parseExecMode :: Parser RunMode
parseExecMode =
  (\_ cmd args -> ExecReCon cmd args)
    <$> flag' () (long "exec" <> help "spawn hermod-recon as a subprocess (its command and args go after --)")
    <*> strArgument (metavar "CMD")
    <*> many (strArgument (metavar "ARGS..."))

-- | @--stdin@: read hermod-recon's JSON lines from this bridge's own
--   stdin. The caller is responsible for hermod-recon's own tracing
--   config in this mode (i.e. for making sure it actually emits
--   Stdout MachineFormat).
parseStdinMode :: Parser RunMode
parseStdinMode =
  flag' ReadStdin (long "stdin" <> help "read hermod-recon's JSON lines from this bridge's own stdin")

parseRunMode :: Parser RunMode
parseRunMode = parseExecMode <|> parseStdinMode

parseCliOptions :: Parser CliOptions
parseCliOptions = CliOptions
              <$> parseTracerHost
              <*> parseTracerPort
              <*> parseRulesFile
              <*> parseDefaultSeverity
              <*> parseProducerToken
              <*> parseRunMode

opts :: ParserInfo CliOptions
opts = info (parseCliOptions <**> helper)
  (fullDesc <> progDesc "Bridge hermod-recon's JSON trace output into cardano-tracer's alarm ingress API")
