{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TupleSections #-}
-- | Stable public API for the Hermod tracing system.
--
-- This is the single-import front door for @hermod-tracing-api@. It
-- re-exports everything a package needs to:
--
-- * __Define trace types__: write 'LogFormatting' (human\/machine rendering,
--   metrics) and 'MetaTrace' (namespace, severity, documentation) instances
--   for your domain message types.
--
-- * __Dispatch messages__: call 'traceWith' to emit, 'contramapM' \/ 'contramapM''
--   to adapt types, 'foldTraceM' to accumulate state, 'routingTrace' to fan out.
--
-- * __Filter__: 'filterTrace', 'filterTraceMaybe'.
--
-- === For tracer authors
--
-- @
-- Trace                  -- the central carrier opaque type
-- LogFormatting(..)      -- typeclass: forMachine, forHuman, asMetrics
-- MetaTrace(..)          -- typeclass: namespaceFor, severityFor, documentFor, …
-- Metric(..)             -- metric payload (IntM, DoubleM, CounterM, LabelSetM)
-- Namespace(..)          -- hierarchical trace identifier
-- SeverityS(..)          -- message severity (Debug … Emergency)
-- SeverityF(..)          -- severity filter (Nothing = Silence)
-- Privacy(..)            -- Public | Confidential
-- DetailLevel(..)        -- DMinimal … DMaximum
-- Folding(..)            -- wrapper for fold-based stateful tracers
-- @
--
-- === Configuration and control (consumed by @hermod-tracing-core@)
--
-- 'TraceConfig', 'ConfigOption', 'BackendConfig',
-- 'ConfigReflection', 'DocCollector', 'ForwarderAddr',
-- 'ForwarderMode', 'TraceOptionForwarder', 'PrometheusSimpleRun'.
-- These appear in type signatures throughout the system; tracer authors
-- typically do not construct them directly.
module Hermod.Tracing.API (module Export, contramapM, contramapMCond, foldTraceM, foldCondTraceM, filterTrace) where

import           Hermod.Tracing.Types as Export hiding (Trace(..), TraceControl(..), LoggingContext(..), LogDoc(..))
import           Hermod.Tracing.Types as Export (Trace)
import           Hermod.Tracing.Trace.Combinators as Export (traceWith, routingTrace)
import           Hermod.Tracing.Trace as Export (filterTraceMaybe)

import           qualified Hermod.Tracing.Trace.Combinators as Internal (contramapM, contramapMCond , foldTraceM, foldCondTraceM)
import           qualified Hermod.Tracing.Trace as Internal (filterTrace)

import           Control.Monad.IO.Unlift

-- | Contramap a monadic function over a trace.
{-# INLINE contramapM #-}
contramapM :: Monad m
  => Trace m b
  -> (a -> m b)
  -> Trace m a
contramapM tr f = Internal.contramapM tr apply where
  apply (x, Left c) = pure (x, Left c)
  apply (lc, Right x) = (lc, ) . Right <$> f x

-- | Like 'contramapM' but can also filter out messages by returning 'Nothing'.
{-# INLINE contramapMCond #-}
contramapMCond :: Monad m
  => Trace m b
  -> (a -> m (Maybe b))
  -> Trace m a
contramapMCond tr f = Internal.contramapMCond tr apply where
  apply (x, Left c) = pure (Just (x, Left c))
  apply (lc, Right x) = fmap ((lc, ) . Right) <$> f x

-- | Fold a monadic accumulator function over a trace.
--   Uses an 'MVar' to hold the state.
{-# INLINE foldTraceM #-}
foldTraceM :: forall a acc m . (MonadUnliftIO m)
  => (acc -> a -> m acc)
  -> acc
  -> Trace m (Folding a acc)
  -> m (Trace m a)
foldTraceM cata = Internal.foldTraceM (const . cata)

-- | Like 'foldTraceM' but additionally filter the trace by a predicate.
{-# INLINE foldCondTraceM #-}
foldCondTraceM :: forall a acc m . (MonadUnliftIO m)
  => (acc -> a -> m acc)
  -> acc
  -> (a -> Bool)
  -> Trace m (Folding a acc)
  -> m (Trace m a)
foldCondTraceM cata = Internal.foldCondTraceM (const . cata)

--- | Don't process further if the selector function returns 'False'.
{-# INLINE filterTrace #-}
filterTrace :: Monad m
  => (a -> Bool)
  -> Trace m a
  -> Trace m a
filterTrace f = Internal.filterTrace (f . snd)
