{-# LANGUAGE RankNTypes #-}

-- | Constructing, hoisting and bridging traces.
--
--   These are the primitives a /library/ needs when it takes a 'Trace' as a
--   parameter and has to build test doubles, adapt monads, or hand a trace to
--   a third-party API that still speaks @contra-tracer@.
--
--   __Control-direction rule.__ 'Hermod.Tracing.Types.TraceControl' messages
--   (configuration, optimisation, documentation) are injected at the /root/
--   trace that the application constructed and retained, and flow downstream
--   to the backends.  A leaf built with 'mkTrace' is a __terminal sink__: its
--   callback never sees a control message, and every control message reaching
--   it is dropped.  That is harmless for test doubles and for library-internal
--   adapters that sit /upstream/ of the root, but it means that such a trace
--   can never be configured, silenced, rate-limited or documented.  Anything
--   user-visible must therefore arrive as a 'Trace' parameter and be wrapped
--   with control-preserving combinators ('contramap', 'contramapM',
--   'filterTrace', 'natTrace', @<>@), never rebuilt from a function.
module Hermod.Tracing.Trace.Construct (
    mkTrace
  , nullTrace
  , natTrace
  , premapM
  , debugTrace
  , stdoutTrace
  , toContraTracer
  , fromContraTracer
) where

import           Hermod.Tracing.Types

import qualified Control.Tracer as T
import           Debug.Trace (traceM)


-- | Build a trace from a callback.
--
--   The callback is invoked for every message; control messages are dropped
--   (see the control-direction rule in the module header).  Only
--   'Applicative' is required, so the result can live in @IOSim@, @STM@ or a
--   pure test monad.
{-# INLINE mkTrace #-}
mkTrace :: Applicative m => (a -> m ()) -> Trace m a
mkTrace f = Trace $ T.mkTracer $ \case
    (_, Right a) -> f a
    (_, Left _)  -> pure ()

-- | The trace that does nothing.  Identical to 'mempty'; it stays /squelching/
--   in the underlying arrow representation, so functions contramapped over it
--   are never evaluated and 'Hermod.Tracing.Trace.Combinators.traceWith' costs
--   nothing.  Drops all control messages, unavoidably.
{-# INLINE nullTrace #-}
nullTrace :: Monad m => Trace m a
nullTrace = Trace T.nullTracer

-- | Change the monad of a trace with a natural transformation.
--
--   Total and structure-preserving: every message /and/ every control message
--   reaches the same handlers, reinterpreted in @n@.  The transformation must
--   be a synchronous, effect-preserving monad morphism (no forking, batching
--   or dropping), otherwise the ordering contract of
--   'Hermod.Tracing.Types.TraceControl' is violated.
{-# INLINE natTrace #-}
natTrace :: (forall x. m x -> n x) -> Trace m a -> Trace n a
natTrace h (Trace tr) = Trace (T.natTracer h tr)

-- | Contravariant transformation with a Kleisli arrow, in @contra-tracer@'s
--   argument order (function first).
--
--   Unlike 'Hermod.Tracing.Trace.Combinators.contramapM', this is built on
--   the arrow representation: the effect is /not/ run when the downstream
--   trace is squelching.  Control messages are forwarded unchanged.
{-# INLINE premapM #-}
premapM :: Monad m => (a -> m b) -> Trace m b -> Trace m a
premapM f (Trace tr) = Trace (T.contramapM g tr)
  where
    g (lc, Right a) = (\b -> (lc, Right b)) <$> f a
    g (lc, Left c)  = pure (lc, Left c)

-- | Trace strings to @stderr@ via 'Debug.Trace.traceM'.  A terminal sink for
--   tests, benchmarks and demos; works in any 'Applicative'.
debugTrace :: Applicative m => Trace m String
debugTrace = mkTrace traceM

-- | Trace strings to @stdout@.  Output may interleave when used from several
--   threads; a terminal sink for tests and demos only — applications should
--   use a configured backend instead.
stdoutTrace :: Trace IO String
stdoutTrace = mkTrace putStrLn

-- | View a trace as a plain @contra-tracer@ 'T.Tracer', for third-party APIs
--   that have not adopted Hermod.
--
--   One-way: messages sent to the result reach the same pipeline (a squelching
--   trace yields a squelching tracer), but no control message can ever enter
--   through it.  Keep the original 'Trace' for configuration — the pipeline
--   state is shared, so configuring the original also governs what flows
--   through this view.
{-# INLINE toContraTracer #-}
toContraTracer :: Monad m => Trace m a -> T.Tracer m a
toContraTracer (Trace tr) = T.contramap (\a -> (emptyLoggingContext, Right a)) tr

-- | Wrap a plain @contra-tracer@ 'T.Tracer' as a trace.  A terminal sink with
--   the contract of 'mkTrace' (control messages are dropped), squelch
--   preserving.  Transitional: prefer taking a 'Trace' parameter.
fromContraTracer :: Monad m => T.Tracer m a -> Trace m a
fromContraTracer tr = Trace $ T.traceMaybe payload tr
  where
    payload (_, Right a) = Just a
    payload (_, Left _)  = Nothing
