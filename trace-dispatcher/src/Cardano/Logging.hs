-- | Batteries-included public interface for the Hermod tracing system.
--
-- A typical application wires up tracing in three steps:
--
-- 1. __Define trace types__: for each domain-specific message type, write
--    'LogFormatting' (human\/machine rendering, metrics) and 'MetaTrace'
--    (namespace, severity, documentation) instances.
--
-- 2. __Construct backends__: call 'mkCardanoTracer' (or 'mkCardanoTracer'')
--    with 'standardTracer', 'ekgTracer', and\/or 'forwardTracer' to build a
--    'Trace IO YourType'.
--
-- 3. __Configure__: load a 'TraceConfig' with 'readConfiguration' and apply it
--    with 'configureTracers'.  Use 'checkTraceConfiguration' to validate the
--    config against all known namespaces at startup.
--

module Cardano.Logging (
    module X
  ) where

-- Core API types and combinators (from trace-dispatcher-api)
import           Cardano.Logging.Types as X
import           Cardano.Logging.Trace as X

-- Backend constructors
import           Cardano.Logging.Tracer.Composed as X
import           Cardano.Logging.Tracer.DataPoint as X
import           Cardano.Logging.Tracer.EKG as X
import           Cardano.Logging.Tracer.Forward as X
import           Cardano.Logging.Tracer.Standard as X

-- Configuration: loading, parsing, applying, and checking
import           Cardano.Logging.Configuration as X
import           Cardano.Logging.ConfigurationParser as X
import           Cardano.Logging.Consistency as X
import           Cardano.Logging.FrequencyLimiter as X

-- Output types produced by the backend pipeline
-- (FormattedMessage, TraceObject, PreFormatted)
import           Cardano.Logging.Formatter as X

-- Utilities: showT, showTHex, showTReal, runInLoop
import           Cardano.Logging.Utils as X

-- Re-exports arrow/emit/squelch from contra-tracer for custom backend authors.
-- traceWith, contramapM, nullTracer, Tracer are shadowed by this package's own versions.
import           Control.Tracer as X hiding (Tracer, contramapM, nullTracer, traceWith)
