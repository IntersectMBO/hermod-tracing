Re(altime) Con(formance) Framework Overview
==========================

This document describes a version of linear temporal logic suitable for realtime conformance
checking of systems that emit structured trace messages. The framework is built to ingest Hermod
trace records as defined in `Hermod.Tracing.Types.TraceMessage`, and is general-purpose: any
application that produces a stream of typed, metadata-rich trace records can be targeted.

The worked examples in section 6 use a Cardano blockchain node as a concrete, real-world
illustration — its forging pipeline provides richly structured, temporally ordered events that
make for clear and non-trivial LTL propositions. Readers unfamiliar with Cardano can treat
the namespace strings and field names as opaque identifiers and still follow the logical structure.

1. Temporal Vocabulary
----------------------
- The logic offers implication, conjunction/disjunction, and negation, plus a small family of temporal constructs: unbounded universal and bounded existential quantifiers over trace suffixes, “next” operator and a bounded “until”. Integer-valued properties within atomic predicates support **Presburger arithmetic** — linear integer arithmetic with equality, ordering, and quantifiers over ℤ, decided via Cooper's quantifier-elimination procedure.
- Atomic formulas represent predicates over properties of individual trace records.

2. Atomic Predicates & Trace Records
------------------------------------
- Each trace record should be normalised into a canonical structure that exposes standard metadata: namespace (e.g., `["Forge","Loop","ForgedBlock"]`), severity, host, thread id, plus an extensible map of domain-specific fields (in the Cardano example: slot number, block number, block hash, failure reason, ledger point, etc.).
- Atomic predicates state facts about that structured record: “namespace equals Forge.ForgedBlock”, “slot equals 423115”, “reason belongs to {BlockFromFuture, SlotIsImmutable}”, “severity is at least Warning”, “field `prev` matches a given block hash pattern”.

3. Trace Model
--------------
- A trace is a finite sequence of the normalised records, ordered by timestamp. Timestamps are not exposed to atomic formulas but instead are handled by the temporal fragment of the logic.

4. Formula Progression
----------------------
- Each event advances the current formula obligation through a single step: temporal operators are unfolded (`☐ ᪲ₖ φ` expands to `φ ∧ ◯(◯ᵏ(☐ ᪲ₖ φ))`), atoms are evaluated against the current event (`⊤` on a type and property match, `⊥` on a type mismatch), and `◯ φ` reduces to `φ` after consuming the time unit.
- The result is a new formula encoding exactly what must hold for the remaining trace suffix. This is purely a satisfiability-based transformation: no automaton is constructed up-front.

5. Simplification & Verdicts
----------------------------
- After each progression step two rewrite passes run in sequence: first, `rewriteHomogeneous` extracts any temporally-pure subformula (containing no temporal operators or atoms) and evaluates it via Presburger or finite-domain arithmetic, replacing it with `⊤` or `⊥`; then `rewriteIdentity` folds standard logical identities (`φ ∧ ⊤ = φ`, `¬¬φ = φ`, constant comparison folding, etc.).
- If at any step the formula reduces to `⊤` the property is immediately satisfied; if it reduces to `⊥` it has immediately failed, enabling early exit in both cases.
- After the trace is exhausted, the residual formula is evaluated by `terminate`: bounded universal obligations (`☐ⁿ`) become `⊤`, bounded existential obligations (`♢ⁿ`) become `⊥`, and any remaining unmatched atoms become `⊥`.

6. Worked Examples
------------------
The following invariants are drawn from the Cardano forging pipeline (some Cardano familiarity assumed). `k`, `m` denote window sizes chosen large enough to accommodate intermediate bookkeeping events between the paired messages.

1. **Leadership outcome within a window**
   `☐ ᪲ (∀i ∈ ℤ. Forge.Loop.StartLeadershipCheck{slot = i} ⇒ ♢ᵏ (Forge.Loop.NodeIsLeader{slot = i} ∨ Forge.Loop.NodeNotLeader{slot = i}))`
   Every leadership-check event must be resolved by an outcome within `k` steps.

2. **Forge adoption chain**
   `☐ ᪲ (∀i ∈ ℤ. Forge.Loop.ForgedBlock{slot = i} ⇒ ♢ᵏ (Forge.Loop.AdoptedBlock{slot = i} ∨ Forge.Loop.DidntAdoptBlock{slot = i} ∨ Forge.Loop.ForgedInvalidBlock{slot = i}))`
   Every forged block must be followed by an adoption verdict within `k` steps.

3. **Failure diagnostics lead to cannot-forge**
   `☐ ᪲ ((Forge.Loop.SlotIsImmutable{} ∨ Forge.Loop.BlockFromFuture{} ∨ Forge.Loop.NoLedgerState{} ∨ Forge.Loop.NoLedgerView{} ∨ Forge.Loop.ForgeStateUpdateError{}) ⇒ ♢ᵏ Forge.Loop.NodeCannotForge{})`
   Every recorded failure reason must trigger the explicit `NodeCannotForge` event, preventing silent drops.

4. **Ledger ticking and mempool snapshot sequence**
   `☐ ᪲ (∀i ∈ ℤ. Forge.Loop.NodeIsLeader{slot = i} ⇒ ♢ᵏ Forge.Loop.ForgeTickedLedgerState{slot = i})`
   `☐ ᪲ (∀i ∈ ℤ. Forge.Loop.ForgeTickedLedgerState{slot = i} ⇒ ♢ᵏ Forge.Loop.ForgingMempoolSnapshot{slot = i})`
   `☐ ᪲ (∀i ∈ ℤ. Forge.Loop.ForgingMempoolSnapshot{slot = i} ⇒ ♢ᵏ Forge.Loop.ForgedBlock{slot = i})`
   The per-slot forging pipeline must proceed in the documented order; slot quantification ensures each chain is tracked independently.

5. **Consensus flow edges**
   `☐ ᪲ (Forge.Loop.BlockContext{} ⇒ ♢ᵏ (Forge.Loop.LedgerState{} ∨ Forge.Loop.NoLedgerState{}))`
   `☐ ᪲ (Forge.Loop.LedgerState{} ⇒ ♢ᵏ (Forge.Loop.LedgerView{} ∨ Forge.Loop.NoLedgerView{}))`
   `☐ ᪲ (Forge.Loop.LedgerView{} ⇒ ♢ᵏ (Forge.Loop.ForgeStateUpdateError{} ∨ Forge.Loop.NodeCannotForge{} ∨ Forge.Loop.NodeNotLeader{} ∨ Forge.Loop.NodeIsLeader{}))`
   Encodes each edge in the forging diagram so that missing or reordered messages are caught immediately.

6. **Immutable or future tip aborts the slot**
   `☐ ᪲ ((Forge.Loop.SlotIsImmutable{} ∨ Forge.Loop.BlockFromFuture{}) ⇒ ♢ᵏ Forge.Loop.NodeNotLeader{})`
   The node must record that it will not lead the slot whenever the tip inhabits the same or a future slot.

7. **Adoption thread crashes bubble up**
   `☐ ᪲ (Forge.Loop.AdoptionThreadDied{} ⇒ ♢ᵏ Forge.Loop.NodeCannotForge{})`
   If the adoption worker dies, an explicit `NodeCannotForge` must follow so operators see the failure instead of a quiet stall.

8. **Invalid forge triggers a fresh leadership cycle**
   `☐ ᪲ (∀i ∈ ℤ. ∀h ∈ Text. Forge.Loop.ForgedInvalidBlock{slot = i, hash = h} ⇒ ♢ᵏ (Forge.Loop.NodeCannotForge{slot = i} ∧ ♢ᵐ Forge.Loop.StartLeadershipCheck{slot = i + 1}))`
   Forging an invalid block must halt forging for that slot and restart the pipeline for the successor slot.

9. **Ledger anchor consistency**
   `☐ ᪲ (∀i ∈ ℤ. ∀p ∈ Text. Forge.Loop.LedgerState{slot = i, point = p} ⇒ ♢ᵏ Forge.Loop.ForgeTickedLedgerState{slot = i, point = p})`
   Comparing the `point` field across both events ensures the ticker processes exactly the ledger snapshot that was previously fetched.
