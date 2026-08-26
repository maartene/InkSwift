# Native compiler — known gaps (deferred)

> **Reference (Diataxis).** Defects found and isolated but **deliberately not fixed
> yet**, with a reproduction for each. This exists so a gap is a recorded decision
> rather than a surprise. For the broader "should I migrate" picture see
> [JS-bridge vs native runtime parity](js-bridge-vs-native-parity.md).

Each entry names the layer it lives in. That distinction matters:

- an **engine** defect also affects stories loaded from pre-compiled
  inklecate/Inky `.ink.json` — no native compile involved;
- a **compiler** defect affects only `InkCompiler.compile(source:)`; the same
  story loaded from oracle json plays correctly.

## Deferred — conditionals inside function bodies (compiler)

Found 2026-08-13 while fixing the engine's function-body container handling
(`Engine_FunctionBodyContainerTests`). The **engine** half is fixed; these two
remain, both compiler-side.

### G1 — execution stops after a call to a function containing an inline conditional

```ink
~ say(false)
Done.
-> END

=== function say(v) ===
{v: yes|no}
```

| path | output |
|---|---|
| `inklecate -p` | `no`, `Done.` |
| oracle json through this runtime | `no`, `Done.` ✅ |
| **native compile** | `no` ❌ — `Done.` never emitted |

The call itself works and the conditional now picks the right branch; what is lost
is everything *after* the call returns.

### G2 — a block conditional in a function body produces no output at all

```ink
~ note(true)
Truthy: {truthy}
-> END

=== function note(v) ===
{ v:
    ~ truthy = truthy + 1
}
```

| path | output |
|---|---|
| `inklecate -p` | `Truthy: 1` |
| oracle json through this runtime | `Truthy: 1` ✅ |
| **native compile** | *(nothing)* ❌ |

G1 and G2 are plausibly one root cause — both are conditionals lowered inside a
function body — but that has **not** been confirmed, and they are recorded
separately until it is.

### Why deferred

These sit in codegen for function bodies, not in an isolated parser rule. The five
compiler fixes that preceded them (`0356325`, `58dd2d4`, `78167e3`, `a05c58f`,
`f8be2cb`) were each a localized decision with a clear oracle answer. G1/G2 need a
codegen-level investigation of how conditional sub-containers and the function
return path interact, which is its own piece of work rather than a tail-end
addition to a bugfix run.

### Workaround

Load pre-compiled inklecate json (`Story(json:)`) for stories that put a
conditional inside a function body — the engine path is correct for both cases.
Alternatively, keep function bodies free of conditionals: compute the condition at
the call site and pass the result in.

### Reproducing

Fixtures for the fixed engine case are committed as
`Tests/SwiftInkRuntimeTests/Fixtures/engine-function-conditional-branch.ink{,.json}`.
The G1/G2 sources above reproduce directly through
`InkCompiler.compile(source:)` versus `Story(json:)` on the same source.

## Deferred — `-> END` does not discard pending choices (engine)

Found 2026-08-26 while closing issues #18 and #21. Affects pre-compiled
inklecate/Inky json too, so it is an **engine** gap, not a compiler one.

Ink distinguishes its two terminators. `DONE` means "this thread has no more
content"; `END` means the story is over, and inkle's runtime implements that as
`StoryState.ForceEnd()`, which clears `currentChoices` (see joethephish on
inkle/ink#129 — *"`END` ensures the story really does come to an end! So, it
cancels/removes any choices that exist"*). `Engine/TreeWalker.swift` collapses
both into one case that only sets `isEnded`, so choices generated before the
story ends are still presented.

### Reproducing

These two sources differ only in the last line. inklecate plays them
differently; InkSwift plays them identically.

```ink
VAR x = 1
-> start
=== start ===
* First
    Chose first.
    { x == 1:
        * Nested in arm
            -> after
    }
* Second
    -> after
-
-> after
=== after ===
Done.
-> END     ← swap for `-> DONE` for the contrasting case
```

| last line | inklecate 1.2.1 | InkSwift |
|---|---|---|
| `-> END` | `Chose first.` / `Done.`, no choice offered | offers `Nested in arm` |
| `-> DONE` | `Chose first.` / `Done.`, offers `Nested in arm` | same — matches |

It surfaces only when flow continues *past* generated choices before ending,
which in practice means a choice written inside a conditional arm or a thread.

### Why deferred

The fix is in `Engine/`, which the compiler work treats as REUSE-AS-IS (CLAUDE.md;
SwiftLint R1/R3/R5). Giving `end` its own `ForceEnd`-equivalent is a small change
but a runtime behaviour change affecting every story, including pre-compiled ones,
so it wants its own decision and its own regression fixtures rather than riding
along with a compiler fix.

## Deferred — a conditional *before* a choice in the same arm strands the rejoin (compiler)

Found 2026-08-26 alongside #21. A **compiler** gap.

```ink
VAR x = 1
VAR y = 2
-> start
=== start ===
Before.
{ x == 1:
    { y == 2:
        Inner.
    }
    * A choice
        -> done
}
Trailing.
=== done ===
Done.
-> END
```

inklecate plays `Before.` / `Inner.` / `Trailing.` then offers `A choice`.
InkSwift drops `Trailing.`.

When a conditional block precedes the choice inside the arm,
`RuntimeObjectEmitter.leadsWithWeave` returns `false` (it stops at the first
`.conditionalBlock`), so the arm takes the plain lowering path and the choice ends
up inside the INNER conditional's rejoin container — whose terminating `done`
halts the flow, stranding the outer `-end`.

`ConditionalEmitter.terminateArm` fixes exactly this shape for an arm, but the
same swap is **not** valid for a rejoin container in general: a rejoin's weave sits
at the enclosing knot's weave level, where the `done` is the knot's own terminator.
Applying it there re-enters content that has already played (TheIntercept emits its
`sipping at my tea` line twice). Closing this needs the rejoin to know whether its
weave is the knot's or a nested sub-weave — more than a local patch.
