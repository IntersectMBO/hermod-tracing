# Revision history for hermod-tracing-api

## NEXT

* Initial release.  Core types and combinators extracted from `hermod-tracing-core`
  into this thin, low-dependency package so that libraries only need to depend
  on `hermod-tracing-api` to define tracers and call core combinators, without
  pulling in the full implementation stack.
* Modules under `Hermod.Tracing.Types.*` carry the stable type vocabulary:
  `Trace`, `LogFormatting`, `MetaTrace`, `Namespace`, `LoggingContext`,
  `SeverityS`, `SeverityF`, `Privacy`, `DetailLevel`, `Folding`, config types,
  and doc-collector types.
* `Hermod.Tracing.Trace` and `Hermod.Tracing.Trace.Combinators` expose the core
  combinators: `traceWith`, `contramapM`, `contramapM'`, `foldTraceM`,
  `foldCondTraceM`, `routingTrace`, `filterTrace`, `filterTraceMaybe`, and the
  full set of annotation combinators (`withNames`, `setSeverity`, `setDetails`,
  `withPrivacy`, …).
* `Hermod.Tracing.API` is the recommended single-import front door for packages
  that only need to define trace types and dispatch messages.  It re-exports
  all types and a curated subset of combinators, intentionally omitting the
  lower-level annotation combinators.
* `PrometheusM` constructor renamed to `LabelSetM` throughout
  `Hermod.Tracing.Types.Annotations`.
