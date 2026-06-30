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
-- Annotation combinators ('withNames', 'setSeverity', 'setDetails', etc.) are
-- intentionally excluded from this module; they are available in
-- "Hermod.Tracing.Trace" for use within @hermod-tracing-core@ itself.
--
-- == When to use this package vs. @hermod-tracing-core@
--
-- Depend on @hermod-tracing-api@ (and import this module) when your package
-- only needs to __define__ trace types and __call__ the core combinators — for
-- example, a library that instruments its own operations.  You get a small
-- transitive closure with no I\/O backends, no config parser, no Prometheus.
--
-- Depend on @hermod-tracing-core@ (and import "Hermod.Tracing") when you need
-- the __full stack__: backend constructors ('standardTracer', 'ekgTracer',
-- 'forwardTracer'), 'configureTracers', 'readConfiguration', and so on.
--
-- == Types exported by this module
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
-- 'ConfigReflection', 'DocCollector', 'LogDoc', 'ForwarderAddr',
-- 'ForwarderMode', 'TraceOptionForwarder', 'PrometheusSimpleRun'.
-- These appear in type signatures throughout the system; tracer authors
-- typically do not construct them directly.
module Hermod.Tracing.API (module X) where

import           Hermod.Tracing.Types as X hiding (Trace(..), TraceControl(..), LoggingContext(..))
import           Hermod.Tracing.Types as X (Trace)
import           Hermod.Tracing.Trace.Combinators as X
                   ( traceWith, contramapM, contramapMCond, contramapM'
                   , foldTraceM, foldCondTraceM, routingTrace
                   , contramap', (>!$!<)
                   )
import           Hermod.Tracing.Trace as X (filterTrace, filterTraceMaybe)
