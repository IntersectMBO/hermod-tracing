# Memory footprint of `Emitting` arms in `contra-tracer 0.2`

## What is measured

`contra-tracer 0.2`'s `Emitting` constructor holds two `Kleisli` closures: `emitK` (the active logging pipeline) and `noEmitK` (the suppression path). Both are retained as GC roots regardless of whether the tracer is active. This report quantifies the heap retained by each arm as a function of the number of composed sub-tracers `n`.

## Methodology

`delta-live-inspect` builds a tracer that is the left-associative `(<>)` composition of `n` independently configured `Trace IO DemoMsg` tracers (each backed by a stdout backend, severity `Debug`). `foldl1 (<>)` is used deliberately to avoid touching `mempty = Squelching`, which would add spurious `(***)` wrappers to `noEmitK`.

The retained size of each arm is measured with the hold/release technique:

```
size = liveBytes(with closure held) − liveBytes(after closure released)
```

A major GC is forced before each sample. The difference cancels background residue and CAF noise. `evaluate` is used to keep the closure alive as a GC root during measurement without GHC optimising the reference away.

## Results

```
n     emit (bytes)    no-emit (bytes)
1     3,496           < noise floor
2     8,184           < noise floor
4     17,560          < noise floor
8     36,312          40
16    73,816          1,192
32    148,824         3,496
64    298,840         8,104
```

## Linear fit

Both arms are strictly linear in `n`:

| Arm | Bytes per tracer | Formula |
|---|---|---|
| `emitK` | **4,688** | `4688n − 1192` |
| `noEmitK` | **144** | `144n − 1112` |

The fits are exact across all measurable data points (residual = 0).

## Interpretation

`noEmitK` for a composed tracer is structurally `arr (const ()) . (lp₁ *** lp₂ *** … *** lpₙ)`. Each composition level adds one `(***)` closure (~48 bytes) plus the individual `lpᵢ` captures, totalling 144 bytes per level. The `emitK` arm carries the full logging pipeline — formatters, routing, backend handles — at ~4,688 bytes per sub-tracer.

At `n = 64`, `noEmitK` consumes 8,104 bytes versus `emitK`'s 298,840 bytes: **2.7% of the emit footprint**. For realistic node configurations (`n` in single digits), `noEmitK` is below the measurement noise floor (< ~1 KB total), making it negligible in practice.

## Conclusion

The `noEmitK` arm is not a memory concern. The `emitK` arm dominates at ~4.6 KB per composed sub-tracer and is the only arm worth optimising if heap reduction is required.
