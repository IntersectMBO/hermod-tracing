{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Structural combinators for building and composing traces.
--
--   These operations change the /shape/ of the pipeline: they adapt message
--   types, accumulate state, route messages to different tracers, and emit
--   messages into the underlying 'T.Tracer'.
--
--   For filtering and per-message annotation (severity, privacy, detail,
--   namespace), see 'Hermod.Tracing.Trace'.
module Hermod.Tracing.Trace.Combinators (
    traceWith
  , contramapM
  , contramapMCond
  , foldTraceM
  , foldCondTraceM
  , contramap'
  , (>!$!<)
) where

import           Hermod.Tracing.Types

import           Control.Monad              (forM_, join)
import           Control.Monad.IO.Unlift
import qualified Control.Tracer             as T
import           Data.Functor.Contravariant as Contr (Contravariant, (>$<))

import           UnliftIO.MVar


-- | Emit a message into a trace.
traceWith :: Monad m => Trace m a -> a -> m ()
traceWith (Trace tr) a = T.traceWith tr (emptyLoggingContext, Right a)

-- | Contramap a monadic function over a trace.
{-# INLINE contramapM #-}
contramapM :: Monad m
  => Trace m b
  -> ((LoggingContext, Either TraceControl a)
      -> m (LoggingContext, Either TraceControl b))
  -> Trace m a
contramapM (Trace tr) mFunc = Trace $ T.Tracer $ T.emit rFunc
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
  -> Trace m a
contramapMCond (Trace tr) mFunc = Trace $ T.Tracer $ T.emit rFunc
  where
    rFunc arg = do
      condMes <- mFunc arg
      forM_ condMes (T.traceWith tr)

-- | Fold a monadic accumulator function over a trace.
--   Uses an 'MVar' to hold the state.
foldTraceM :: forall a acc m . (MonadUnliftIO m)
  => (acc -> LoggingContext -> a -> m acc)
  -> acc
  -> Trace m (Folding a acc)
  -> m (Trace m a)
foldTraceM cata initial (Trace tr) = do
  ref <- liftIO (newMVar initial)
  pure $ contramapM (Trace tr) $
    \case
      (lc, Right v) -> do
        x' <- modifyMVar ref $ \x -> do
          !accu <- cata x lc v
          pure $ join (,) accu
        pure (lc, Right (Folding x'))
      (lc, Left control) ->
        pure (lc, Left control)

-- | Like 'foldTraceM' but additionally filter the trace by a predicate.
foldCondTraceM :: forall a acc m . (MonadUnliftIO m)
  => (acc -> LoggingContext -> a -> m acc)
  -> acc
  -> (a -> Bool)
  -> Trace m (Folding a acc)
  -> m (Trace m a)
foldCondTraceM cata initial flt (Trace tr) = do
  ref <- liftIO (newMVar initial)
  pure $ contramapMCond (Trace tr) (foldF ref)
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
