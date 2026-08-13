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
