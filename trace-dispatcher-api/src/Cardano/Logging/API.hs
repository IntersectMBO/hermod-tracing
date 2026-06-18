-- | Stable public API for the Hermod tracing system.
--
-- This is the single-import front door for @trace-dispatcher-api@. It
-- re-exports everything a package needs to:
--
-- * __Define trace types__: write 'LogFormatting' (human\/machine rendering,
--   metrics) and 'MetaTrace' (namespace, severity, documentation) instances
--   for your domain message types.
--
-- * __Dispatch messages__: call 'traceWith' to emit, 'contramapM' \/ 'contramapM''
--   to adapt types, 'foldTraceM' to accumulate state, 'routingTrace' to fan out.
--
-- * __Filter and annotate__: 'filterTraceBySeverity', 'filterTraceByPrivacy',
--   'withNames', 'setSeverity', 'setDetails', etc.
--
-- == When to use this package vs. @trace-dispatcher@
--
-- Depend on @trace-dispatcher-api@ (and import this module) when your package
-- only needs to __define__ trace types and __call__ the core combinators — for
-- example, a library that instruments its own operations.  You get a small
-- transitive closure with no I\/O backends, no config parser, no Prometheus.
--
-- Depend on @trace-dispatcher@ (and import "Cardano.Logging") when you need
-- the __full stack__: backend constructors ('standardTracer', 'ekgTracer',
-- 'forwardTracer'), 'configureTracers', 'readConfiguration', and so on.
--
-- == Types exported by this module
--
-- === For tracer authors
--
-- @
-- Trace                  -- the central carrier type
-- LogFormatting(..)      -- typeclass: forMachine, forHuman, asMetrics
-- MetaTrace(..)          -- typeclass: namespaceFor, severityFor, documentFor, …
-- Metric(..)             -- metric payload (IntM, DoubleM, CounterM, PrometheusM)
-- Namespace(..)          -- hierarchical trace identifier
-- LoggingContext(..)     -- per-message context (namespace, severity, privacy, detail)
-- SeverityS(..)          -- message severity (Debug … Emergency)
-- SeverityF(..)          -- severity filter (Nothing = Silence)
-- Privacy(..)            -- Public | Confidential
-- DetailLevel(..)        -- DMinimal … DMaximum
-- Folding(..)            -- wrapper for fold-based stateful tracers
-- @
--
-- === Configuration and control (consumed by @trace-dispatcher@)
--
-- 'TraceControl', 'TraceConfig', 'ConfigOption', 'BackendConfig',
-- 'ConfigReflection', 'DocCollector', 'LogDoc', 'ForwarderAddr',
-- 'ForwarderMode', 'TraceOptionForwarder', 'PrometheusSimpleRun'.
-- These appear in type signatures throughout the system; tracer authors
-- typically do not construct them directly.
module Cardano.Logging.API
    ( module X
    ) where

-- Core types: Trace, LogFormatting, MetaTrace, Namespace, Metric,
--             LoggingContext, Severity, Privacy, DetailLevel, Folding,
--             TraceConfig, TraceControl, BackendConfig, …
import           Cardano.Logging.Types as X

-- Core combinators: traceWith, contramapM, contramapM', foldTraceM,
--                   foldCondTraceM, routingTrace, filterTrace*,
--                   withNames, setSeverity, setDetails, withLoggingContext, …
import           Cardano.Logging.Trace as X
