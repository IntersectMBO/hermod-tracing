**hermod-tracing-core**

This package depends on the arrow-based `contra-tracer` package (>= 0.2).

Applications that construct and configure backends import `Hermod.Tracing` from this package.
Libraries that only emit traces depend on `hermod-tracing-api:public` instead and import
`Hermod.Tracing.API` (or the `contra-tracer`-spelled `Hermod.Tracing.API.Tracer`). The two
front doors share their entities except for `contramapM`, `contramapMCond`, `foldTraceM`,
`foldCondTraceM` and `filterTrace`, which work on the message envelope here and on the payload
in the API; import one of them qualified where both are needed. `Hermod.Tracing` re-exports
only the arrow primitives of `contra-tracer`; import `Control.Tracer` directly for the rest.

The documentation can currently be found under: docs/hermod-tracing-core.md  

## Developers

Performance & Tracing Team is responsible for this library.
The primary developer is [@JürgenNF](https://github.com/jutaro).
