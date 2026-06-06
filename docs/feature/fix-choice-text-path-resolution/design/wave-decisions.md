# Wave Decisions — fix-choice-text-path-resolution

**Feature**: fix-choice-text-path-resolution  
**Date**: 2026-06-04  
**Branch**: native-runtime  
**Scope**: Tier 1 fix (bracketed choice text + relative path resolution)

---

## Root Cause Analysis

### Bug report

A story using `* [bracketed text]` choices produced empty `Choice.text` for those choices. After selecting one, no continuation text appeared.

### Root Cause A — Empty choice text (`flg=20`)

Inklecate compiles `* [text]` choices as `flg=20`: the choice text is pushed onto `state.evalStack` via a `str`/`/str` instruction sequence preceding the `choicePoint` node. The engine's `stepToNextLine` shortcut reads choice text only from `containerStack.last?.container.namedContent["s"]` (the `flg=18`/`flg=22` path). For `flg=20`, no `"s"` sub-container exists, and the evalStack string is never consumed — `Choice.text` is always `""`.

### Root Cause B — No continuation text after choice

`InkEngine.chooseChoice()` calls `resolveNamedPath()` with the choice's target path. Inklecate emits **relative paths** (e.g., `.^.c-1`) for choices within knots. `resolveNamedPath` starts from `root` and has no understanding of:
- `.` prefix (current container)
- `^` component (parent traversal)

It returns `nil`, the `containerStack` update is silently skipped, and the exhausted container produces no output.

### Coupling

These two root causes are **coupled**. The `flg=18`/`flg=22` shortcut works because it bypasses the `str` / `{"->": ".^.s"}` / `/str` sequence — i.e., it works *around* the broken relative path resolution. Fixing path resolution without removing the shortcut will break `flg=18`/`flg=22` handling. Both must be fixed together.

---

## Architect Recommendations

From the solution architect review (2026-06-04):

1. **Remove the `namedContent["s"]` shortcut in `stepToNextLine`**. Replace it with eval-stack consumption: when a `.choicePoint` is encountered, pop `state.evalStack.last` as choice text when it holds a `.string` value. This handles all `flg` variants uniformly — the `str`/`/str` sequence already runs correctly in TreeWalker and deposits the string on `evalStack` before the `choicePoint` node is reached.

2. **Add `resolveRelativePath` to `InkEngine`**. Handle leading `.` (relative marker, discard) and `^` components (parent traversal using `containerStack`) before delegating the remainder to the existing absolute `resolveNamedPath`. Update `applyDivert` and `chooseChoice` to use this method.

3. **Model the `flg` bitmask minimally**. At minimum, `flg=4` (invisible default/gather) must suppress choices from `currentChoices`. `flg=8` (once-only) requires visit-count gating — document as a known gap if not addressed in this fix.

4. **`TreeWalker.handleChoicePoint` becomes dead code** once the shortcut is removed. Remove it.

---

## Scope Decision

**Tier 1 only** (user-approved 2026-06-04). This session addresses:

| Change | File |
|--------|------|
| Remove `namedContent["s"]` shortcut; consume `evalStack` string as choice text | `InkEngine.swift` |
| Add `resolveRelativePath` handling `.` prefix and `^` traversal | `InkEngine.swift` |
| Model `flg` bitmask: suppress `flg=4` invisible defaults | `InkEngine.swift` |
| Remove dead `handleChoicePoint` from TreeWalker | `TreeWalker.swift` |
| Regression tests: `flg=20` choice text, relative path resolution | `SwiftInkRuntimeTests` |

Tiers 2–3 (choice flag completeness, conditional text, functions, tunnels) are deferred to subsequent features. See `docs/product/architecture/brief.md` § Ink Feature Coverage for the full matrix.

---

## Paradigm

Object-Oriented with value-type state. Crafter: `@nw-software-crafter`.

## Mutation Testing Strategy

Per-project policy: skip Muter/mutation testing for Swift features (unreliable in this project). See project memory `feedback_mutation_testing.md`.
