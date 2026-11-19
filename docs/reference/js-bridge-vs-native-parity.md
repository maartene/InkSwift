# JS-bridge vs native runtime — supported parity & known gaps

> **Reference (Diataxis).** This is the honest, single source for *what the native
> `SwiftInkRuntime` can and cannot do yet* relative to the legacy JavaScriptCore
> JS-bridge (`InkStory`). It exists so you can decide — against your actual story —
> whether to migrate now, wait, or stay on the bridge.

## Recommendation

**We recommend `SwiftInkRuntime` for new projects.** It is a pure-Swift runtime with a
native Ink compiler, no JavaScript engine (no JavaScriptCore / JXKit dependency), and it
runs on both Apple platforms and Linux.

This is **not** a claim of complete parity. The JS-bridge (`InkStory`, backed by inkjs)
still supports a handful of Ink constructs and one API capability the native runtime does
not yet have. Those gaps are listed below. **Stay on the JS-bridge if you need any of them.**

The JS-bridge is now **legacy** and is scheduled for removal in **v3.0.0**. It remains
fully functional and supported until then. To migrate, follow the
[migration guide](../how-to/migrate-from-js-bridge.md).

## Known gaps vs the JS-bridge

The gaps come from two sources, aggregated here without duplicating the construct SSOT.

### Feature (construct) gaps

The language-construct gaps are owned by the construct SSOT, not restated here. See the
**MUST-REJECT** rows in
[`docs/product/ink-feature-reference.md`](../product/ink-feature-reference.md) for the
authoritative, always-current list. As of today they are:

- **`LIST` declarations** (MUST-REJECT row 37)
- **`RANDOM` / `SEED_RANDOM`** (MUST-REJECT row 38)
- **Threads (`<-`)** (MUST-REJECT row 36)
- **`EXTERNAL` functions** (MUST-REJECT row 39)
- **Shuffle variable-text (`{~a|b}`)** (MUST-REJECT row 28 — depends on `RANDOM`)
- **Multi-line sequences (`{stopping:` … `}`)** (MUST-REJECT row 40 — the native compiler only; the inline forms are supported)
- **`INCLUDE`** (MUST-REJECT row 41 — the native compiler only; load a multi-file story from its inklecate `.ink.json`)
- **Strings with inline logic (`~ return "value {n}"`)** (MUST-REJECT row 42 — the native compiler only; quotes in prose are fine)
- **Tags with inline logic (`# pic{n}.jpg`)** (MUST-REJECT row 43 — the native compiler only; static tags are fine)
- **Tags inside inline logic (`{met: Hi # greeting}`)** (MUST-REJECT row 44 — the native compiler only)

For the gaps marked "the native compiler only", compiling with inklecate and loading the
`.ink.json` with `Story(json:)` is a workaround (except multi-line sequences, which the
runtime plays wrong too). See
[How InkSwift differs from inklecate](differences-from-inklecate.md).

If your story uses any of these, stay on the JS-bridge for now.

### Behaviour gaps found by the upstream conformance suite

Beyond the rejected constructs, ink's own test suite (`tests/Tests.cs` from inkle/ink,
ported as `Tests/SwiftInkRuntimeTests/Conformance/`) shows places where a story the native
runtime accepts plays differently from the reference. Each failing upstream test is
recorded as a disabled backlog item naming the gap. Examples: `TURNS()` and `TURNS_SINCE`,
some glue placements, default (fallback) choices, tunnel onwards with a divert
(`->-> target`), float formatting and division, and some newline handling. For the current list, run:

```
grep -rho 'conformance: [^"]*' Tests/SwiftInkRuntimeTests/Conformance | sort | uniq -c | sort -rn
```

If your story relies on one of these, check it against the JS-bridge before migrating.

### API gaps

These are surface/behaviour differences between the `InkStory` API and the native
`Story` / `InkCompiler` API. They are owned by this statement (the construct SSOT does
not cover them):

- **Combine reactive observation** — *no native equivalent.* The JS-bridge conforms to
  `ObservableObject` and exposes `@Published` properties plus
  `registerObservedVariable` / `oberservedVariables` for Combine-driven variable
  observation. The native `Story` has no Combine/observation surface; poll `getVariable`
  instead, or stay on the bridge if reactive observation is essential.
- **Tag shape** — the JS-bridge exposes tags as `[String: String]`; the native runtime
  exposes them as `[String]`. Migrating code that reads tags must adapt to the array
  shape.
- **Error handling** — the JS-bridge surfaces problems via a `currentErrors` array. The
  native runtime splits them: misuse of the API (an invalid choice index, an unknown knot,
  an invalid save) **throws** from the corresponding call, so migrating code moves from
  array inspection to `try` / `catch` there. Errors in the story itself are reported in
  `Story.currentErrors` and stop the story (`canContinue == false`), using the reference
  runtime's messages. So far this covers a `->->` or `~ return` with no matching tunnel or
  function on the call stack. Running out of content is not reported yet
  ([#28](https://github.com/maartene/InkSwift/issues/28)). These errors are never saved,
  and `restoreState` / `moveToKnot` clear them.

Stay on the JS-bridge if any of these block you; otherwise migrate with the
[migration guide](../how-to/migrate-from-js-bridge.md).

## This list is a living backlog

**Maintenance convention.** This gaps list is the native runtime's *to-do list toward
v3.0.0*, not a one-time snapshot. Each later feature that **closes a gap** — moving a
construct from MUST-REJECT to MUST-COMPILE in `ink-feature-reference.md`, or landing a
missing API-parity capability such as Combine observation — MUST revisit this statement
and **prune the closed item as part of its GREEN/finalize step**. A closed gap left
listed here is a stale backlog — treat it the same as a stale test.

The construct-gap half of this convention is already recorded at the top of the "Known
gaps / future work" section of `ink-feature-reference.md`; the API-gap half (Combine
observation, tag shape, error handling) is owned and maintained here.

## See also

- [Migration guide: InkStory → Story / InkCompiler](../how-to/migrate-from-js-bridge.md)
- [Ink feature reference (construct-gap SSOT)](../product/ink-feature-reference.md)
- [How InkSwift differs from inklecate](differences-from-inklecate.md)
