# hermod-bench-app

A chatty application for benchmarking Hermod at application level. It sits
between the criterion microbenchmarks of `hermod-tracing-core` and a system
benchmark of a real application: tracing runs in its natural surroundings
(many tracers and namespaces, configured stages, real backends, a live heap
the GC has to copy, several threads), while the share of filtered messages and
the amount of real work are parameters. Not published.

## What it does

Ten characters from Naruto, Sailor Moon, Spirited Away, Dragon Ball and
Attack on Titan are the application's subsystems. Each has its own event type
and five to eight namespaces, 2 to 4 names deep, such as
`Goku.Training.PowerLevel.Measured`, `Eren.ODM.Gear.Gas.Consumed` or
`Chihiro.Bathhouse.Chore.Started`; some events carry metrics. The tracers are
built and configured as cardano-node builds its tracers (`mkDispatchTracers`):

- one `mkHermodTracer` per subsystem, with stdout and EKG backends (no
  forwarding: it is downstream of what this app measures);
- application-facing tracers composed with `<>` through the
  `contra-tracer`-compatible facade (`Hermod.Tracing.API.Tracer`), as the
  node's `chainDBTracer`, `startupTracer` and `nodeStateTracer` do;
- the tracer information and effective configuration traced at startup.

Worker threads repeat: some pure, non-allocating work; trace a number of
events drawn from a seeded generator (the same sequence in every variant);
now and then replace part of the live heap. Event fields are lazy, so a
filtered message's fields are never evaluated.

Trace output goes to stdout. At the end, one JSON line with the run's RTS
statistics goes to stderr: CPU (mutator, GC), wall time, allocated and copied
bytes, GC counts, and the numbers of messages traced and emitted.

## Configurations

`config/` holds four configurations, from least to most emitted:

| Config | Like | Emitted |
|---|---|---|
| `silent.yaml` | everything silenced | none |
| `quiet.yaml` | a mainnet node: `Notice` and above | ~2% |
| `mixed.yaml` | node's benchmark configuration: chatty and quiet subsystems, silenced subtrees, a frequency limiter | ~20% |
| `verbose.yaml` | everything at `Debug` | all |

## Running it

```
cabal run hermod-bench-app -- --config examples/hermod-bench-app/config/quiet.yaml \
  --iterations 100000 > /dev/null
```

Options (`--help`): `--config FILE`, or `--no-tracing` for the baseline
without tracing (all tracers `nullTracer`, no backends); `--threads`, `--iterations N` (fixed work per worker) or
`--rate MSG/S --duration SECONDS` (fixed rate), `--messages` per iteration,
`--work` per iteration, `--live-heap` in MB, `--churn-every`, `--seed`. The
RTS options built in are `-T` (needed) and `-N2`, the least concurrency
that exercises the multi-threaded paths; everything else is GHC's default.
Options after `+RTS` come later and take precedence, e.g. cardano-node's
`+RTS -I0 -A16m -qg1 -qb1 -N2 --disable-delayed-os-memory-return`.

Fixed work is the mode for comparisons: every variant does the same work and
traces the same messages, and the RTS counts allocation exactly. Fixed rate
answers what tracing costs at a given message rate, in CPU and MiB/s.

## Comparing builds

Two tools split the job. `build.sh` builds the app against revisions of this
repository: it checks each one out in a git worktree under `dist-newstyle/`,
adds this checkout's app through `cabal.project.local` where the revision
doesn't contain it, checks the binary's built-in RTS options against the
cabal file (a changed `-with-rtsopts` alone doesn't relink), and prints one
`--bin=REF=PATH` line per revision. `hermod-bench-compare` runs any builds
interleaved, in alternating order, and prints mean ± standard error per
metric and the difference against the first:

```
cabal build exe:hermod-bench-compare
$(cabal list-bin exe:hermod-bench-compare) \
  $(examples/hermod-bench-app/build.sh master mkarg/opt-trace-filtering) \
  --rounds 5 --config quiet --config mixed -- --iterations 100000
```

Step by step, from the repository root, the same comparison reads:

```
# 1. Build the app against each revision. build.sh prints one line per
#    revision, e.g.
#      --bin=master=/…/bench-app-worktrees/master/…/hermod-bench-app
#    which is exactly the option hermod-bench-compare expects.
examples/hermod-bench-app/build.sh master mkarg/opt-trace-filtering

# 2. Build the compare tool; `cabal list-bin` prints the path of its binary.
cabal build exe:hermod-bench-compare
cabal list-bin exe:hermod-bench-compare

# 3. Run it with those --bin options, and the app's arguments after `--`.
/…/hermod-bench-compare --bin=master=/… --bin=mkarg/opt-trace-filtering=/… \
  --rounds 5 --config quiet -- --iterations 100000
```

The one-liner above does all three at once: the shell replaces `$(command)`
with what the command prints, so `$(cabal list-bin …)` becomes the compare
tool's path and `$(…/build.sh …)` becomes the `--bin` options. This works in
bash, zsh and fish alike. To keep the builds for several runs, store them
in a variable, e.g. in bash or zsh `bins=$(examples/hermod-bench-app/build.sh
master HEAD)`, and pass `$bins` (zsh: `${=bins}`) in place of the `$(…)`.

The builds can come from anywhere, e.g. one revision under two GHC versions:
`--bin NAME=PATH` names each. Each binary's GHC version and built-in RTS
options are read from `+RTS --info`; `--rts` adds options to every run, and
`--out FILE` writes all summaries as JSON lines, each with its binary's
name, path, GHC version and RTS options, and the round.

The configuration `none`, the baseline without tracing, always runs (it is
added if not given). Against it, each configuration's table ends with
tracing's own CPU per message (above the same binary's baseline) and its
share of the CPU. A sweep over the amount of work is a loop around the tool:

```
bins=$(examples/hermod-bench-app/build.sh master mkarg/opt-trace-filtering)
for w in 2000 20000 200000; do
  $(cabal list-bin exe:hermod-bench-compare) $bins --rounds 3 \
    --config silent --config quiet --config mixed -- --work $w --iterations 20000
done
```

(in zsh, `${=bins}` in place of `$bins`). The per-message figures are
totals divided by the number of traced messages, so they include each
message's share of the work; compare them between variants, not with the
microbenchmarks.

The stdout backend renders in its own thread from a bounded queue: at the
end of a run, up to 2048 messages may still be queued, and their rendering is
not counted.
