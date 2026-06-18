{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneKindSignatures #-}

module Cardano.Logging.Tracer.Forward
  ( HowToConnect(..)
  , Host
  , Port
  , forwardTracer
  ) where

import           Cardano.Logging.DocuGenerator
import           Cardano.Logging.Formatter (FormattedMessage (..), TraceObject)
import           Cardano.Logging.Types

import           Control.DeepSeq (NFData)
import           Control.Monad.IO.Class
import qualified Control.Tracer as T
import qualified Data.Aeson as AE
import qualified Data.Aeson.Types as AE (Parser)
import           Control.Applicative ((<|>))
import           Data.Kind (Type)
import           Data.Text as T (Text, null, unpack, breakOnEnd, unsnoc)
import           Data.Text.Read as T (decimal)
import           Data.Word (Word16)
import           GHC.Generics (Generic)


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
  | T.null t = fail "parseLocalPipe: empty Text"
  | otherwise   = pure $ T.unpack t

parseHostPort :: Text -> AE.Parser (Text, Word16)
parseHostPort t
  | T.null t
  = fail "parseHostPort: empty Text"
  | otherwise
  = let
    (host_, portText) = T.breakOnEnd ":" t
    host              = maybe "" fst (T.unsnoc host_)
  in if
    | T.null host      -> fail "parseHostPort: Empty host or no colon found."
    | T.null portText  -> fail "parseHostPort: Empty port."
    | Right (port, remainder) <- T.decimal portText
    , T.null remainder
    , 0 <= port, port <= 65535 -> pure (host, port)
    | otherwise -> fail "parseHostPort: Non-numeric port or value out of range."


---------------------------------------------------------------------------

-- | It is mandatory to construct only one forwardTracer tracer in any application!
-- Throwing away a forwardTracer tracer and using a new one will result in an exception
forwardTracer :: forall m. (MonadIO m)
  => (TraceObject -> IO ())
  -> Trace m FormattedMessage
forwardTracer write =
  Trace $ T.arrow $ T.emit $ uncurry output
 where
  output ::
       LoggingContext
    -> Either TraceControl FormattedMessage
    -> m ()
  output LoggingContext{} (Right (FormattedForwarder lo)) =
    liftIO $ write lo
  output LoggingContext{} (Left TCReset) =
    pure ()
  output lk (Left c@TCDocument {}) =
    docIt Forwarder (lk, Left c)
  output LoggingContext{} _ =
    pure ()
