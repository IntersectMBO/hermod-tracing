-- | Batteries-included public interface for the Hermod tracing system.
--
-- A typical application wires up tracing in three steps:
--
-- 1. __Define trace types__: for each domain-specific message type, write
--    'LogFormatting' (human\/machine rendering, metrics) and 'MetaTrace'
--    (namespace, severity, documentation) instances.
--
-- 2. __Construct backends__: call 'mkHermodTracer' (or 'mkHermodTracer'')
--    with 'standardTracer', 'ekgTracer', and\/or 'forwardTracer' to build a
--    'Trace IO YourType'.
--
-- 3. __Configure__: load a 'TraceConfig' with 'readConfiguration' and apply it
--    with 'configureTracers'.  Use 'checkTraceConfiguration' to validate the
--    config against all known namespaces at startup.
--
-- === Importing alongside the API facade
--
-- This module and "Hermod.Tracing.API" (from @hermod-tracing-api@) export the
-- /same/ entities for the types, 'traceWith', 'routingTrace',
-- 'filterTraceMaybe', the constructors of "Hermod.Tracing.Trace.Construct"
-- ('mkTrace', 'nullTrace', 'natTrace', 'premapM', …) and the @showT@ helpers,
-- so importing both unqualified is unambiguous for those.  Five names are
-- /different/ entities: 'contramapM', 'contramapMCond', 'foldTraceM',
-- 'foldCondTraceM' and 'filterTrace' work on the full message envelope
-- (@(LoggingContext, Either TraceControl a)@) here, and on the payload @a@
-- in "Hermod.Tracing.API".  Application code that needs both imports one of
-- the two qualified.  "Hermod.Tracing.API.Tracer" (the @contra-tracer@-spelled
-- facade) shares no names with this module other than the common ones above
-- and @contramapM@, which it defines with the function first.
--
-- The names of @contra-tracer@'s @Control.Tracer@ are /not/ re-exported here
-- (only the arrow primitives below are); import @Control.Tracer@ directly for
-- a plain @contra-tracer@ @Tracer@, @mkTracer@, @natTracer@ etc., or use
-- 'toContraTracer' \/ 'fromContraTracer' to bridge.

module Hermod.Tracing (
    module X
  ) where

-- Core API types and combinators (from hermod-tracing-api)
import           Hermod.Tracing.Types as X
import           Hermod.Tracing.Trace as X
import           Hermod.Tracing.Trace.Construct as X
import           Data.Functor.Contravariant as X (Contravariant (..), (>$<))

-- Backend constructors
import           Hermod.Tracing.Tracer.Composed as X
import           Hermod.Tracing.Tracer.DataPoint as X
import           Hermod.Tracing.Tracer.EKG as X
import           Hermod.Tracing.Tracer.Forward as X
import           Hermod.Tracing.Tracer.Standard as X

-- Configuration: loading, parsing, applying, and checking
import           Hermod.Tracing.Configuration as X
import           Hermod.Tracing.ConfigurationParser as X
import           Hermod.Tracing.Consistency as X
import           Hermod.Tracing.FrequencyLimiter as X

-- Output types produced by the backend pipeline
-- (FormattedMessage, TraceObject, PreFormatted)
import           Hermod.Tracing.Formatter as X

-- Utilities: showT, showTHex, showTReal, runInLoop
import           Hermod.Tracing.Utils as X

-- The arrow primitives of contra-tracer, for custom backend authors
-- (a backend is @Trace $ arrow $ emit …@).  Nothing else of Control.Tracer
-- is re-exported, so that this module can be imported together with the
-- Hermod.Tracing.API.* facades without name clashes.
import           Control.Tracer as X (arrow, use, squelch, emit, effect, nat)
