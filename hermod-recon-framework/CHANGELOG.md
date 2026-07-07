# Revision history for hermod-recon-framework

## NEXT

* Replace `trace-dispatcher` dependency with `hermod-tracing-core`.
* Update all `Cardano.Logging.*` imports to `Hermod.Tracing.*`.
* Rename CLI flag `--trace-dispatcher-cfg` to `--hermod-tracing-cfg`.

## 1.4.0 -- June 2026

* All Unicode operators in the formula parsers now have ASCII spellings accepted
  as alternatives (e.g. `\globally`, `\forall`, `&&`, `=>`, `<=`).
* Numeric indices on temporal operators can be written as a parenthesised decimal
  immediately after the operator token (e.g. `\globallyN(2)`, `\finallyN(300)`).

## 1.3.0 -- June 2026

* Rename module namespace from `Cardano.ReCon.*` to `Hermod.ReCon.*`.
* Rename executables: `cardano-recon` → `hermod-recon`, `cardano-recon-grep` → `hermod-recon-grep`.

## 1.2.1 -- May 2026

* Replace positional `FILE` and `FILES` arguments in `cardano-recon` with named `--formulas` and `--traces` options.

## 1.2.0 -- May 2026

* Add `ContinuousFormula` — the temporal-operator-free fragment of `Formula`, with `retract` for
  converting a `Formula` and `eval` for deciding it against a single event.
* Add `cardano-recon-grep` executable — filters a JSON array of `TraceMessage`s by a list of
  continuous formulas, emitting only the messages that satisfy all of them.
* Add `--grep` flag to `cardano-recon` — on a negative formula outcome prints only the JSON array
  of relevant events to stdout (bypassing trace-dispatcher); prints nothing on a positive outcome.
* Replace the raw context printout with a `ContextDump` trace message at `Debug` severity.

## 1.1.1 -- April 2026
* Support atoms that refer to property keys at arbitrary depth
* Replace the `crash-on-missing-key` build flag with a runtime CLI option `--on-missing-key <crash|bottom>` (default: `bottom`)

## 1.1.0 -- April 2026

* Support configurable timeunits in formulas via a CLI option.
* Support existential quantification over properties (both finite and infinite domain)
* Support Presburger arithmetic (over ℤ)

## 1.0.0 -- Feb 2026

* First version.
