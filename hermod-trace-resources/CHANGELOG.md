# Changelog for hermod-trace-resources

## NEXT

* Replace `trace-dispatcher` dependency with `hermod-tracing-core`.
* Update `Cardano.Logging` import to `Hermod.Tracing`.

## 1.0.0

- Initial release as `hermod-trace-resources`
  (moved from `cardano-node/trace-resources`, renamed from `trace-resources`).
- Module namespace: `Hermod.Tracing.Resources.*`.
- Single public module: `Hermod.Tracing.Resources`; platform-specific
  implementation modules are internal.
