# hermod-tracing-prometheus

Optional Prometheus exposition backend for the
[hermod-tracing](https://github.com/IntersectMBO/hermod-tracing) system.

## Overview

This package provides the `PrometheusSimple` backend, which serves current EKG
metrics in the [Prometheus text exposition format](https://prometheus.io/docs/instrumenting/exposition_formats/)
directly from the host process over a minimal HTTP/TCP server. No separate
forwarding infrastructure is required.

## Usage

Add `hermod-tracing-prometheus` to your `.cabal` dependencies alongside
`hermod-tracing-core`.

The backend is selected via the `PrometheusSimple` constructor of
`BackendConfig` (from `hermod-tracing-api`), which can be set in the
application configuration file:

```yaml
HermodTracing:
  Options:
    "":
      backends:
        - EKGBackend
        - PrometheusSimple 9090
```

Or programmatically:

```haskell
import Hermod.Tracing.Types.Config (BackendConfig(..))

-- Bind to localhost only, port 9090:
PrometheusSimple False Nothing 9090

-- Bind to all IPv4 interfaces, port 9090, drop _int/_counter suffixes:
PrometheusSimple True (Just "0.0.0.0") 9090
```

The `Bool` argument enables the `nosuffix` mode, which strips type suffixes
(`_int`, `_counter`, `_real`) from metric names for a cleaner exposition.
The optional `HostName` argument sets the bind address; omitting it binds to
localhost only. Metrics are served under the path `/metrics`.

`PrometheusSimple` reads from the EKG store, so `EKGBackend` must also be
configured for the tracers whose metrics you want to expose.

> **CAUTION**: binding to a non-localhost address exposes metrics to the
> network. Only do this in an environment you control.

## DoS protection

The TCP server includes configurable hardening against connection flooding.
The `PrometheusSimpleRun` record (from `hermod-tracing-api`) can override the
defaults when starting the server:

| Field             | Default | Description                                     |
|-------------------|---------|-------------------------------------------------|
| `connTimeout`     | 22 s    | Release socket after inactivity                 |
| `connCountGlobal` | 16      | Limit total concurrent connections              |
| `connCountPerHost`| 5       | Limit concurrent connections from the same host |
| `connPerSecond`   | 8.0     | Limit requests per second                       |

## Modules

| Module                                        | Purpose                                      |
|-----------------------------------------------|----------------------------------------------|
| `Hermod.Tracing.Prometheus.Exposition`        | Render EKG samples as Prometheus text format |
| `Hermod.Tracing.Prometheus.NetworkRun`        | Hardened TCP server runner                   |
| `Hermod.Tracing.Prometheus.TCPServer`         | Top-level server wiring                      |
