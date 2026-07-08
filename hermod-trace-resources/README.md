# hermod-trace-resources

OS-level and RTS resource sampling for the
[Hermod tracing system](https://github.com/IntersectMBO/hermod-tracing).

## What it does

`hermod-trace-resources` exposes a single IO action:

```haskell
readResourceStats :: IO (Maybe ResourceStats)
```

Call it once per sampling interval to get a snapshot of the current process's
resource usage. The returned `ResourceStats` value carries `LogFormatting` and
`MetaTrace` instances from `hermod-tracing`, so it can be fed directly into any
`Trace IO ResourceStats`.

## Platform support

| Platform | CPU & GC | Memory (RSS) | Block I/O | Network I/O | Threads |
|----------|----------|--------------|-----------|-------------|---------|
| Linux    | ✓        | ✓            | ✓         | ✓ (opt-in)  | ✓       |
| macOS    | ✓        | ✓            | —         | —           | ✓       |
| Windows  | ✓        | ✓            | ✓         | —           | ✓       |
| Other    | ✓ (RTS only) | —        | —         | —           | ✓       |

Fields not supported on a given platform are reported as `0`.

## Quick start

```haskell
import Hermod.Tracing.Resources

sample :: IO ()
sample = do
  mStats <- readResourceStats
  case mStats of
    Nothing    -> putStrLn "resource sampling unavailable"
    Just stats -> print stats
```

## Measured quantities

| Field         | Unit            | Source                              |
|---------------|-----------------|-------------------------------------|
| `rCentiCpu`   | centiseconds    | `/proc/self/stat` (Linux), OS APIs  |
| `rCentiGC`    | centiseconds    | GHC RTS stats                       |
| `rCentiMut`   | centiseconds    | GHC RTS stats                       |
| `rGcsMajor`   | count           | GHC RTS stats                       |
| `rGcsMinor`   | count           | GHC RTS stats                       |
| `rAlloc`      | bytes           | GHC RTS stats (cumulative)          |
| `rLive`       | bytes           | GHC RTS stats (after last GC)       |
| `rHeap`       | bytes           | GHC RTS stats (committed)           |
| `rRSS`        | bytes           | OS kernel (resident set size)       |
| `rCentiBlkIO` | centiseconds    | `/proc/self/stat` (Linux only)      |
| `rNetRd`      | bytes           | `/proc/self/net/netstat` (Linux, see below) |
| `rNetWr`      | bytes           | `/proc/self/net/netstat` (Linux, see below) |
| `rFsRd`       | bytes           | `/proc/self/io` (Linux), OS APIs    |
| `rFsWr`       | bytes           | `/proc/self/io` (Linux), OS APIs    |
| `rThreads`    | count           | GHC RTS stats (live green threads)  |

## Cabal flag: `with-netstat`

Network I/O on Linux is read from `/proc/self/net/netstat`, which is a system-wide
counter file — the values represent all IP traffic on the host, not just this process.
Because parsing this file on every sample has a non-trivial cost, it is disabled by
default.

Enable it with:

```
cabal build -f with-netstat
```

or in your `cabal.project`:

```
package hermod-trace-resources
  flags: +with-netstat
```

## Integration with hermod-tracing

`ResourceStats` implements both `LogFormatting` (human-readable text, structured
JSON and system metrics) and `MetaTrace` (namespace, severity, metric documentation). Wire it up like
any other traced value:

```haskell
configReflection <- emptyConfigReflection
!tr <- mkHermodTracer myStdoutTracer mempty Nothing ["Resources"] -- No trace forwarding or metrics in this example
configureTracers configReflection myTraceConfig [tr]
forever $ do
  threadDelay 5_000_000  -- 5 s
  readResourceStats >>= mapM_ (traceWith tr)
```
