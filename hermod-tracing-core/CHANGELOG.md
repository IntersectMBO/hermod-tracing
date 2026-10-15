# Revision history for hermod-tracing-core

## 1.1.0 -- October 2026

A major bump because `Hermod.Tracing` exports less (first bullet). No
integration exists on 1.0.0, so downstream packages constrain
`hermod-tracing-core ^>= 1.1` without a migration.

* `Hermod.Tracing` no longer re-exports `contra-tracer`'s `Control.Tracer`
  wholesale. It keeps the arrow primitives a custom backend is built from
  (`arrow`, `use`, `squelch`, `emit`, `effect`, `nat`) and `Contravariant(..)`
  / `(>$<)`; `mkTracer`, `natTracer`, `stdoutTracer`, `debugTracer`,
  `traceMaybe`, `squelchUnless` and the other `Control.Tracer` names are
  gone from it. They were different entities from the functions of the same
  names in `Hermod.Tracing.API.Tracer`, so `Hermod.Tracing` could not be
  imported unqualified next to the facade. Code that used them through
  `Hermod.Tracing` imports `Control.Tracer` directly, or bridges with
  `toContraTracer` / `fromContraTracer`.
* `Hermod.Tracing` re-exports `Hermod.Tracing.Trace.Construct` (`mkTrace`,
  `nullTrace`, `natTrace`, `premapM`, `debugTrace`, `stdoutTrace`,
  `toContraTracer`, `fromContraTracer`), so application code does not need
  `Hermod.Tracing.API` for them. Its haddock states which names it shares
  with `Hermod.Tracing.API` as the same entities and which five
  (`contramapM`, `contramapMCond`, `foldTraceM`, `foldCondTraceM`,
  `filterTrace`) are the envelope-level variants.
* `showT`, `showTHex` and `showTReal` now live in `hermod-tracing-api`
  (`Hermod.Tracing.Types.ShowT`, re-exported by `Hermod.Tracing.API`);
  `Hermod.Tracing.Utils` re-exports the same entities, so importing both
  `Hermod.Tracing` and `Hermod.Tracing.API` is unambiguous.
* Depends on `hermod-tracing-api ^>= 1.1` (both sublibraries); previously
  unbounded.
* Deprecated: trace-dispatcher's configuration layout (`TraceOptions`,
  `TraceOptionForwarder`, `TraceOptionNodeName`, `TraceOptionMetricsPrefix`,
  `TraceOptionResourceFrequency`, `TraceOptionLedgerMetricsFrequency`,
  `TracePrometheusSimpleRun`) is accepted again, but only in place of the
  `HermodTracing` object: inside it, or at the top of a file that
  `HermodTracing` refers to. The current layout takes precedence over it, and
  it is not accepted at the top level of a configuration file. The two
  frequencies become the `PeriodicTracers` entries `Resources` and
  `LedgerMetrics`; a negative frequency fails to parse. This lets cardano-node
  configurations migrate in steps, and will be removed once they have.
  Every configuration that 1.0.0 accepted is read as before.
* By convention, `PeriodicTracers` names are PascalCase, like namespaces; the
  example configuration `doc/config.json` and the docs use `Resources`.
* The environment variable `TRACE_DISPATCHER_LOGGING_HOSTNAME` is read again
  when `HERMOD_TRACING_LOGGING_HOSTNAME` is not set. Deprecated; will be
  removed together with trace-dispatcher's configuration layout.

## 1.0.0 -- July 2026

* Initial release: based on `trace-dispatcher-2.13.0`.
* All modules renamed from the `Cardano.Logging.*` namespace to `Hermod.Tracing.*`.
* Core types (`Trace`, `LogFormatting`, `MetaTrace`, `Namespace`, `LoggingContext`,
  severity/privacy/detail types, config types, `DocCollector`, …) and core
  combinators (`traceWith`, `contramapM`, `foldTraceM`,
  `filterTrace`, …) have been extracted into the new thin package
  `hermod-tracing-api`.  `hermod-tracing-core` now depends on that package.
* `contramapM'` combinator removed.
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
* `Hermod.Tracing.ConfigurationParser`: dropped the legacy top-level
  `"TraceOptions"`/`"TraceOptionForwarder"`/… config format
  (`parseAsLegacy`); only the `"HermodTracing"`-wrapped and flattened
  top-level formats are now accepted. `"TraceOptionResourceFrequency"` and
  `"TraceOptionLedgerMetricsFrequency"` are replaced by a
  `"PeriodicTracers"` map (see `hermod-tracing-api`'s CHANGELOG for
  `tcPeriodicTracers`).
* **Breaking config change**: the JSON key previously parsed as
  `"TraceOptionNodeName"` is now `"ApplicationName"`. Config files using
  `"TraceOptionNodeName"` must rename that key; the old key is silently
  ignored. Internally, `ConfigRepresentation` field `traceOptionNodeName`
  is renamed to `traceOptionApplicationName`, matching `hermod-tracing-api`'s
  `TraceConfig.tcApplicationName`.
