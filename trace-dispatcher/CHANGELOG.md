# Revision history for trace-dispatcher

## 2.12.1 -- Apr 2026

* Add `docuResultsToNamespaces` to `DocuGenerator` to support JSON schema generation.
* Add `PrometheusSimpleRun` data type and field `TraceConfig.tcPrometheusSimpleRun`. This exposes some of the DoS protection parameters of the `PrometheusSimple` backend.
* The above parameters can be set via the top-level config key `"TracePrometheusSimpleRun": {...}`. Those values will _selectively override_ the hardcoded ones from `defaultRunParams`.
* Add `Cardano.Logging.Prometheus.TCPServer.runPrometheusSimpleWith` to run the backend providing a custom `PrometheusSimpleRun` value.
* Generelly relax some of the DoS protection default values.
* Fix `emptyTraceConfig` to be actually empty.
* Implement the basics for the future way of providing configuration via the top-level config key `"HermodTracing"`.
* This config key can reference an external file, or provide an object cleanly encapsulating _all_ of Hermod's options. The option names are shortened wrt. the current top-level names.
* Support `!include` extension for YAML config files.
* The namespace root in `"TraceOptions": { "": {...}}` can now be aliased as '\_root\_': `"TraceOptions": { "_root_": {...}}`. This facilitates automations that have to treat an empty JSON string as special case.
* Add `readConfigurationWithFallback` and `readConfigurationWithFallbackAndDefault` to `Cardano.Logging.ConfigurationParser`, adding fallback values to the namespace root. These will apply iff no such value was given in the file or default config, and guard against accidentally missing trace output.
* In the same module, `readConfiguration` and `readConfigurationWithDefault` will now guarantee fallback values: `Notice` severity, `DNormal` detail level and `Stdout MachineFormat` JSON logging.

## 2.12.0 -- Mar 2026

* Increase robustness of evaluating trace messages, metrics and datapoints

## 2.11.1 -- Feb 2026

* Add strict `contramap'` (infix alias `>!$!<`) to the API, capturing a common pattern to avoid unintentional space leaks when composing tracers
* Increase `PrometheusSimple` robustness by restarting the backend upon crash, adding start/stop traces and more eagerly reaping of dangling sockets
* Setting the `TRACE_DISPATCHER_LOGGING_HOSTNAME` environment variable will override the system hostname in trace messages.
* Increased strictness when storing traced `DataPoints`
* Drastically reduced fallback value for forwarding queue capacity to minimize impact of forwarding service interruption on heap size and retention
* Removed `TraceConfig.tcPeerFrequency` and hence `TraceOptionPeerFrequency` from config representation
* Removed unused module `Cardano.Logging.Types.NodePeers`

## 2.11.0 -- Nov 2025

* `class LogFormatting`: remove redundant `forHumanFromMachine` and `forHumanOrMachine` (the system already does that inherently)
* Introduce type `Cardano.Logging.Types.TraceMessage.TraceMessage` with explicit codecs for JSON and CBOR
* Rework `PreFormatted` type and formatters to use `TraceMessage`; slightly optimize `humanFormatter'`
* Add CBOR formatting via `FormattedMessage.FormattedCBOR` constructor and a `cborFormatter'` function
* Replaced both `disconnectedQueueSize` and `connectedQueueSize` with `queueSize` in `TraceOptionForwarder` while keeping config parsing backwards compatible
* Add retry delay reset in `runInLoop` when the action runs sufficiently long
* Safely stop `standardTracer`'s stdout thread when there are no more producers

## 2.10.0 -- July, 2025

* Forwarding protocol supports connections over TCP socket, in addition to Unix domain sockets.
* Failure to initialise the `PrometheusSimple` backend is now lenient - i.e., won't result in an exception being propagated.
* `trace-forward` now depends on `trace-dispatcher`, and not the other way round.
* Improves the structure and metadata of generated tracer documentation.
* Drop unnecessary dependency on `io-classes`.

## 2.9.2 -- May 2025

* New config field `traceOptionLedgerMetricsFrequency`.

## 2.9.1 -- Apr 2025

* Removed `cardano-node' as a dependency from`cardano-tracer'. This necessitated moving `NodeInfo`
  (from `cardano-tracer:Cardano.Node.Startup` to `trace-dispatcher:Cardano.Logging.Types.NodeInfo`), `NodePeers`
  (from `cardano-node:Cardano.Node.Tracing.Peers` to `trace-dispatcher:Cardano.Logging.Types.NodePeers`), and
  `NodeStartupInfo` (from `cardano-tracer:Cardano.Node.Startup` to `cardano-node:Cardano.Node.Tracing.NodeStartupInfo.hs`).

## 2.9 -- Mar 2025

* New `PrometheusSimple` backend which runs a simple TCP server for direct exposition of metrics, without forwarding.
* New `maxReconnectDelay` config option in `TraceOptionForwarder`: Specifies maximum delay (seconds) between (re-)connection attempts of a forwarder (default: 60s).
* Introduce `forHumanFromMachine :: a -> Text` into `class LogFormatting a` as a safe drop-in `forMachine` definition in instances.
* Optimize data sharing in formatters.
* Remove unused optional namespace prefix argument from formatters.
* Updated to use `ekg-forward-0.9`.
* Remove `ekg-wai` from dependencies.

## 2.8.1 -- Feb 2025

* Updated to `ouroboros-network-framework-0.16`

## 2.8.0 -- Jan 2025

* Change dependency `ekg` to `ekg-wai`, replacing `snap-server` based web stack with `warp / wai`.
* Add `initForwardingDelayed` which allows for deferred start of forwarding after initialization, instead of tying both together.

## 2.7.0 -- Sep 2024

* Add `docuResultsToMetricsHelptext` for JSON output of metrics docs; required
  by `cardano-node` command `trace-documentation --output-metric-help`

## 2.6.0

* With a metrics prefix that can be set in the configuration (tcMetricsPrefix)
  Metrics gets a type postfix (_int,_real, _counter)

## 2.5.7

* With a prometheus metric with key label pairs. The value will always be "1"

## 2.5.2 -- Dec 2023

* ForHuman Color, Increased Consistency Checks, and Non-empty Inner Workspace Validation

## 2.5.1 -- Dec 2023

* Rewrite of examples as unit tests

## 2.4.1 -- Nov 2023

* Updated to `ouroboros-network-0.10`

## 2.1.0 -- Sep 2023

* Updated to `ouroboros-network-0.9.1.0`

## 2.0.0 -- May 2023

* First version that diverges from cardano-node versioning scheme

* GHC-9.2 support

* Many undocumented changes

## 1.35.4 -- November 2022

* Undocumented changes

## 1.29.0 -- September 2021

* Initial version.
