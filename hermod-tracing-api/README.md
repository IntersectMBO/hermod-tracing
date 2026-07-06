# hermod-tracing-api

Thin, low-dependency API layer for the [Hermod tracing system](../hermod-tracing-core/README.md).

It provides the stable type vocabulary and core combinators that a package needs
to instrument its own operations — without pulling in backends, configuration
parsers, or Prometheus.

## When to use this package

| You need to… | Depend on… |
|---|---|
| Define trace types (`LogFormatting`, `MetaTrace`) and emit messages | **`hermod-tracing-api`** |
| Set up backends, parse config, run EKG/Prometheus | `hermod-tracing-core` |

The dependency graph is intentionally shallow: `hermod-tracing-core` depends on
`hermod-tracing-api:internal`, never the other way around.

## Sublibraries

The package exposes two sublibraries:

- **`hermod-tracing-api:internal`** — the full type vocabulary and combinators
  (`src/internal/`): `Hermod.Tracing.Types.*`, `Hermod.Tracing.Trace`,
  `Hermod.Tracing.Trace.Combinators`.
- **`hermod-tracing-api:public`** (the default library) — the single-import
  end-user front door (`src/public/`): `Hermod.Tracing.API`.

User-space packages shall depend on `hermod-tracing-api:public` and `import Hermod.Tracing.API`.

## Quickstart

```haskell
import Hermod.Tracing.API
```

That single import brings in everything needed to define and use tracers.

### 1. Define your message type

```haskell
data MyMsg
  = RequestReceived { reqId :: Int, path :: Text }
  | RequestFailed   { reqId :: Int, reason :: Text }
```

### 2. Implement `LogFormatting`

```haskell
instance LogFormatting MyMsg where
  forMachine _dl (RequestReceived rid p) =
    AE.fromList [ "kind" .= ("RequestReceived" :: Text)
                , "reqId" .= rid, "path" .= p ]
  forMachine _dl (RequestFailed rid r) =
    AE.fromList [ "kind" .= ("RequestFailed" :: Text)
                , "reqId" .= rid, "reason" .= r ]

  forHuman (RequestReceived rid p) =
    "Request " <> T.pack (show rid) <> " received: " <> p
  forHuman (RequestFailed rid r) =
    "Request " <> T.pack (show rid) <> " failed: " <> r

  asMetrics (RequestReceived _ _) = [ CounterM "requests.received" CounterIncrement ]
  asMetrics (RequestFailed   _ _) = [ CounterM "requests.failed"   CounterIncrement ]
```

### 3. Implement `MetaTrace`

```haskell
instance MetaTrace MyMsg where
  namespaceFor RequestReceived{} = Namespace [] ["Request", "Received"]
  namespaceFor RequestFailed{}   = Namespace [] ["Request", "Failed"]

  severityFor (Namespace _ ["Request", "Received"]) _ = Just Info
  severityFor (Namespace _ ["Request", "Failed"])   _ = Just Warning
  severityFor _ _                                     = Nothing

  documentFor (Namespace _ ["Request", "Received"]) = Just "A new request was received."
  documentFor (Namespace _ ["Request", "Failed"])   = Just "A request could not be fulfilled."
  documentFor _                                     = Nothing

  allNamespaces =
    [ Namespace [] ["Request", "Received"]
    , Namespace [] ["Request", "Failed"]
    ]
```

### 4. Emit messages

```haskell
traceWith myTracer (RequestReceived 42 "/api/v1/ping")
```

## Key types

| Type | Purpose |
|---|---|
| `Trace m a` | Central carrier — a contravariant tracer with per-message context |
| `LogFormatting a` | Typeclass: `forMachine`, `forHuman`, `asMetrics` |
| `MetaTrace a` | Typeclass: namespace, severity, privacy, detail, documentation |
| `Namespace a` | Hierarchical dot-separated message identifier |
| `SeverityS` | Message severity (`Debug` … `Emergency`, following RFC 5424) |
| `SeverityF` | Severity filter (`Just minSeverity` or `Silence`) |
| `Privacy` | `Public` \| `Confidential` |
| `DetailLevel` | `DMinimal` … `DMaximum` |
| `Metric` | Metric payload: `IntM`, `DoubleM`, `CounterM`, `LabelSetM` |
| `CounterAction` | `CounterIncrement` \| `CounterAdd Word64` |
| `Folding a b` | Wrapper for stateful fold-based tracers |

## Core combinators

| Combinator | Purpose |
|---|---|
| `traceWith tr msg` | Emit a message into a trace |
| `contramapM tr f` | Adapt message type monadically |
| `contramapMCond tr f` | Like `contramapM`, but can also drop messages by returning `Nothing` |
| `foldTraceM tr acc f` | Accumulate state across messages |
| `foldCondTraceM tr acc f` | Like `foldTraceM`, but can drop messages |
| `routingTrace f tracers` | Fan a message out to multiple traces |
| `filterTrace tr p` | Drop messages that fail a predicate |
| `filterTraceMaybe tr f` | Drop or transform messages |

## Metrics

`asMetrics` maps a message value to zero or more `Metric` updates. The
`hermod-tracing-core` EKG backend consumes these automatically when an EKG
tracer is wired up.

```haskell
asMetrics (BatchProcessed size) =
  [ IntM     "batch.current"   (fromIntegral size)  -- gauge: last batch size
  , CounterM "batches.total"   CounterIncrement      -- counter: +1 per batch
  , CounterM "elements.total"  (CounterAdd (fromIntegral size)) -- counter: +N
  ]
```

Metric names follow the Prometheus data model; use `.` as a namespace
separator (the backend rewrites them to `_` for Prometheus exposition).
