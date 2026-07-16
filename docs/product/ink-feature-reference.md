# Ink Feature Reference — Supported vs Unsupported Constructs

**Type:** Reference (Diataxis). Scannable status tables, not a tutorial.

This document is the human-readable face of the native InkSwift compiler's accepted
feature set. It classifies every Ink construct from the [Feature Coverage Matrix](architecture/brief.md#feature-coverage-matrix)
(rows 1–39) as **MUST-COMPILE** or **MUST-REJECT**, with a one-line example and a
one-line reason for each.

## The supported set == the runtime-playable set

The native compiler's accepted set is, by design, **exactly** the set of constructs
the `SwiftInkRuntime` engine can play (architecture invariant DDD-12). The compiler
never emits a blueprint for a construct the runtime cannot execute; conversely every
construct the compiler accepts is playable line-for-line, choice-for-choice against
the inklecate oracle.

As of slice-01 the **deterministic variable-text forms** (sequence / cycle / once)
**MUST-COMPILE**: the compiler now lowers them onto the visit-count switch the
runtime already plays. Only the **shuffle** form `{~a|b}` remains MUST-REJECT among
the variable-text constructs, because it additionally needs RANDOM — see
[Known gaps / future work](#known-gaps--future-work).

A construct documented MUST-COMPILE below provably compiles, and a construct
documented MUST-REJECT provably rejects with a located `.unsupportedConstruct`
error. This consistency is enforced executably by
`Tests/SwiftInkRuntimeTests/Acceptance/Compiler_S5_FeatureReferenceConsistencyTests.swift`
(8 supported-compile + 5 unsupported-reject checks). If this table and that suite
ever disagree, the suite is the source of truth and this document is the bug.

## MUST-COMPILE

These constructs compile to a playable blueprint. (Matrix rows 1–27, 29–35.)

| # | Construct | Example | Reason |
|---|-----------|---------|--------|
| 1 | Text output / newlines | `Hello, world.` | Plain prose is the base case; emitted verbatim. |
| 2 | Knots (`=== name`) | `=== forest ===` | Named top-level containers; resolved as divert targets. |
| 3 | Stitches (`= name`) | `= clearing` | Named sub-containers within a knot. |
| 4 | Diverts (`->`) | `-> forest` | Absolute, relative pure-ancestor, and anchor diverts all resolve. |
| 5 | Relative paths (`.^.x`) | `-> .^.clearing` | Caret parent-traversal + named lookup per stack frame. |
| 6 | Plain choices (`* text`) | `* Go north` | Once-only choice presenting literal text. |
| 7 | Bracketed choices (`* [text]`) | `* [Look around]` | Bracketed text shown in the choice but not echoed into output. |
| 8 | Sticky choices (`+ text`) | `+ Wait` | Remains selectable after being picked. |
| 9 | Once-only suppression | `* Open the door` | A picked once-only choice is suppressed on revisit. |
| 10 | Invisible defaults | `* ->` | Auto-divert taken when no visible choice remains. |
| 11 | Conditional choices (`* {cond}`) | `* {hasKey} Unlock` | Choice shown only when the guard evaluates true. |
| 12 | Gathers (`-`) | `- They met again.` | Re-converges branching flow; nesting supported. |
| 13 | Labeled gathers / options `(label)` | `- (reunion)` | Named gather usable as a relative divert target. |
| 14 | Read counts | `{forest}` | Knot/stitch visit counters readable in expressions. |
| 15 | Glue (`<>`) | `Hello <> world` | Suppresses the surrounding newline to join lines. |
| 16 | VAR global variables | `VAR hp = 10` | Mutable global state. |
| 17 | CONST declarations | `CONST MAX = 99` | Inlined as a literal at compile time. |
| 18 | Temp variables (`~ temp`) | `~ temp x = 1` | Frame-scoped local variable. |
| 19 | Variable assignment (`~ x =`) | `~ hp = hp - 1` | Mutates a declared variable. |
| 20 | Variable read in output (`{x}`) | `You have {hp} HP.` | Interpolates a variable into output. |
| 21 | Arithmetic / logic operators | `{hp > 0 && alive}` | `+ - * / % == != > < && \|\| !` all evaluate. |
| 22 | Inline conditionals (`{c: a\|b}`) | `{alive: alive\|dead}` | Inline branch on a boolean/numeric guard. |
| 23 | Block conditionals (if / else if) | `{ hp > 0:\n  alive\n- else:\n  dead\n}` | Multi-line conditional block with else branch. |
| 24 | Switch-style conditionals | `{ kind:\n- 1: red\n- 2: blue\n}` | Per-case dispatch via `==` + conditional diverts. |
| 25 | Variable text: sequences (`{a\|b\|c}`) | `{red\|green\|blue}` | Lowered to a visit-count switch that clamps at the last stage (`MIN`). |
| 26 | Variable text: cycles (`{&a\|b}`) | `{&one\|two}` | Lowered to a visit-count switch that wraps modulo the stage count (`%`). |
| 27 | Variable text: once-only (`{!a\|b}`) | `{!first time\|}` | Lowered to a visit-count switch that advances once per stage then blanks. |
| 29 | Functions (`=== f(params) ===`) | `=== function raise(x) ===` | Callable knot with parameters and a return frame. |
| 30 | Inline function calls `{f()}` | `{double(5)}` | Function invocation whose return value is emitted. |
| 31 | String interpolation | `Score: {score}` | `str`/`/str` interpolation of expression results. |
| 32 | Tags (`#tag`) | `Hello #greeting` | Metadata tag attached to a line. |
| 33 | Save / restore | (engine state) | `StoryState` round-trips through `chooseChoice`. |
| 34 | Tunnels (`-> knot ->`) | `-> combat ->` | Divert that returns to the call site via the return stack. |
| 35 | Reference parameters (`ref x`) | `~ raise(ref hp)` | By-reference parameter mutating the caller's variable. |

## MUST-REJECT

These constructs are rejected by the compiler with a located
`.unsupportedConstruct` error. (Matrix rows 28, 36–39.)

| # | Construct | Example | Reason |
|---|-----------|---------|--------|
| 28 | Variable text: shuffle (`{~a\|b}`) | `{~heads\|tails}` | Requires RANDOM, which the runtime genuinely lacks. |
| 36 | Threads (`<-`) | `<- conversation` | Concurrent flow weaving is unimplemented in the runtime. |
| 37 | LIST declarations | `LIST colors = red, green` | List value type and operators are unimplemented. |
| 38 | RANDOM / SEED_RANDOM | `~ r = RANDOM(1, 6)` | No deterministic RNG support in the runtime. |
| 39 | External functions | `EXTERNAL beep()` | No host-binding mechanism for external calls. |

## Known gaps / future work

**Maintenance convention — this gap list is the native-runtime parity backlog.**
The MUST-REJECT table and the gaps below are not just documentation; they are the
running to-do list of work remaining to reach parity with the inkjs-backed JS-bridge
(`InkSwift`). Whenever a feature adds a capability that closes a gap — moving a
construct from MUST-REJECT to MUST-COMPILE, or landing a missing API-parity capability
— that feature MUST, as part of its GREEN/finalize step, revisit this list and remove
(or reclassify) every gap it closed, so the backlog only ever lists what is genuinely
still missing. Precedent: slice-01 moved the deterministic variable-text rows 25–27
from MUST-REJECT to MUST-COMPILE and updated this document in the same change. A closed
gap left in this list is a stale backlog — treat it the same as a stale test.

The MUST-REJECT list above is honest about *why* each construct is rejected, because
the reasons are not uniform:

- **Deterministic variable-text (sequence / cycle / once — rows 25–27)** is now
  **supported** (slice-01). inklecate compiles `{a|b|c}` and its `&`/`!` variants
  into a read-count-driven visit-count switch (`visit + MIN`/`%` + `==` + conditional
  diverts), and the native compiler lowers these source forms onto exactly that shape
  via `VariableTextEmitter` — no runtime change was needed.

- **Shuffle (`{~...}` — row 28)** depends on RANDOM, which the runtime does not
  provide. It therefore stays unsupported until RANDOM lands — it is the only
  variable-text form still rejected.

- **Threads, LIST, RANDOM/SEED_RANDOM, EXTERNAL (rows 36–39)** are
  **runtime-unsupported**: the engine has no execution model for them today. These
  are lower priority (the BEYOND tier) and out of scope for the current ceiling.

### Variable-text lowering, by example

The comprehensive end-to-end fixture `Tests/InkSwiftTests/TheIntercept.ink` uses a
once-only variable-text form on line 86:

```ink
{|I rattle my fingers on the field table.|}
```

This bare once-only spelling is a plain sequence (`["", "I rattle…", ""]`): the text
appears on the second visit, then the form falls silent. As of slice-01 the native
compiler lowers it directly — closing the last variable-text gap that blocked native
compilation of this fixture (shuffle aside).
