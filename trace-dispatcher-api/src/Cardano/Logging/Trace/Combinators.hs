{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Structural combinators for building and composing traces.
--
--   These operations change the /shape/ of the pipeline: they adapt message
--   types, accumulate state, route messages to different tracers, and emit
--   messages into the underlying 'T.Tracer'.
--
--   For filtering and per-message annotation (severity, privacy, detail,
--   namespace), see 'Cardano.Logging.Trace'.
module Cardano.Logging.Trace.Combinators (
    traceWith
  , withLoggingContext
  , contramapM
  , contramapMCond
  , contramapM'
  , foldTraceM
  , foldCondTraceM
  , routingTrace
  , contramap'
  , (>!$!<)
) where

import           Cardano.Logging.Types

import           Control.Monad              (forM_, join)
import           Control.Monad.IO.Unlift
import qualified Control.Tracer             as T
import           Data.Functor.Contravariant as Contr (Contravariant, (>$<))

import           UnliftIO.MVar


-- | Emit a message into a trace.
traceWith :: Monad m => Trace m a -> a -> m ()
traceWith (Trace tr) a = T.traceWith tr (emptyLoggingContext, Right a)

-- | Replace the logging context for all messages passing through this trace.
withLoggingContext :: Monad m => LoggingContext -> Trace m a -> Trace m a
withLoggingContext lc (Trace tr) = Trace $
    T.contramap (\(_lc, cont) -> (lc, cont)) tr


-- | Contramap a monadic function over a trace.
{-# INLINE contramapM #-}
contramapM :: Monad m
  => Trace m b
  -> ((LoggingContext, Either TraceControl a)
      -> m (LoggingContext, Either TraceControl b))
  -> m (Trace m a)
contramapM (Trace tr) mFunc =
  pure $ Trace $ T.Tracer $ T.emit rFunc
    where
      rFunc arg = do
        res <- mFunc arg
        T.traceWith tr res

-- | Like 'contramapM' but can also filter out messages by returning 'Nothing'.
{-# INLINE contramapMCond #-}
contramapMCond :: Monad m
  => Trace m b
  -> ((LoggingContext, Either TraceControl a)
      -> m (Maybe (LoggingContext, Either TraceControl b)))
  -> m (Trace m a)
contramapMCond (Trace tr) mFunc =
  pure $ Trace $ T.Tracer $ T.emit rFunc
    where
      rFunc arg = do
        condMes <- mFunc arg
        forM_ condMes (T.traceWith tr)

-- | Build a trace from a raw monadic action.
{-# INLINE contramapM' #-}
contramapM' :: Monad m
  => ((LoggingContext, Either TraceControl a) -> m ())
  -> Trace m a
contramapM' rFunc =
  Trace $ T.Tracer $ T.emit rFunc


-- | Fold a monadic accumulator function over a trace.
--   Uses an 'MVar' to hold the state.
foldTraceM :: forall a acc m . (MonadUnliftIO m)
  => (acc -> LoggingContext -> a -> m acc)
  -> acc
  -> Trace m (Folding a acc)
  -> m (Trace m a)
foldTraceM cata initial (Trace tr) = do
  ref <- liftIO (newMVar initial)
  contramapM (Trace tr)
      (\case
        (lc, Right v) -> do
          x' <- modifyMVar ref $ \x -> do
            !accu <- cata x lc v
            pure $ join (,) accu
          pure (lc, Right (Folding x'))
        (lc, Left control) ->
          pure (lc, Left control))

-- | Like 'foldTraceM' but additionally filter the trace by a predicate.
foldCondTraceM :: forall a acc m . (MonadUnliftIO m)
  => (acc -> LoggingContext -> a -> m acc)
  -> acc
  -> (a -> Bool)
  -> Trace m (Folding a acc)
  -> m (Trace m a)
foldCondTraceM cata initial flt (Trace tr) = do
  ref <- liftIO (newMVar initial)
  contramapMCond (Trace tr) (foldF ref)
 where
    foldF ref =
      \case
        (lc, Right v) -> do
          x' <- modifyMVar ref $ \x -> do
            !accu <- cata x lc v
            pure $ join (,) accu
          if flt v
            then pure $ Just (lc, Right (Folding x'))
            else pure Nothing
        (lc, Left control) ->
          pure $ Just (lc, Left control)

-- | Route messages to different tracers based on the message content.
--
--   The second argument must @mappend@ all possible tracers of the first
--   argument to one tracer. This is required for the configuration!
routingTrace :: forall m a. Monad m
  => (a -> m (Trace m a))
  -> Trace m a
  -> Trace m a
routingTrace rf rc = contramapM'
    (\case
      (lc, Right a) -> do
          nt <- rf a
          T.traceWith (unpackTrace nt) (lc, Right a)
      (lc, Left control) ->
          T.traceWith (unpackTrace rc) (lc, Left control))


-- | A strict contramap that evaluates both the function and the result to WHNF,
--   avoiding accidental space leaks when composing deep tracer chains.
--
--   The infix alias is '(>!$!<)'.
contramap', (>!$!<) :: Contravariant f => (a' -> a) -> (f a -> f a')

contramap' a !b =
  let !result = a Contr.>$< b
  in result

infixl 4 >!$!<

(>!$!<) = contramap'
