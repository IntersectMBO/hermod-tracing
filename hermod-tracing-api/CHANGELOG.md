# Revision history for hermod-tracing-api

## 1.1.0 -- October 2026

Additive release: everything a *library* needs to depend on `hermod-tracing-api`
instead of `contra-tracer`. All additions live in new modules; nothing new is
reachable through `Hermod.Tracing.Types` or `Hermod.Tracing.Trace`, so
`hermod-tracing-core-1.0.0` keeps building against this release. The one
behaviour change is that `TraceOptionForwarder`'s JSON parser reads the
deprecated queue-size keys again (below).

* New `:internal` module `Hermod.Tracing.Trace.Construct`: `mkTrace`
  (build a trace from a callback; a terminal sink that drops control
  messages), `nullTrace` (named `mempty`), `natTrace` (change the monad with a
  natural transformation, control-preserving), `premapM` (Kleisli contramap in
  `contra-tracer` argument order, effect not run when squelched), the test
  helpers `debugTrace` / `stdoutTrace`, and the bridges `toContraTracer` /
  `fromContraTracer`.
* New `:internal` module `Hermod.Tracing.Types.ShowT`: `showT`, `showTHex`,
  `showTReal` (moved from `hermod-tracing-core`'s `Hermod.Tracing.Utils`,
  which re-exports them from 1.0.1 on), so instance-only packages no longer
  need `hermod-tracing-core`.
* `Hermod.Tracing.API` additionally exports `mkTrace`, `nullTrace`, `natTrace`,
  `debugTrace`, `stdoutTrace`, `Contravariant(..)`, `(>$<)`, `showT`,
  `showTHex`, `showTReal`, and documents the rules for using a `Trace` in a
  library (control direction, parameter rule, STM rule, never configure a
  merge).
* New `:public` module `Hermod.Tracing.API.Trace`: the narrow plumbing subset
  of the front door (`Trace`, `traceWith`, `mkTrace`, `nullTrace`, `natTrace`,
  `Contravariant(..)`, `(>$<)`, `contramapM`, `contramapMCond`, `filterTrace`,
  `filterTraceMaybe`, `routingTrace`, `debugTrace`, `stdoutTrace`).
* New `:public` module `Hermod.Tracing.API.Tracer`: a `contra-tracer`-compatible
  vocabulary over `Trace` — `type Tracer = Trace`, `traceWith`, `mkTracer`,
  `nullTracer`, `natTracer`, `contramapM` (function-first argument order),
  `Contravariant(..)`, `(>$<)`, `debugTracer`, `stdoutTracer`. A library
  migrates by swapping `import Control.Tracer` for
  `import Hermod.Tracing.API.Tracer` and the build dependency for
  `hermod-tracing-api:public`. Do not import it unqualified together with
  `Hermod.Tracing.API` (`contramapM` differs in argument order).
* New `:public` module `Hermod.Tracing.API.ContraTracer`: `toContraTracer`,
  `fromContraTracer` for third-party APIs that still take a `contra-tracer`
  `Tracer`; kept separate so remaining bridges are greppable.
* `traceWith` is now `INLINE` (as in `contra-tracer`), so a squelching trace
  does not allocate the message envelope.
* `TraceOptionForwarder`'s JSON parser again reads the deprecated
  `connQueueSize` / `disconnQueueSize` when `queueSize` is absent: the larger
  of the two is used, each defaulting to its old value (128 / 192), as
  trace-dispatcher did. Existing configurations keep their queue size.
* Haddock: removed the stale mention of `ForwarderAddr`.

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
* `TraceOptionForwarder` JSON parsing no longer accepts the deprecated
  `connQueueSize` / `disconnQueueSize` fields. Use `queueSize` instead.
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
* Removed `ForwarderAddr` newtype. To specify forwarder connection, use
  `HowToConnect`.
