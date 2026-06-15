# Evolution — compiler-variable-text

**Status**: COMPLETE (GA) — deterministic variable-text lowering (matrix rows 25–27) and the `not` unary operator shipped and play oracle-identical. The full `TheIntercept.ink` native-compile e2e and a dotted read-count RED test remain genuinely `.disabled`, descoped (user-approved) to the `native-ink-compiler` feature as an explicit follow-up.
**Date**: 2026-06-15
**Predecessor**: `docs/evolution/native-ink-compiler-evolution.md` (this feature closes that feature's documented compiler↔runtime parity gap)

This is the cross-feature retrospective archive for the `compiler-variable-text` feature — a variable-text lowering pass added to the already-delivered native compiler. The single most important durable lesson is captured in **"The Slice-04 Descope-Premise Falsification"** section below: an honest RED falsified the assumption that closing the variable-text rows would make the flagship fixture compile, and surfaced a whole weave-label addressing subsystem that belongs to `native-ink-compiler`.

---

## Feature Summary

This feature makes Ink's three **deterministic** variable-text forms compile natively (pure-Swift, in-process, no `inklecate`):

- **sequence** `{a|b|c}` — matrix row 25
- **cycle** `{&a|b}` — matrix row 26
- **once-only** `{!a|b}` / bare `{|x|}` — matrix row 27

All three move MUST-REJECT → MUST-COMPILE and play **oracle-identical** (line-for-line, choice-for-choice against the committed inklecate `.ink.json`). Shuffle `{~a|b}` (row 28) stays rejected — it additionally needs `RANDOM`, which is genuinely runtime-unsupported. The variable-text lowering required **zero runtime/engine changes** (KPI #4 holds): inklecate lowers these forms to a visit-count switch built from primitives the runtime already executes (`visit` + `du` + `MIN`/`%` + `==` + conditional diverts), so the compiler now lowers them the same way.

The feature also delivered, as a necessary enabler discovered mid-wave, the **`not` unary operator** in condition expressions (`not <operand>` → `.unary("!",…)` AST node → native postfix `!`).

### Components Shipped

All co-located under `Sources/SwiftInkRuntime/Compiler/` per **ADR-006**; lowering design per **ADR-010**.

| Component | Path | Role | Decision |
|---|---|---|---|
| `VariableTextEmitter` | `Codegen/VariableTextEmitter.swift` | Lowers sequence/cycle/once to the `#f:5` visit-switch; owns the `seq{N}-s{I}` / `seq{N}-end` named-container namespace | **CREATE NEW** |
| `ContentSegment.variableText` + `VariableTextMode` | `AST/CompilerAST.swift` | AST case `.variableText(mode:stages:)` + `VariableTextMode { sequence, cycle, once }`; `.unary` case | **EXTEND** |
| variable-text parse rule + `not`-prefix / paren grouping | `Parser/InkParser.swift`, `Parser/InkParserExpressions.swift` | Top-level `\|`-split, leading-marker → mode, `modeAndContent`; `not <operand>` and parenthesised grouping | **EXTEND** |
| `.variableText` + `.unary` dispatch | `Codegen/RuntimeObjectEmitter.swift` | `lowerBody` branch parallel to `.conditional`; `.unary` → native postfix `!` | **EXTEND** |
| `UnsupportedConstructDetector` | `Parser/UnsupportedConstructDetector.swift` | Reject set narrowed to **shuffle only** | **EXTEND** (gate) |

No `Package.swift` change, no new dependency, no new `NodeKind` case for variable text. The `not` operator added one AST case (`.unary`).

---

## The Lowering Design (ground truth — verified against inklecate)

All three forms lower to an anonymous dispatch container flagged `#f:5` (`Visits | CountStartOnly` → `visit` reports the 0-based own-entry read count: 0 on first play). The dispatch computes a stage index and conditionally diverts to one named stage container per stage; each stage `pop`s the duplicated index, emits its text (if any), then diverts to a shared `seq{N}-end` continuation. The forms differ **only** in three parameters:

| Form | OP | BOUND | append empty stage? | stages emitted |
|---|---|---|---|---|
| sequence `{a\|b\|c}` (S stages) | `MIN` | `S − 1` (last index) → **clamp** | no | S |
| cycle `{&a\|b}` (S stages) | `%` | `S` (stage count) → **wrap** via modulo | no | S |
| once-only `{!a\|b}` (S source stages) | `MIN` | `S` (new last index) → **blank** | **yes (1)** | S + 1 |
| bare `{\|x\|}` — a plain **sequence**; `\|`-split → `["", "x", ""]` | `MIN` | `S − 1` | no | S (= 3) |

So **once = sequence + one appended empty final stage**, and **bare `{|x|}` is not special**. An empty stage holds `pop` + divert and **no `^text`** node. One parametrized routine over `(op, bound, appendEmptyStage)` serves all three. `VariableTextEmitter` is a stateless `enum` with a **pure-function (return-only)** contract: `(...) -> [NodeKind]` registering containers into an `inout named` collector (aggregate-bounded, the same universe `ConditionalEmitter` honours), no I/O, no global side effect.

The named-container namespace is `seq{N}-*` (e.g. `seq0-s0`, `seq0-end`). OQ-3 (DESIGN open question) asked whether this could collide with the `cond{N}-*` namespace `ConditionalEmitter` uses when a body mixes both a variable-text form and a conditional. **Discharged in slice 02**: the two emitters use distinct ordinal prefixes (`seq` vs `cond`), so there is no key collision. The intentional `VariableTextEmitter`/`ConditionalEmitter` structural parallelism (mirrored `BranchLowerer`/`ExpressionLowerer` typealiases and `nextOrdinal`/`key`/`path` style) is a copied template, not shared code — and the L1–L6 refactor pass deliberately left it as-is.

---

## The `not` Unary Operator (step 05-01)

Delivered as a **necessary enabler discovered by slice-04's honest RED**, not as planned variable-text scope. `not <operand>` in a condition was previously unparseable; the flagship fixture uses it. The addition:

- `InkParserExpressions` — a `not`-prefix rule plus parenthesised grouping in the Pratt expression parser.
- `CompilerAST` — a new `.unary(op:operand:)` case.
- `RuntimeObjectEmitter` — `.unary("!", …)` lowers to the runtime's native postfix `!` (matrix row 21 already lists `!` as an arithmetic/logic operator the runtime executes).

This is a clean, additive expression-parser extension; it is variable-text-adjacent only in that slice-04's RED is what surfaced it.

---

## The Slice-04 Descope-Premise Falsification (the durable lesson)

**This is the most important record in this archive.**

Slice 04 set out to re-enable the full `TheIntercept.ink` native-compile end-to-end oracle test. That test had been descoped on 2026-06-14 on the **stated belief** that its line-86 once-only variable-text form `{|I rattle my fingers on the field table.|}` was the **SOLE** blocker to native-compiling the flagship fixture (see the parity-gap note in `native-ink-compiler-evolution.md`).

Slice 04 began with an **honest RED-first** (commit `9be123b`): re-enable the e2e and let it fail truthfully. That RED **FALSIFIED the premise**. With all three variable-text forms lowered (slices 01–03 green), `TheIntercept.ink` *still* did not native-compile — two further compiler gaps, **unrelated to variable text**, also block the full fixture:

1. **`not` unary operator** — the fixture uses `not` in a condition. *Resolved here* as step 05-01.
2. **Dotted read-count addressing of named weave labels** — e.g. `{harris_demands_component.cant_talk_right: …}`, which must lower to a `CNT?` node addressing a *named weave label*. The step 06-01 investigation (commit `aa72e14`, RED-pinned with a `SCOPE-GUARD` stop) found the dotted subject is rejected at parse time and that closing it needs a **whole weave-label addressing subsystem**, not a point fix:
   - choice `(label)` parsing **and** `{condition}` parsing on choices,
   - **label-keyed** choice containers,
   - **count-visits** flagging on those containers,
   - a **name → path resolution table** so a dotted read-count reference resolves to the labelled container's path.

   This is squarely a `native-ink-compiler` (weave subsystem) concern, **not** a variable-text concern.

### User decision (2026-06-15)

**DESCOPE gap #2 to the `native-ink-compiler` feature and finalize `compiler-variable-text` now.** What ships in this GA:

- variable-text lowering (slices 01–03) — sequence/cycle/once, oracle-identical;
- the `not` unary operator (step 05-01).

What remains **genuinely `.disabled`** (failing, honestly documented) as the explicit `native-ink-compiler` follow-up:

- the `TheIntercept.ink` full native-compile e2e oracle test;
- the dotted read-count RED test (step 06-01).

The project's **"zero `.disabled` ATs at finalize" invariant is consciously WAIVED** for exactly these two user-approved descoped ATs. They are not weakened or deleted — they remain in the suite, `.disabled` with a reason naming the `native-ink-compiler` weave-label follow-up, so the gap is visible and tripwired for the next feature.

### Why this lesson matters

- **A descope rationale is a claim, and claims about corpora must be checked against the corpus, not the prose.** The "line 86 is the sole blocker" belief was plausible and written down — and wrong. An always-happy re-enable would have hidden the two extra gaps; the honest RED is what flushed them out. This is the same lesson the predecessor feature learned ("brief claims are not ground truth") recurring one layer deeper.
- **Honest RED + a SCOPE-GUARD stop is the correct response to discovering hidden scope.** Step 06-01 did not attempt to build a weave subsystem inside a variable-text slice; it pinned the failure with a RED test, named exactly what the follow-up needs, and stopped. That converts an unbounded surprise into a bounded, documented backlog item.
- **Keep the falsifying tests `.disabled`-with-reason rather than deleting them.** A deleted test loses the tripwire; a `.disabled` test with a reason pointing at `native-ink-compiler` keeps the gap honest and re-enables automatically when the subsystem lands.

---

## Quality State at Finalize

- **Full `swift test`: 290 tests, 0 failures** — releasable trunk.
- **SwiftLint `--strict` (R1/R3/R5 boundary): 0 violations** — `Compiler/` imports no `Engine/`, no `JSONSerialization`.
- **L1–L6 refactoring pass: clean** — no transformations needed; the code was already minimal, and the `VariableTextEmitter`/`ConditionalEmitter` parallelism is intentional (per OQ-3 discharge).
- **Adversarial review (nw-software-crafter-reviewer): APPROVED** — zero defects, no testing theater; every enabled AT ports port-to-port through `InkCompiler.compile` against committed inklecate oracles.
- **DES integrity (des-verify-integrity): exit 0** — "All 6 steps have complete DES traces".
- **Mutation testing: SKIPPED (disabled project-wide** per CLAUDE.md — no reliable Swift tool; test quality carried by the oracle execution-equivalence suite + code review + R1/R3/R5 boundary gates).

---

## Work Completed (step history)

| Step | Commit | What landed |
|---|---|---|
| 01-01 (slice 01) | `1954460` | Lowered the three deterministic variable-text forms; NEW `VariableTextEmitter`; narrowed `UnsupportedConstructDetector` to shuffle-only; AST/parser/emitter EXTENDs |
| 02-01 (slice 02) | `cdfcf2e` | Verified N-stage sequence clamp; discharged DESIGN OQ-3 (no `seq{N}`/`cond{N}` key collision in mixed bodies). Test-only |
| 03-01 (slice 03) | `45f5594` | Verified cycle modulo-wrap (2-stage + 4-stage OQ-1). Test-only |
| 04-01 (slice 04) | `9be123b` | Honest RED that **falsified the descope premise**; e2e + DISTILL re-pointing committed; AT left `.disabled` (genuinely failing) pending escalation |
| 05-01 (step 05) | `cd98c8c` | Delivered the `not` unary operator (parser + `.unary` AST + native postfix `!`) — the first of the two gaps slice-04 surfaced |
| 06-01 (step 06) | `aa72e14` | Investigation of gap #2 (dotted read-count addressing); RED-pinned + SCOPE-GUARD stop; scoped the weave-label subsystem and escalated for descope |

---

## Lessons Learned

- **An honest RED is the cheapest scope insurance.** Slice 04's truthful re-enable cost one commit and turned a believed-closed gap into two precisely-named follow-ups — far cheaper than discovering them in `native-ink-compiler` later, or worse, shipping a silently-wrong "fix."
- **Descope at the feature boundary that owns the concern.** The weave-label subsystem (choice-label parsing, label-keyed containers, count-visits flags, name→path table) is `native-ink-compiler` work; putting it there keeps `compiler-variable-text` cohesive and lets the next feature pick up a fully-scoped backlog item.
- **Waiving an invariant is acceptable when it is conscious, narrow, and recorded.** The "zero `.disabled` at finalize" rule is waived for exactly two user-approved ATs, each carrying a reason that names the follow-up — a documented exception, not a silent skip.
- **Zero-runtime-change lowering is achievable when the runtime already executes the target primitives.** Because inklecate's visit-count lowering uses only ops the runtime had (`visit`/`du`/`MIN`/`%`/`==`/conditional diverts), the entire variable-text feature is a compiler-only diff — KPI #4 ("no inklecate, no runtime change") held throughout.
- **Boundary gates held**: SwiftLint `--strict` 0 violations (R1/R3/R5); adversarial review APPROVED; DES integrity exit 0 across all 6 steps.

---

## Deferred / Follow-Up (native-ink-compiler)

| Item | Why deferred | What the follow-up needs |
|---|---|---|
| Dotted read-count addressing of named weave labels (`{label.sublabel: …}` → `CNT?` on a named label) | A whole weave-label addressing subsystem, not a point fix; a `native-ink-compiler` concern, not variable text | choice `(label)` + `{condition}` parsing on choices · label-keyed choice containers · count-visits flagging · name→path resolution table |
| `TheIntercept.ink` full native-compile e2e | Blocked solely by the item above (the `not`-operator blocker is now resolved) | re-enables automatically once the weave-label subsystem lands; the `.disabled` AT is the tripwire |

Both remain `.disabled`-with-reason in `Tests/SwiftInkRuntimeTests/Acceptance/` — failing honestly, named explicitly.

---

## Source-of-Truth Pointers

| Artifact | Path |
|---|---|
| Feature delta (DELIVER sections) | `docs/feature/compiler-variable-text/feature-delta.md` |
| Roadmap (step plan) | `docs/feature/compiler-variable-text/deliver/roadmap.json` |
| Execution log (step history) | `docs/feature/compiler-variable-text/deliver/execution-log.json` |
| Lowering ADR | `docs/product/architecture/adr-010-variable-text-lowering.md` |
| Measured KPI baselines | `docs/product/kpi-contracts.yaml` (`measured_baselines`) |
| Architecture brief (Feature Coverage Matrix + Component Inventory) | `docs/product/architecture/brief.md` |
| Predecessor evolution archive | `docs/evolution/native-ink-compiler-evolution.md` |
| Compiler sources | `Sources/SwiftInkRuntime/Compiler/` |
