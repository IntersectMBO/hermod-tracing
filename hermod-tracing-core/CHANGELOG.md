# Revision history for hermod-tracing-core

## 1.0.0 -- July 2026

* Initial release: based on `trace-dispatcher-2.13.0`.
* All modules renamed from the `Cardano.Logging.*` namespace to `Hermod.Tracing.*`.
* Core types (`Trace`, `LogFormatting`, `MetaTrace`, `Namespace`, `LoggingContext`,
  severity/privacy/detail types, config types, `DocCollector`, …) and core
  combinators (`traceWith`, `contramapM`, `foldTraceM`,
  `filterTrace`, …) have been extracted into the new thin package
  `hermod-tracing-api`.  `hermod-tracing-core` now depends on that package.
* `routingTrace` and `contramapM'` combinators removed.
* `Hermod.Tracing` (the top-level re-export module) now carries an explicit
  export list, trimming it to the approved public surface.
* `mkCardanoTracer` / `mkCardanoTracer'` renamed to `mkHermodTracer` / `mkHermodTracer'`.
* `TraceDispatcherMessage` renamed to `HermodTracingMessage`.
* Environment variable `TRACE_DISPATCHER_LOGGING_HOSTNAME` renamed to `HERMOD_TRACING_LOGGING_HOSTNAME`.
* Prometheus modules (`Hermod.Tracing.Prometheus.*`) extracted into the new
  optional package `hermod-tracing-prometheus`.
* Internal helper `presentPrometheusM` renamed to `presentLabelSetM` in
  `Hermod.Tracing.Tracer.EKG`.
* `Hermod.Tracing.Types.NodeInfo` and `Hermod.Tracing.Types.NodeStartupInfo`
  removed — these were cardano-node–specific types with no generic utility.
* `contra-tracer` version bound loosened from `^>= 0.2.1` to unconstrained.
* Introduce `ConfigSource` in `Hermod.Tracing.ConfigurationParser`, replacing the `FilePath` parameter in `readConfiguration` and related functions. Supported sources: File (YAML or JSON), strict or lazy `ByteString`s (YAML or JSON), and pre-parsed `Aeson.Object`s.
