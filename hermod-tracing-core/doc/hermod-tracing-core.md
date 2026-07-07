# hermod-tracing-core: efficient, simple and flexible program tracing

`hermod-tracing-core` is a library that enables definition of __tracing systems__ -- systems that collect and manage traces -- as evidence of program execution.

- [hermod-tracing-core: efficient, simple and flexible program tracing](#hermod-tracing-core-efficient-simple-and-flexible-program-tracing)
- [Introduction](#introduction)
  - [Rationale](#rationale)
  - [Key Recommendations for Developers](#key-recommendations-for-developers)
- [Basic Tracer Topics](#basic-tracer-topics)
  - [Tracer Construction Basics](#tracer-construction-basics)
  - [Namespace Concept Explanation](#namespace-concept-explanation)
  - [Typeclasses Overview](#typeclasses-overview)
    - [LogFormatting Typeclass](#logformatting-typeclass)
    - [MetaTrace Typeclass](#metatrace-typeclass)
  - [Metrics Integration](#metrics-integration)
  - [Frequency Limiting in Trace Filtering](#frequency-limiting-in-trace-filtering)
  - [Configuration](#configuration)
- [Advanced Tracer Topics](#advanced-tracer-topics)
  - [Message Filtering based on Severity](#message-filtering-based-on-severity)
  - [Comprehensive Trace Filtering](#comprehensive-trace-filtering)
  - [Privacy Annotations](#privacy-annotations)
  - [Detail Level in Trace Presentation](#detail-level-in-trace-presentation)
  - [Fold-Based Aggregation](#fold-based-aggregation)
  - [Routing Mechanism](#routing-mechanism)
  - [Documentation Generation](#documentation-generation)
  - [Consistency Checking](#consistency-checking)
  - [Trace Backends Overview](#trace-backends-overview)
  - [Data Points Overview and Deprecation Notice](#data-points-overview-and-deprecation-notice)
- [Appendix](#appendix)
  - [References](#references)
  - [Future work](#future-work)
    - [Versioning](#versioning)
    - [Trace Consumers](#trace-consumers)

# Introduction

## Rationale

The `hermod-tracing-core` library serves as a sophisticated solution for streamlined and effective tracing systems. Built upon the arrow-based `contra-tracer` framework, it provides the following capabilities:

- Persistent activation of all tracers, adhering to the configured severity levels.

- Granular configuration (such as filtering, limiting) of individual tracers based on hierarchical namespaces, extending down to individual messages.

- Seamless transmission of traces to a dedicated server capable of handling traces from multiple clients.

- Dynamic reconfiguration (i.e. hot-reloading) of tracing settings within a running application.

- Automatic generation of comprehensive documentation encompassing all trace messages, metrics, and datapoints.

- Sanity and consistency checking of tracer implementations and tracing settings based on the system's introspective capability.

## Key Recommendations for Developers

Kindly consider the following important suggestions:

- The current tracing system employs two methods for message identification: a hierarchical name known as its Namespace and the Kind field in machine representation. Our implementation is rooted in the namespace, and we are actively moving towards deprecating the Kind field for a singular reliance on namespaces. Therefore, we strongly recommend utilizing namespaces for any trace analysis tools, as the _Kind field will be phased out in the near future_.

- Avoid using strictness annotations for trace types. Given that trace messages are either promptly discarded or instantly converted to another format without storage, strictness annotations introduce unnecessary inefficiencies without tangible benefits.

- When developing new tracers, consider creating the new tracers first and subsequently mapping to old tracers.

- Bug reports and contributions are welcome via the project issue tracker.

# Basic Tracer Topics

## Tracer Construction Basics

1. Define an Algebraic Data Type (ADT) and assign distinct constructors to each trace message.

An example is:

```haskell
data TraceAddBlockEvent blk =
    IgnoreBlockOlderThanK (RealPoint blk)
  | IgnoreBlockAlreadyInVolatileDB (RealPoint blk)
  ...
```

2. Create a tracer for this data type using the provided Haskell function:

```haskell
-- | Construct a hermod tracer.
-- and an instance of MetaTrace for meta-information such as
-- severity, privacy, details, and backends.
-- The tracer receives those backends as arguments:
--   * 'trStdout':  stdout tracing
--   * 'trForward': trace forwarding
--   * 'mbTrEkg':   (optional) EKG monitoring
-- The tracer is supplied with a 'name' as an array of text, which is prepended to its namespace.
-- This function returns the new tracer.

mkHermodTracer :: forall evt.
    ( LogFormatting evt
    , MetaTrace evt )
  => Trace IO FormattedMessage
  -> Trace IO FormattedMessage
  -> Maybe (Trace IO FormattedMessage)
  -> [Text]
  -> IO (Trace IO evt)
```

It is imperative that the tracer backends (the first three parameters) remain consistent across all tracers. For example, only one stdout backend is permitted for use in any program.

3. Configure the returned tracer with:

```haskell
-- | Invoke this function during initialization (and potentially later for reconfiguration).
-- ConfigReflection is utilized to gather information about the tracers
-- and is employed to optimize the tracers.
-- TraceConfig represents the configuration, typically loaded from a configuration file.
-- While it is feasible to provide more than one tracer of the same type,
-- this scenario is not common.
-- This function does not return a value.

configureTracers :: forall a m.
    ( MetaTrace a
    , MonadIO m )
  => ConfigReflection
  -> TraceConfig
  -> [Trace m a]
  -> m ()
```

4. Trace Emission Process

To emit a trace, employing a message and its corresponding tracer, utilize the `traceWith` function:

```haskell
traceWith :: Trace m a -> a -> m ()
-- For example:
addBlockTracer <- mkHermodTracer trStdout trForward (Just trEkg) ["ChainDB"]
configureTracers configReflect config [addBlockTracer]
..
traceWith addBlockTracer (IgnoreBlockOlderThanK p)
```

## Namespace Concept Explanation

Understanding the concept of namespaces is crucial for comprehending the tracing system and the `MetaTrace` typeclass. Tracers are systematically organized within a hierarchical tracer namespace, with tree nodes and leaves identified by `Text` name components.

The tracing system requires careful organization to ensure that all messages possess a unique name within this namespace. Moreover, the same tracer type can be utilized in different contexts, such as for local and remote messages. To enable this flexibility, the 'inner' namespace is prefixed by the namespace passed to a tracer during construction (refer to `mkHermodTracer` example above).

```haskell
-- A unique identifier for every message, composed of arrays of text
-- A namespace can also appear with the tracer name (e.g., "ChainDB.OpenEvent.OpenedDB"),
-- or more prefixes; currently, a NamespaceOuter is used.
-- The inner namespace may not be empty.
data Namespace a = Namespace {
    nsPrefix :: [Text]
  , nsInner  :: [Text]}
```

Every namespace is composed of:

- system namespace
- tracer namespace (argument of mkHermodTracer)
- inner namespace (provided by the MetaTrace typeclass)

The tracer namespace serves pivotal roles in:

- __Documentation__: It defines the overall structure of the generated documentation output.

- __Configuration__: It allows reference to tracers that need reconfiguration, such as altering their severity.

- __Output__: The messages carry the tracer namespace, providing clarity and context in the output.

## Typeclasses Overview

For the effective integration of trace messages into the tracing system, two essential typeclasses must be implemented: one for message formatting and another for meta-information.

### LogFormatting Typeclass

The `LogFormatting` typeclass governs the presentation of trace messages, encompassing the mapping of traces to metrics and messages. It includes the following methods:

- The `forMachine` method caters to a machine-readable representation, adaptable based on the detail level. Implementation is mandatory for the trace author. The system will render this,
along with trace metadata, as JSON of type `Hermod.Tracing.Types.TraceMessage.TraceMessage`.

- The `forHuman` method renders the message in a human-readable form. Its default implementation is an
empty text. Whenever the system encounters the empty text, it will replace it with the machine-readable JSON, rendering it as a value in `{"data": <value>}`, preventing potential loss of log information

- The `asMetrics` method portrays the message as 0 to n metrics. The default implementation assumes no metrics. Each metric can optionally specify a hierarchical identifier as a `[Text]`.

```haskell
class LogFormatting a where
  -- Machine readable representation with varying details based on the detail level.
  forMachine :: DetailLevel -> a -> Aeson.Object

  -- Human readable representation.
  forHuman :: a -> Text
  forHuman _v = ""

  -- Metrics representation.
  asMetrics :: a -> [Metric]
  asMetrics _v = []
```

Metrics, represented as numbers, serve to monitor the running system and can be accessed, for example, through Prometheus.

```haskell
data Metric
  -- Integer metric with a named identifier.
    = IntM Text Integer
  -- Double metric with a named identifier.
    | DoubleM Text Double
  -- Counter metric: increment by one or add a given value.
    | CounterM Text CounterAction
  -- Labelled set of key-value pairs for dimensional metrics.
    | LabelSetM Text [(Text, Text)]
  deriving (Show, Eq)
```

### MetaTrace Typeclass

The `MetaTrace` typeclass plays a pivotal role in providing meta-information for trace messages. It includes the following methods:

- __namespaceFor__: Offers a distinct (inner) namespace for each trace message.

- __severityFor__: Provides severity for a given namespace. As some severities depend not only on the message type but also on the individual message, the actual message may be passed as well.

- __privacyFor__: Determines whether a message is `Private` or `Public`. Private messages are not forwarded and are only displayed on the stdout trace. If no implementation is given, `Public` is chosen.

- __detailsFor__: Specifies the level of details for printing messages. Options include `DMinimal`, `DNormal`, `DDetailed`, and `DMaximum`. If no implementation is given, `DNormal` is chosen.

- __documentFor__: Allows the addition of optional documentation for messages as text. See section [Documentation Generation](#documentation-generation) later in this document.

- __metricsDocFor__: Enables the addition of documentation for metrics carried by the respective message. If no implementation is given, the default is no metrics.

- __allNamespaces__: Must return an array with all namespaces of this trace type.

```haskell
class MetaTrace a where
  namespaceFor  :: a -> Namespace a

  severityFor   :: Namespace a -> Maybe a -> Maybe SeverityS

  privacyFor    :: Namespace a -> Maybe a -> Maybe Privacy
  privacyFor _ _ =  Just Public

  detailsFor    :: Namespace a -> Maybe a -> Maybe DetailLevel
  detailsFor _ _ =  Just DNormal

  documentFor   :: Namespace a -> Maybe Text

  metricsDocFor :: Namespace a -> [(Text, Text)]
  metricsDocFor _ = []

  allNamespaces :: [Namespace a]
```

## Metrics Integration

Metrics are seamlessly incorporated into the system through regular trace messages implementing the `asMetrics` function within the `LogFormatting` typeclass. Unlike other trace components, metrics are not subjected to filtering and are consistently provided. This occurs as long as the `EKGBackend` is configured for the message. The `EKGBackend` then forwards these metrics for additional processing. Subsequently, they are dispatched as Prometheus metrics, extending their utility and visibility.

It is essential to implement the metricsDoc function of the MetaTrace typeclass, as this information is utilized to optimize system performance.

The `MetricsPrefix` configuration option (under `HermodTracing`) can be used to prepend a prefix to any metrics name. For example, the prefix could be `"my.application"`.

## Frequency Limiting in Trace Filtering

Frequency filtering is an integral aspect of trace filtering, offering an optional mechanism to limit the observable frequency of individual trace messages.

In essence, this involves a fair and probabilistic suppression of messages within a particular trace when their moving-average frequency surpasses a specified threshold parameter.

The frequency limiter, in addition to controlling message frequency, emits a suppression summary message under specific conditions:

- When message suppression commences.
- Every 10 seconds during active limiting, providing the count of suppressed messages.
- When message suppression concludes, indicating the total number of suppressed messages.

Usually frequency limiters can be just added by configuration, for special cases you
can construct them in your code. Each frequency limiter is assigned a name for identification purposes:

```haskell
limitFrequency
  :: forall a m . MonadUnliftIO m
  => Double   -- messages per second
  -> Text     -- name of this limiter
  -> Trace m HermodTracingMessage -- the limiter's messages
  -> Trace m a -- the trace subject to limitation
  -> m (Trace m a) -- the original trace
```

It is important to note that frequency filtering is designed to be applied selectively to a subset of traces, specifically those identified as potentially noisy. The configuration of frequency limits can thus be tailored to this subset of traces.

## Configuration

The configurability provided by this library relies on:

1. __Tracer Namespace-based Configurability__: Configurable down to single message granularity based on tracer namespaces.

2. __Runtime Reconfigurability__: Triggered by invoking `configureTracers`, enabling changes during program execution.

The usual form to provide a configuration is via a configuration file, which can be in JSON or YAML format. The options that
can be given based on a namespace are: `severity`, `detail`, `backends` and `maxFrequency`.

The top-level `HermodTracing` object also accepts three optional global keys:

- `Forwarder` — forwarder connection options (queue size, verbosity, reconnect delay).
- `MetricsPrefix` — a string prepended to all metric names.
- `PeriodicTracers` — a map from arbitrary tracer identifiers to cardinal numbers. The numbers are interpreted by the host application (as millisecond delays, slot counts, or any other application-defined unit). A value of `0` signals that the named tracer should not run; an absent key leaves the host free to apply its own default.

Backends can be a combination of `Forwarder`, `EKGBackend`, `PrometheusSimple [suffix|nosuffix] [bindhost] <port>` and
one of `Stdout MachineFormat`, `Stdout HumanFormatColoured` and `Stdout HumanFormatUncoloured`.

The connection for the `Forwarder` backend is configured in the host application via the `HowToConnect` value passed when constructing the forward sink. Both local socket paths and TCP connections are supported. The host application typically takes the `Initiator` role (connecting to a fixed acceptor endpoint), though `Responder` mode (accepting incoming connections) is also supported for debugging or specific deployment scenarios.

The `PrometheusSimple` backend provides Prometheus metrics _directly from the process_, without forwarding. It is implemented in the separate `hermod-tracing-prometheus` package, which must be added as a dependency and wired up at application startup. It always applies to all tracers globally, and should only be configured once.
Providing an available port number in the connection string is mandatory; this will bind to localhost only by default. By specifying a bind host, the metrics can be queried remotely, e.g. over IPv4 by
binding to `0.0.0.0`, or IPv6 by binding to `::`. Metrics will be available under the URL `/metrics`.
The `nosuffix` modifier removes suffixes like `_int` from metrics names, making them more similar to those in the old system; `suffix` is the implicit default and can be omitted.

*CAUTION*: Generally allowing remote queries of Prometheus metrics is risky and should only be done in an environment you control.

The empty-string namespace key `""` matches all tracers and serves as the catch-all default. `_root_` may be used as a more readable alias for `""` in both YAML and JSON configs.

```yaml
HermodTracing:
  Options:
    _root_: # Options for all tracers, if not overwritten (alias for ""):
      severity: Notice
      detail: DNormal
      backends:
        - Stdout MachineFormat
        - EKGBackend
        - Forwarder
        - 'PrometheusSimple :: 1234' # Prometheus metrics available over IPv6 (and localhost) on port 1234

    ChainDB: # Show as well messages with severity Info for all ChainDB traces.
      severity: Info
      detail: DDetailed

    ChainDB.AddBlockEvent.AddedBlockToQueue: # Limit the AddedBlockToQueue events to a maximum of two per second.
      maxFrequency: 2.0

  Forwarder: # Configure the forwarder
    maxReconnectDelay: 20

  # Any metrics emitted will get this prefix
  MetricsPrefix: "my.application.metrics."

  # Named periodic tracers: host-interpreted cardinal numbers (0 = do not run)
  PeriodicTracers:
    heartbeat: 5000
```

The same in JSON looks like this:

```json
{
  "HermodTracing": {
    "Options": {
      "": {
        "severity": "Notice",
        "detail": "DNormal",
        "backends": [
          "Stdout MachineFormat",
          "EKGBackend",
          "Forwarder",
          "PrometheusSimple :: 1234"
        ]
      },
      "ChainDB": {
        "severity": "Info",
        "detail": "DDetailed"
      },
      "ChainDB.AddBlockEvent.AddedBlockToQueue": {
        "maxFrequency": 2.0
      }
    },
    "Forwarder": {
      "maxReconnectDelay": 20
    },
    "MetricsPrefix": "my.application.metrics.",
    "PeriodicTracers": {
      "resources": 5000
    }
  }
}
```

# Advanced Tracer Topics

The functionality of the new tracing system is composable using basic combinators defined on contravariant tracing.
In this part of the document we introduce the underlying functions. You should look here if you want to
implement some advanced functionality.

## Message Filtering based on Severity

The concept of severity in the new system is articulated through an enumeration outlined in [section 6.2.1 of RFC 5424](https://tools.ietf.org/html/rfc5424#section-6.2.1). The severity levels, ranging from the least severe (`Debug`) to the most severe (`Emergency`), provide a framework for ignoring messages with severity levels below a globally configured severity cutoff.

To enhance severity filtering, we introduce the option of `Silence`. This addition allows for the unconditional silencing of a specific trace, essentially representing the deactivation of tracers — a semantic continuation of the functionality in the legacy system.

The following trace combinators play a role in modifying the annotated severity of a trace:

```haskell
-- Sets severities for the messages in this trace based on the MetaTrace class
withSeverity :: forall m a. (Monad m, MetaTrace a) => Trace m a -> Trace m a

-- Sets severity for the messages in this trace
setSeverity :: Monad m => SeverityS -> Trace m a -> Trace m a

-- Filters out messages with a severity less than the given one
filterTraceBySeverity :: Monad m
  => Maybe SeverityF
  -> Trace m a
  -> Trace m a
```

When these combinators are applied multiple times to a single trace, only the outermost application has an effect, rendering subsequent applications inconsequential.

In the absence of trace context or configured severity overrides, `Info` serves as the default severity.

## Comprehensive Trace Filtering

A versatile filtering mechanism is provided, granting access to both the object and a `LoggingContext`, encompassing the namespace along with optional severity, privacy, and detail level:

```haskell
-- Don't process further if the result of the selector function
-- is False.
filterTrace :: (Monad m)
  => ((LoggingContext, a) -> Bool)
  -> Trace m a
  -> Trace m a

-- Context carried by any log message
data LoggingContext = LoggingContext {
    lcNSInner   :: [Text]
  , lcNSPrefix  :: [Text]
  , lcSeverity  :: Maybe SeverityS
  , lcPrivacy   :: Maybe Privacy
  , lcDetails   :: Maybe DetailLevel
  }
```

For instance, you can create a filter function to display only _Public_ messages:

```haskell
filterTrace (\(c, _) -> case lcPrivacy c of
                Just s  -> s == Public
                Nothing -> False) -- privacy unknown, don't send out
```

This capability allows for flexible and fine-grained control over the inclusion or exclusion of messages based on a variety of contextual criteria.

## Privacy Annotations

In our tracing system, privacy annotations empower the distinction of messages that remain within the system and are not sent over the network, but are solely displayed on stdout. This privacy feature is defined through the following enumeration:

```haskell
data Privacy
    = Confidential | Public
```

When a trace carries a __Confidential__ privacy level, it implies that the trace remains internalized within the system, with the exception of being displayed via standard output.

The annotation mechanism for privacy mirrors that of severity:

```haskell
-- Sets privacy for the messages in this trace based on the MetaTrace class
withPrivacy :: forall m a. (Monad m, MetaTrace a) => Trace m a -> Trace m a

-- Sets privacy Confidential for the messages in this trace
privately :: Monad m => Trace m a -> Trace m a

-- Only processes messages further with a privacy greater than the given one
filterTraceByPrivacy :: (Monad m) =>
     Maybe Privacy
  -> Trace m a
  -> Trace m a
```

In the absence of privacy annotations, `Public` serves as the default privacy level.

Trace privacy, unlike severity, is not configurable.

Trace filtering responds to privacy context as follows:

1. Traces marked as `Confidential` can solely reach the `stdout` trace-out.
2. Traces marked as `Public` reach both the `stdout` and `trace-forwarder` trace-outs.

Effectively, preventing leaks of `Confidential` traces due to logging misconfiguration is inherent — any potential leak can only occur if the user explicitly permits network access to the standard output of the traced program.

## Detail Level in Trace Presentation

A crucial facet of trace presentation is the degree of detail provided for each trace. This consideration holds significance because the generated program traces may inherently include exhaustive details. Presenting every intricate detail in its entirety could impose a considerable burden on trace handling.

To address this, a configurable mechanism for controlling the level of detail is introduced, allowing customization down to specific messages.

The control over detail levels is manifested through the following enumeration:

```haskell
data DetailLevel = DMinimal | DNormal | DDetailed | DMaximum
```

This detail level control ensures that the presentation of traces strikes a balance between informativeness and efficiency, catering to diverse needs and preferences.

## Fold-Based Aggregation

When there is a need for aggregating information from multiple consecutive messages, the following fold functions can be employed:

```haskell
-- Folds the monadic cata function with acc over a.
-- Uses an MVar to store the state
foldTraceM :: forall a acc m . (MonadUnliftIO m)
  => (acc -> a -> m acc)
  -> acc
  -> Trace m (Folding a acc)
  -> m (Trace m a)

-- Like foldTraceM, but filters the trace by a predicate.
foldCondTraceM :: forall a acc m . (MonadUnliftIO m)
  => (acc -> a -> m acc)
  -> acc
  -> (a -> Bool)
  -> Trace m (Folding a acc)
  -> m (Trace m a)
```

To facilitate typechecking, the `Folding` type is utilized, and it can be removed by the `unfold` function:

```haskell
newtype Folding a acc = Folding acc

unfold :: Folding a b -> b
unfold (Folding b) = b
```

Given that tracers can be invoked from different threads, an `MVar` is internally employed to ensure correct behavior.

As an illustrative example, let's consider a scenario where we want to log a measurement value along with the sum of all measurements recorded thus far. We define a `Stats` type to store the sum alongside the measurement, and a `fold`-compatible function to calculate new `Stats` from old `Stats` and `Measure`:

```haskell
data Stats = Stats {
    sMeasure :: Double,
    sSum     :: Double
    }

calculateS :: MonadIO m => Stats -> Double -> m Stats
calculateS Stats{..} val = pure $ Stats val (sSum + val)
```

With these components in place, we can define the aggregation tracer using the `foldTraceM` procedure. Subsequently, when we log measurement values, the tracer outputs the corresponding `Stats`:

```haskell
aggregationTracer <- foldTraceM calculateS (Stats 0.0 0.0) exampleTracer
traceWith aggregationTracer 1.1 -- measure: 1.1 sum: 1.1
traceWith aggregationTracer 2.0 -- measure: 2.0 sum: 3.1
```

This demonstrates how fold-based aggregation facilitates the accumulation of information over consecutive messages, enabling insightful data summaries.

## Routing Mechanism

When there is a need to route a trace message to different tracers based on specific criteria, the following function proves valuable:

```haskell
-- Allows routing to different tracers, based on the message being processed.
-- The second argument must mappend all possible tracers of the first
-- argument to one tracer. This is required for the configuration!
routingTrace :: forall m a. Monad m
  => (a -> m (Trace m a))
  -> Trace m a
  -> Trace m a

let resTrace = routingTrace routingFunction (tracer1 <> tracer2)
  where
    routingFunction LO1 {} = tracer1
    routingFunction LO2 {} = tracer2
```

In this context, the second argument must encapsulate the combination (using `mappend`) of all tracers utilized in the routing trace function into a single tracer. This amalgamation is crucial for the subsequent configuration steps.

While a more secure interface could be constructed using a map of values to tracers, the choice here prioritizes the ability for comprehensive pattern matching. The flexibility offered by full pattern matching outweighs the potential disadvantages, given the context.

Similarly, to route a single trace to multiple tracers simultaneously, the fact that `Tracer` is a `Semigroup` allows us to utilize the `<>` operator or `mconcat` for lists of tracers:

```haskell
(<>) :: Monoid m => m -> m -> m
mconcat :: Monoid m => [m] -> m
```

For instance, to direct messages from one trace to two tracers simultaneously, we can use:

```haskell
let resTrace = tracer1 <> tracer2
```

## Documentation Generation

The self-documentation capabilities of Hermod rely on annotation / doc-strings defined via the `documentFor` and `metricsDocFor` methods within the `MetaTrace` typeclass. A specialized execution of the system mode emits documentation for all annotated traces,
utilizing the tracer namespace to structure the document.  

To generate the documentation, import the `Hermod.Tracing.DocuGenerator` module. First, call `documentTracer` for each tracer your application defines. The resulting `DocTracer` values can be combined with `<>` and then passed to one of:

* `docuResultsToText` to render a comprehensive markdown document of all traces (requires a `TraceConfig`)
* `docuResultsToNamespaces` to render a flat list of trace message namespaces
* `docuResultsToMetricsHelptext` to render a JSON object where metric names are mapped to their docstrings

For `docuResultsToText`, a full application config yields the most accurate output, but the library's `emptyTraceConfig` will suffice for a minimal run.

```haskell
-- | Document a single tracer and return a DocTracer result.
documentTracer :: forall a.
     MetaTrace a
  => Trace IO a
  -> IO DocTracer

-- | Render a comprehensive markdown document from collected DocTracer results.
docuResultsToText :: DocTracer -> TraceConfig -> Text

-- For example:
b1 <- documentTracer tracer1
b2 <- documentTracer tracer2
T.writeFile "Docu.md" (docuResultsToText (b1 <> b2) myTraceConfig)
```

A generated documentation snippet for a simple message may appear as follows:

__Forge.Loop.StartLeadershipCheck__

> Start of the leadership check.

Severity:  `Info`
Privacy:   `Public`
Details:   `DNormal`

From the current configuration:

Backends:
      `EKGBackend`,
      `Stdout MachineFormat`,
      `Forwarder`
Filtered `Visible` by config value: `Info`

## Consistency Checking

As namespaces are essentially strings, the type system doesn't inherently ensure the consistency of namespaces. To address this concern, we have incorporated consistency check functionality into `hermod-tracing-core`. You can invoke the following functions from the `Hermod.Tracing.Consistency` module. They return a list of `Text` warnings; an empty list indicates that everything is in order.

```haskell
-- | Check the configuration source against all registered namespaces.
-- An empty return list means everything is well.
checkTraceConfiguration ::
     ConfigSource          -- configuration source (file, bytes, or JSON object)
  -> TraceConfig           -- default config (used as fallback)
  -> [([Text], [Text])]    -- all namespaces as (prefix, inner) pairs
  -> IO NSWarnings

-- | Pure variant: check an already-loaded TraceConfig.
checkTraceConfiguration' ::
     TraceConfig
  -> [([Text], [Text])]
  -> NSWarnings
```

An example warning is "Config namespace error: i.am.an.invalid.namespace".

It is recommended to run these checks as part of the application's test suite to catch misconfigured namespaces before deployment.

The consistency checks cover the following aspects:

- Every namespace in `all namespaces` must be unique.

- Each namespace is a terminal and is not a part of another namespace.

- Namespaces in the `severityFor`, `privacyFor`, `detailsFor`, `documentFor`, and `metricsDocFor` functions are consistent with the `allNamespaces` definition.

- Any namespace in the configuration must be found by a hierarchical lookup in `all namespaces`.

If the checker encounters any problems it emits a `TracerConsistencyWarnings` message through the
`Hermod.Tracing.HermodTracingMessage` type. The message is routed via the `Reflection` namespace
and carries `Warning` severity so that misconfigured namespaces are surfaced prominently in both the
logs and forwarded tracing output.

## Trace Backends Overview

As mentioned earlier, trace backends serve as the final destinations for all traces once they have undergone trace interpretation, resulting in metrics and messages. The system defines three trace backends:

1. __Standard Tracer:__ This is the fundamental standard output tracer. Notably, it can accept both regular and confidential traces.

    ```haskell
    standardTracer :: forall m. (MonadIO m)
      => m (Trace m FormattedMessage)
    ```

2. __Trace-Forward Tracer:__ This is a network-only sink dedicated to forwarding messages using typed protocols over TCP or local sockets. It exclusively handles public traces.

    ```haskell
    forwardTracer :: forall m. (MonadIO m)
      => ForwardSink TraceObject
      -> Trace m FormattedMessage
    ```

3. __EKG Tracer:__ This tracer submits metrics to a local EKG store (which then can be exposed directly via the `PrometheusSimple` backend and/or forwarded).

    ```haskell
    ekgTracer :: MonadIO m
      => Metrics.Store
      -> m (Trace m FormattedMessage)
    ```

It's imperative to note that constructing more than one instance of each tracer in an application should absolutely be avoided, as it may result in unexpected behaviour.

## Data Points Overview and Deprecation Notice

`DataPoint`s provide a means for external processes to inquire about the host application's runtime state. Essentially similar to metrics, `DataPoint`s, however, have an Algebraic Data Type (ADT) structure, allowing them to represent structured information beyond simple metrics. This feature enables external processes to query and access specific details of a running application, such as its basic runtime information.

Implemented as special tracers, `DataPoint`s package objects into `DataPoint` constructors and necessitate a `ToJSON` instance for these objects. The set of `DataPoint`s follows the same namespace structure as metrics and log messages. While `DataPoint`s operate independently of tracing, they are stored locally, facilitating on-demand queries for the latest values of a specific `DataPoint`.

Note: `DataPoint` support is tied to the current version of the forwarding protocol. Future versions of the protocol may not carry `DataPoint`s. For a future-proof approach to exposing application state, host applications should consider alternatives such as a gRPC interface.

```haskell
-- A simple dataPointTracer supporting the construction of a namespace.
mkDataPointTracer :: forall dp. (ToJSON dp, MetaTrace dp, NFData dp)
  => Trace IO DataPoint
  -> IO (Trace IO dp)
```

# Appendix

## References

- [hermod-tracing on GitHub](https://github.com/IntersectMBO/hermod-tracing) — source repository and issue tracker
- [contra-tracer](https://hackage.haskell.org/package/contra-tracer) — the contravariant tracing primitive that `hermod-tracing-core` builds upon

## Future work

### Versioning

Versioning for trace messages stands as a crucial component that significantly contributes to the functionality and maintainability of our system. We acknowledge the importance of associating version numbers with log messages, ensuring transparency and consistency throughout the application lifecycle.

Adhering to a change protocol and establishing a clear correlation between application version numbers and trace version numbers is a prudent strategy. This approach aids in the effective management and communication of updates, alterations, and improvements to our tracing system. Such alignment guarantees that any modifications to the tracing system are accurately reflected and comprehended by both the development team and the broader developer community.

Anticipating the forthcoming development phase, we are eager to design and implement this versioning feature. Our goal is to seamlessly integrate it into our overall system architecture, bolstering our capacity to adapt and evolve. This ensures a clear, consistent, and structured approach to trace messages, enhancing our system's resilience and comprehensibility.

### Trace Consumers

A future direction for Hermod's trace and metrics forwarding capability is a subscription-based trace consumer model. This approach would allow consumer processes to register with a trace acceptor service and selectively receive messages based on their subscriptions, providing a more efficient and targeted alternative to the current `DataPoint` pull model.

`DataPoint` support may not be carried forward into the next version of the forwarding protocol. In the meantime, host applications that require robust, future-proof state exposure should consider complementary mechanisms such as a gRPC interface.
