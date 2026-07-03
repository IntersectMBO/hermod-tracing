# Revision history for hermod-tracing-api

## 1.0.0 -- July 2026

* Initial release.  Core types and combinators extracted from `trace-dispatcher`
  into this thin, low-dependency package so that libraries only need to depend
  on `hermod-tracing-api` to define tracers and call core combinators, without
  pulling in the full implementation stack.
* Modules under `Hermod.Tracing.Types.*` carry the stable type vocabulary:
  `Trace`, `LogFormatting`, `MetaTrace`, `Namespace`, `LoggingContext`,
  `SeverityS`, `SeverityF`, `Privacy`, `DetailLevel`, `Folding`, config types,
  and doc-collector types.
* `Hermod.Tracing.Trace` and `Hermod.Tracing.Trace.Combinators` expose the
  structural pipeline combinators: `traceWith`, `contramapM`, `contramapMCond`,
  `foldTraceM`, `foldCondTraceM`, `routingTrace`, `filterTrace`, `filterTraceMaybe`.
* `Hermod.Tracing.API` is the recommended single-import front door for packages
  that only need to define trace types and dispatch messages. Combinators in
  this module have ergonomic signatures: `contramapM`/`contramapMCond` take
  `(a -> m b)`, `filterTrace` takes `(a -> Bool)`, `foldTraceM`/`foldCondTraceM`
  take `(acc -> a -> m acc)` — `LoggingContext` and `TraceControl` are hidden
  from callers.
* Annotation and filtering combinators (`withNames`, `setSeverity`, `setDetails`,
  `withPrivacy`, `filterTraceBySeverity`, …) are not part of this package; they
  live in `hermod-tracing-core` as internal implementation details.
* `contramapM` and `contramapMCond` are pure (return `Trace m a`, not
  `m (Trace m a)`).
* `PrometheusM` constructor renamed to `LabelSetM` throughout
  `Hermod.Tracing.Types.Annotations`.
* `CounterM` field type changed from `Maybe Int` to `CounterAction` for
  clarity of intent (`CounterIncrement` / `CounterAdd`).
* Package split into two sublibraries: `hermod-tracing-api:internal` (types
  and combinators) and `hermod-tracing-api:public` (the `Hermod.Tracing.API`
  front door). Consumers depending on `hermod-tracing-api` and importing
  `Hermod.Tracing.API` are unaffected.
* Made `contramap` strict and removed `contramap'` and `>!$!<`.
* `TraceConfig`'s `tcResourceFrequency` and `tcLedgerMetricsFrequency` fields
  removed; replaced by `tcPeriodicTracers :: Map Text Word64`, a generalized
  map from an arbitrary periodic-tracer identifier to a cardinal number
  interpreted in an application-specific timeunit, potentially distinct per
  identifier.
* `TraceConfig`'s `tcNodeName` field renamed to `tcApplicationName`.
