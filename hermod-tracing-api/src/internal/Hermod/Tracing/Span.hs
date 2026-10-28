{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Begin\/end span tracing for @hermod-tracing@.
--
-- Each 'withSpan' emits a 'SpanBegin' and exactly one matching end
-- event. The 'Maybe SpanError' field on the end says how the span
-- ended: with success ('Nothing'), or an exception ('Just').
module Hermod.Tracing.Span
  ( SpanId (..)
  , SpanTrace (..)
  , SpanError (..)
  , withSpan
  , withSpanLazy
  ) where

import           Hermod.Tracing.Trace (traceWith)
import           Hermod.Tracing.Types
import           Hermod.Tracing.Types.ShowT (showT)

import           Control.DeepSeq (NFData, force)
import qualified Control.Exception as Except
import           Control.Exception (SomeAsyncException (..), SomeException (..),
                   evaluate, fromException)
import           Control.Monad (void)
import           Control.Monad.IO.Class (MonadIO, liftIO)
import           Data.Aeson (Object, ToJSON (toJSON), Value (String), object, (.=))
import           Data.Text (Text, pack)
import           Data.Typeable (typeOf)
import           Data.Unique (hashUnique, newUnique)
import           Data.Word (Word64)
import           GHC.Clock (getMonotonicTimeNSec)
import           UnliftIO (MonadUnliftIO, withRunInIO)
import           UnliftIO.Exception (throwIO, uninterruptibleMask_)

-- | Process-unique span correlation id.
newtype SpanId = SpanId { unSpanId :: Word64 }
  deriving (Eq, Ord, Show)

-- | Why a span did not complete normally. @seException@ is @show . typeOf@
--   of the exception, prefixed with @"async:"@ for async exceptions.
--   @seMessage@ is reserved for a caller-supplied description.
data SpanError = SpanError
  { seException :: !Text
  , seMessage   :: !Text
  }
  deriving (Eq, Show)

instance ToJSON SpanError where
  toJSON :: SpanError -> Value
  toJSON (SpanError except message) = object 
    [ "exception" .= except
    , "message"   .= message ]

-- | A span event. Every 'SpanBegin' pairs with exactly one end event.
data SpanTrace
  = SpanBegin !SpanId !Text
  | SpanEnd   !SpanId !Text !Double !(Maybe SpanError)
  deriving (Show)

-- | Allocate a fresh span id. Unique within one run, not across restarts.
newSpanId :: MonadIO m => m SpanId
newSpanId = liftIO (SpanId . fromIntegral . hashUnique <$> newUnique)

-- | Run @action@ inside a span, forcing the result to NF. Lazy IO and
-- crash-on-force thunks are attributed to the span. Async exceptions
-- still produce a 'SpanEnd' (under 'uninterruptibleMask_') and are
-- rethrown.
{-# inlinable withSpan #-}
withSpan
  :: MonadUnliftIO m
  => NFData a
  => Trace m SpanTrace -> Text -> m a -> m a
withSpan = withSpanEnd SpanEnd forceNF

-- | 'withSpan' without the NF force. For result types that are not 'NFData'.
{-# inlinable withSpanLazy #-}
withSpanLazy
  :: MonadUnliftIO m
  => Trace m SpanTrace -> Text -> m a -> m a
withSpanLazy = withSpanEnd SpanEnd noForce

-- Internal
forceNF :: MonadUnliftIO m => NFData a => a -> m ()
forceNF = liftIO . void . evaluate . force

noForce :: Applicative f => a -> f ()
noForce _ = pure ()

withSpanEnd
  :: forall m a. ()
  => MonadUnliftIO m
  => (SpanId -> Text -> Double -> Maybe SpanError -> SpanTrace)
  -> (a -> m ())
  -> Trace m SpanTrace
  -> Text
  -> m a
  -> m a
withSpanEnd mkEnd forceVal tr name action = do
  spanId <- newSpanId
  !time_start <- liftIO getMonotonicTimeNSec
  traceWith tr (SpanBegin spanId name)
  -- Control.Exception.try (not UnliftIO's) because we want async
  -- exceptions caught here so a killed span still emits SpanEnd.
  result <- withRunInIO \runInIO -> Except.try @SomeException $
    runInIO do
      a <- action
      forceVal a
      pure a
  !time_end <- liftIO getMonotonicTimeNSec
  let
    ms :: Double
    !ms = fromIntegral (time_end - time_start) / 1_000_000
  case result of
    Right a -> traceWith tr (mkEnd spanId name ms Nothing) >> pure a
    Left except -> do
      let merr = Just (spanErrorFromException except)
      case fromException @SomeAsyncException except of
        Just _  -> uninterruptibleMask_ (traceWith tr (mkEnd spanId name ms merr))
        Nothing -> traceWith tr (mkEnd spanId name ms merr)
      throwIO except

spanErrorFromException :: SomeException -> SpanError
spanErrorFromException someExcept = SpanError exceptRendered "" where
  exceptRendered :: Text
  exceptRendered
    | Just (SomeAsyncException inner) <- fromException @SomeAsyncException someExcept
    = "async:" <> pack (show (typeOf inner))
    | SomeException except <- someExcept
    = pack (show (typeOf except))

-- Formatting
instance LogFormatting SpanTrace where
  forMachine :: DetailLevel -> SpanTrace -> Object
  forMachine _ (SpanBegin sid name) = mconcat
    [ "event"   .= String "begin"
    , "span_id" .= unSpanId sid
    , "name"    .= name
    ]
  forMachine _ (SpanEnd sid name ms merr) =
    machineEnd sid name ms merr

  forHuman :: SpanTrace -> Text
  forHuman (SpanBegin sid name) =
    "Span begin [" <> showT (unSpanId sid) <> "] " <> name
  forHuman (SpanEnd sid name ms merr) =
    humanEnd sid name ms merr

machineEnd :: SpanId -> Text -> Double -> Maybe SpanError -> Object
machineEnd sid name ms merr = mconcat $
  [ "event"       .= String "end"
  , "span_id"     .= unSpanId sid
  , "name"        .= name
  , "duration_ms" .= ms
  ] ++ maybe [] (\err -> [ "error" .= err ]) merr

humanEnd :: SpanId -> Text -> Double -> Maybe SpanError -> Text
humanEnd sid name ms merr = let 
  body :: Text
  body = "Span end   [" <> showT (unSpanId sid) <> "] " <> name
      <> " (" <> showT ms <> " ms)"
  in maybe body (\err -> body <> " ERROR " <> seException err) merr

-- MetaTrace
instance MetaTrace SpanTrace where
  namespaceFor :: SpanTrace -> Namespace SpanTrace
  namespaceFor SpanBegin{} = Namespace [] ["Span", "Begin"]
  namespaceFor SpanEnd{}   = Namespace [] ["Span", "End"]

  severityFor :: Namespace SpanTrace -> Maybe SpanTrace -> Maybe SeverityS
  severityFor (Namespace _ ["Span", "Begin"]) _ = Just Info
  severityFor (Namespace _ ["Span", "End"])   _ = Just Info
  severityFor _                               _ = Nothing

  documentFor :: Namespace SpanTrace -> Maybe Text
  documentFor (Namespace _ ["Span", "Begin"]) = Just
    "Start of a span: a span_id shared with the matching end event and the operation name."
  documentFor (Namespace _ ["Span", "End"]) = Just
    "End of a span. Carries duration in ms and, if the span failed, an error object."
  documentFor _ = 
    Nothing

  allNamespaces :: [Namespace SpanTrace]
  allNamespaces =
    [ Namespace [] ["Span", "Begin"]
    , Namespace [] ["Span", "End"]
    ]
