{-# LANGUAGE DeriveAnyClass           #-}
{-# LANGUAGE DeriveGeneric            #-}
{-# LANGUAGE DerivingStrategies       #-}
{-# LANGUAGE MultiWayIf               #-}
{-# LANGUAGE StandaloneKindSignatures #-}

module Cardano.Logging.Types.Configuration
       ( HowToConnect (..)
       , PrometheusSimpleRun (..)
       , prometheusSimpleNoOverrides
       )
       where

import           Control.Applicative ((<|>))
import           Control.DeepSeq     (NFData)
import           Data.Aeson          as AE (FromJSON (..), ToJSON (..),
                                            withText)
import           Data.Aeson.Types    as AE (Parser)
import           Data.Kind           (Type)
import           Data.Text           as T (Text, breakOnEnd, null, unpack,
                                           unsnoc)
import           Data.Text.Read      as T
import           Data.Word
import           GHC.Generics        (Generic)



data PrometheusSimpleRun
  = -- | Parameter overrides for PrometheusSimple DoS protection
    PrometheusSimpleRun
      { connTimeout      :: Maybe Word     -- ^ Release socket after inactivity (seconds); default: 22
      , connCountGlobal  :: Maybe Word     -- ^ Limit total number of incoming connections; default: 16
      , connCountPerHost :: Maybe Word     -- ^ Limit number of incoming connections from the same host; default: 5
      , connPerSecond    :: Maybe Double   -- ^ Limit requests per second (may be < 1.0); default: 8.0
      }
  deriving (Show, Generic, AE.FromJSON, AE.ToJSON)

prometheusSimpleNoOverrides :: PrometheusSimpleRun
prometheusSimpleNoOverrides = PrometheusSimpleRun Nothing Nothing Nothing Nothing


-- | Specifies how to connect to the peer.
--
-- Taken from ekg-forward:System.Metrics.Configuration, to avoid dependency.
type Host :: Type
type Host = Text

type Port :: Type
type Port = Word16

type HowToConnect :: Type
data HowToConnect
  = LocalPipe    !FilePath    -- ^ Local pipe (UNIX or Windows).
  | RemoteSocket !Host !Port  -- ^ Remote socket (host and port).
  deriving stock (Eq, Generic)
  deriving anyclass (NFData)

instance Show HowToConnect where
  show = \case
    LocalPipe pipe         -> pipe
    RemoteSocket host port -> T.unpack host ++ ":" ++ show port

instance AE.ToJSON HowToConnect where
  toJSON     = AE.toJSON . show
  toEncoding = AE.toEncoding . show

-- first try to host:port, and if that fails revert to parsing any
-- string literal and assume it is a localpipe.
instance AE.FromJSON HowToConnect where
  parseJSON = AE.withText "HowToConnect" $ \t ->
        (uncurry RemoteSocket <$> parseHostPort t)
    <|> (        LocalPipe    <$> parseLocalPipe t)

parseLocalPipe :: Text -> AE.Parser FilePath
parseLocalPipe t
  | T.null t  = failWith "empty local pipe path"
  | otherwise = pure $ T.unpack t

parseHostPort :: Text -> AE.Parser (Text, Word16)
parseHostPort t
  | T.null t
  = failWith "empty 'host:port'"
  | otherwise
  = let
    (host_, portText) = T.breakOnEnd ":" t
    host              = maybe "" fst (T.unsnoc host_)
  in if
    | T.null host      -> failWith "empty host, or no colon found"
    | T.null portText  -> failWith "empty port"
    | Right (port, remainder) <- T.decimal portText
    , T.null remainder
    , 0 < port -> pure (host, port)
    | otherwise -> failWith "invalid port number"

failWith :: String -> AE.Parser a
failWith msg =
  fail $ "hermod.HowToConnect.parseJSON: " ++ msg
