# hermod-tracing

Structured tracing and observability for Haskell applications. A composable,
efficiently-routed tracing framework built on contravariant tracers, with
support for structured logging, EKG metrics, trace forwarding, and runtime
reconfiguration.

This repository currently hosts the `trace-dispatcher` package, migrated from
[cardano-node](https://github.com/IntersectMBO/cardano-node). It will be
renamed as part of the broader hermod-tracing rebranding effort.

## Overview

`trace-dispatcher` replaces the legacy `iohk-monitoring` framework. Its design
goals are:

- **Simplicity** — define tracers with two typeclasses; the framework handles
  routing, formatting, and dispatch
- **Composability** — tracers are contravariant functors; combine and transform
  them freely
- **Configurability** — filter by severity or namespace, set detail levels, and
  enable frequency limiting, all from a YAML/JSON config file with hot-reload
  support
- **Observability** — route the same trace message simultaneously to stdout,
  a remote [`cardano-tracer`](https://github.com/IntersectMBO/cardano-node/tree/master/cardano-tracer)
  process, and EKG/Prometheus metrics

## Concepts

### Tracers and namespaces

Every tracer carries a hierarchical **namespace** (a list of `Text` segments)
that identifies it within the application. Namespaces drive configuration
lookup, documentation generation, and consistency checks.

### Implementing a traceable type

Two typeclasses must be implemented for any type that is traced:

```haskell
class LogFormatting a where
  -- Required: machine-readable JSON at the given detail level
  forMachine :: DetailLevel -> a -> AE.Object

  -- Optional: human-readable text (falls back to JSON if absent)
  forHuman :: a -> Text
  forHuman = ""

  -- Optional: extract EKG/Prometheus metrics
  asMetrics :: a -> [Metric]
  asMetrics _ = []

class MetaTrace a where
  -- Namespace segment for each constructor
  namespaceFor  :: a -> Namespace a

  -- Static severity, privacy, detail level, and documentation per namespace
  severityFor   :: Namespace a -> Maybe SeverityS
  privacyFor    :: Namespace a -> Privacy
  detailsFor    :: Namespace a -> DetailLevel
  documentFor   :: Namespace a -> Maybe Text

  -- All namespaces this type can produce (used for docs and consistency checks)
  allNamespaces :: [Namespace a]
```

### Backends

Three backend tracers are available; each should be instantiated once:

| Backend | Function | Notes |
|---|---|---|
| `Cardano.Logging.Tracer.Standard` | stdout | thread-safe, bounded buffer, human or machine format |
| `Cardano.Logging.Tracer.Forward` | TCP/socket forwarding | sends to `cardano-tracer`; public traces only |
| `Cardano.Logging.Tracer.EKG` | EKG metrics store | Counter, Gauge, Label; always active regardless of severity |

### Configuration

Tracers are configured via a YAML or JSON file keyed by namespace. For example:

```yaml
Node.ChainDB:
  severity: Notice
  detail: DNormal
  backends:
    - Stdout MachineFormat
    - EKGBackend

Node.ChainDB.AddBlockEvent.AddedBlockToQueue:
  severity: Debug
  maxFrequency: 2.0
```

An empty string key (`""`) sets the default for all tracers. Configuration can
be reloaded at runtime by sending a `TCConfig` control message.

### Frequency limiting

Wrapping a tracer with `limitFrequency` suppresses messages that exceed a
threshold (messages/second) using a budget-based algorithm to avoid jitter.
The tracer emits `StartLimiting`, `ContinueLimiting`, and `StopLimiting`
control messages through a companion tracer.

### Privacy

Traces are either `Public` (forwarded to `cardano-tracer`) or `Confidential`
(stdout only). Privacy is set in code via `MetaTrace` and cannot be overridden
by configuration, preventing inadvertent network exposure of sensitive data.

## Building

### With Nix (recommended)

```sh
# Enter the development shell
nix develop

# Build the library
cabal build trace-dispatcher

# Run the test suite
cabal test trace-dispatcher
```

### Without Nix

Requires GHC ≥ 9.6 and cabal-install. CHaP must be added to your Cabal
repository list:

```sh
cabal update
cabal build trace-dispatcher
```

See `cabal.project` for the required CHaP repository stanza and index-state.

## Documentation

Haddock documentation is published at
[hermod.cardano.intersectmbo.org](https://hermod.cardano.intersectmbo.org)
and rebuilt nightly.

Extended design documentation is in
[`trace-dispatcher/doc/trace-dispatcher.md`](trace-dispatcher/doc/trace-dispatcher.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE-OF-CONDUCT.md](CODE-OF-CONDUCT.md).
Security issues should be reported as described in [SECURITY.md](SECURITY.md).
