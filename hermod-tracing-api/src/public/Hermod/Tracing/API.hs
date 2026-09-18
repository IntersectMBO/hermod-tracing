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
-- * __Dispatch messages__: call 'traceWith' to emit, 'contramap' \/ 'contramapM'
--   to adapt types, 'foldTraceM' to accumulate state, 'routingTrace' to fan out.
--
-- * __Filter__: 'filterTrace', 'filterTraceMaybe'.
--
-- * __Construct and bridge__: 'mkTrace', 'nullTrace', 'natTrace' and the
--   test helpers 'debugTrace' \/ 'stdoutTrace'.
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
-- showT, showTHex, showTReal  -- Text rendering helpers for instances
-- @
--
-- === Using a 'Trace' in a library
--
-- Libraries that take tracers as parameters (rather than configuring
-- backends) should observe these rules; they keep the application able to
-- configure, document and reconfigure every tracer from one place:
--
-- 1. /Control direction./ Control messages (configuration, optimisation,
--    documentation) are injected by the application at the root 'Trace' it
--    constructed and retained, and flow downstream to the backends.  A trace
--    built with 'mkTrace' (or 'nullTrace') is a terminal sink that drops
--    them: fine for test doubles and for internal adapters that sit upstream
--    of the root, never for anything the user should be able to configure.
--
-- 2. /Parameter rule./ Anything user-visible arrives as a 'Trace' parameter
--    and is only ever wrapped with control-preserving combinators
--    ('contramap', 'contramapM', 'filterTrace', 'natTrace', @<>@).
--
-- 3. /STM rule./ A @Trace (STM m) a@ type-checks but can never be configured
--    or documented (both need 'IO'); use a plain @STM m ()@ callback for
--    transactional bookkeeping instead.
--
-- 4. /Never configure a merge./ @tr1 <> tr2@ broadcasts control messages to
--    both branches; register and configure the components, not the merge.
--
-- Libraries that prefer @contra-tracer@'s spellings (@Tracer@, @mkTracer@,
-- @nullTracer@, …) import "Hermod.Tracing.API.Tracer" instead of this
-- module; the two must not be imported unqualified into one module, because
-- 'contramapM' takes its arguments in the opposite order there.
--
-- === Configuration and control (consumed by @hermod-tracing-core@)
--
-- 'TraceConfig', 'ConfigOption', 'BackendConfig',
-- 'ConfigReflection', 'DocCollector',
-- 'ForwarderMode', 'TraceOptionForwarder', 'PrometheusSimpleRun'.
-- These appear in type signatures throughout the system; tracer authors
-- typically do not construct them directly.
module Hermod.Tracing.API (module Export, contramapM, contramapMCond, foldTraceM, foldCondTraceM, filterTrace) where

import           Hermod.Tracing.Types as Export hiding (Trace(..), TraceControl(..), LoggingContext(..), LogDoc(..))
import           Hermod.Tracing.Types as Export (Trace)
import           Hermod.Tracing.Trace.Combinators as Export (traceWith, routingTrace)
import           Hermod.Tracing.Trace as Export (filterTraceMaybe)
import           Hermod.Tracing.Trace.Construct as Export (mkTrace, nullTrace, natTrace, debugTrace, stdoutTrace)
import           Hermod.Tracing.Types.ShowT as Export (showT, showTHex, showTReal)
import           Data.Functor.Contravariant as Export (Contravariant (..), (>$<))

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
foldTraceM :: forall a acc m . (MonadUnliftIO m)
  => (acc -> a -> m acc)
  -> acc
  -> Trace m (Folding a acc)
  -> m (Trace m a)
foldTraceM cata = Internal.foldTraceM (const . cata)

-- | Like 'foldTraceM' but additionally filter the trace by a predicate.
foldCondTraceM :: forall a acc m . (MonadUnliftIO m)
  => (acc -> a -> m acc)
  -> acc
  -> (a -> Bool)
  -> Trace m (Folding a acc)
  -> m (Trace m a)
foldCondTraceM cata = Internal.foldCondTraceM (const . cata)

--- | Don't process further if the selector function returns 'False'.
filterTrace :: Monad m
  => (a -> Bool)
  -> Trace m a
  -> Trace m a
filterTrace f = Internal.filterTrace (f . snd)
