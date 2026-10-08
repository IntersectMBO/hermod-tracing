{-# LANGUAGE RankNTypes #-}

-- | A @contra-tracer@-compatible vocabulary over Hermod's 'Trace'.
--
--   This module exports a strict subset of the names of @Control.Tracer@
--   (contra-tracer 0.2.1), with the same signatures, constraints and argument
--   order, defined over Hermod's 'Trace'.  A library migrates from
--   @contra-tracer@ by replacing @import Control.Tracer@ with
--   @import Hermod.Tracing.API.Tracer@ and the @contra-tracer@ build
--   dependency with @hermod-tracing-api:public@; its tracer-typed API then
--   /is/ Hermod's 'Trace' (the type checker sees through the synonym), so an
--   application can hand it the traces it constructed and retained, and
--   control messages flow end to end.
--
--   Deliberately not exported: 'Trace' itself (several consumers define their
--   own event types called @Trace@), the constructor and the arrow interface.
--   The rules of "Hermod.Tracing.API" ("Using a 'Trace' in a library") apply
--   unchanged: 'mkTracer' builds a terminal sink that drops control messages.
--
--   Do not import this module and "Hermod.Tracing.API" unqualified into the
--   same module: 'contramapM' takes its arguments in the opposite order.
module Hermod.Tracing.API.Tracer (
    Tracer
  , traceWith
  , mkTracer
  , nullTracer
  , natTracer
  , contramapM
  , Contravariant (..)
  , (>$<)
  , debugTracer
  , stdoutTracer
) where

import           Hermod.Tracing.Trace.Combinators (traceWith)
import           Hermod.Tracing.Trace.Construct (debugTrace, mkTrace, natTrace, nullTrace, premapM,
                   stdoutTrace)
import           Hermod.Tracing.Types (Trace)

import           Data.Functor.Contravariant (Contravariant (..), (>$<))


-- | Hermod's 'Trace' under @contra-tracer@'s name.  A nullary synonym, so
--   partial applications such as @Tracer m@ remain legal.
type Tracer = Trace

-- | Make a trace from a callback; see 'mkTrace' (terminal sink).
{-# INLINE mkTracer #-}
mkTracer :: Applicative m => (a -> m ()) -> Tracer m a
mkTracer = mkTrace

-- | The trace that does nothing; see 'nullTrace'.
{-# INLINE nullTracer #-}
nullTracer :: Monad m => Tracer m a
nullTracer = nullTrace

-- | Change the monad with a natural transformation; see 'natTrace'.
{-# INLINE natTracer #-}
natTracer :: (forall x. m x -> n x) -> Tracer m a -> Tracer n a
natTracer = natTrace

-- | Contravariant transformation with a Kleisli arrow, function first, as in
--   @contra-tracer@.  The effect is only run when a downstream trace emits.
{-# INLINE contramapM #-}
contramapM :: Monad m => (a -> m b) -> Tracer m b -> Tracer m a
contramapM = premapM

-- | Trace strings to @stderr@ via 'Debug.Trace.traceM'; see 'debugTrace'.
debugTracer :: Applicative m => Tracer m String
debugTracer = debugTrace

-- | Trace strings to @stdout@; see 'stdoutTrace'.
stdoutTracer :: Tracer IO String
stdoutTracer = stdoutTrace
