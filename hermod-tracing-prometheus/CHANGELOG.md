# Revision history for hermod-tracing-prometheus

## 1.1.0 -- October 2026

* `runPrometheusSimple` and `runPrometheusSimpleWith` take a hermod `Trace` instead of a
  `contra-tracer` `Tracer`, so an application passes its configured trace directly. Breaking.
  The package no longer depends on `contra-tracer`.
* Expose label sets as `# TYPE ... gauge` for full conformance with Prometheus text exposition format.
* Bounds on `hermod-tracing-api:internal` (`^>= 1.1`) and `hermod-tracing-core` (`^>= 1.0`).

## 1.0.0 -- July 2026

* Initial release. Extracted from `hermod-tracing-core`.
