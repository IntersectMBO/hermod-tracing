# Revision history for hermod-tracing-prometheus

## 1.1.1 -- November 2026

* `mkTCPServerRunner` releases a connection's per-host and global slot
  even when closing the socket is interrupted by an asynchronous
  exception, such as a late `TimeoutThread` from the inactivity timeout.
  Before, each such interruption leaked one slot, and a host that
  leaked `runConnLimitPerHost` slots was refused until restart.
  Fixes IntersectMBO/hermod-tracing#28.
  Thanks to [@chadaibbhot-git](https://github.com/chadaibbhot-git) for the
  report and the fix (IntersectMBO/hermod-tracing#29).
* Added a test suite with a test for this case.

## 1.1.0 -- October 2026

* `runPrometheusSimple` and `runPrometheusSimpleWith` take a hermod `Trace` instead of a
  `contra-tracer` `Tracer`, so an application passes its configured trace directly. Breaking.
  The package no longer depends on `contra-tracer`.
* Expose label sets as `# TYPE ... gauge` for full conformance with Prometheus text exposition format.
* Bounds on `hermod-tracing-api:internal` (`^>= 1.1`) and `hermod-tracing-core` (`^>= 1.1`).
* `runPrometheusSimpleSilent` is defined with `nullTrace` (the same value as `mempty`, by its name).

## 1.0.0 -- July 2026

* Initial release. Extracted from `hermod-tracing-core`.
