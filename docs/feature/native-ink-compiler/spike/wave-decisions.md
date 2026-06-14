# SPIKE Decisions — native-ink-compiler

**Wave**: SPIKE (weave, unblock slice 03) | **Date**: 2026-06-14
**Agent**: Attila (nw-software-crafter) via `/nw-spike` | **Gate**: ADR-008

## Assumption Tested
- Ink's weave (choices + gathers with **indentation-driven loose-end
  resolution**) can be compiled to a `ContainerNode` tree the existing runtime
  plays choice-for-choice identical to the inklecate oracle. (Single highest-risk
  algorithm per the feasibility study; DESIGN Fork 3 / ADR-008.)

## Probe Verdict
- **WORKS**: flat + decisive multi-level **nested** weave both play identical to
  the oracle through the real engine, using the SIMPLE container template
  (`ev/str/^label/str/ev` + `choicePoint` + sibling `c-N`/`g-N` named containers +
  absolute-qualified diverts) — inklecate's `$r` machinery is NOT required.
  See `findings.md`. Probe: `swift test --filter SpikeWeaveProbe` → 2/2 green.

## Promotion Decision
- **PROMOTE** (project owner, 2026-06-14). Verdict is WORKS and the
  container-construction template is exactly the codegen pattern ADR-008's gate
  is meant to yield — worth building on immediately. Walking skeleton target:
  the FLAT weave fixture compiling-and-playing GREEN end-to-end through the real
  `InkCompiler.compile` driving port (slice S3a: bracketed/plain choices +
  single gather + loose-end resolution + flag encoding).

## Walking Skeleton (PROMOTE)
- Driving adapter: `InkCompiler.compile(source:)` → `StoryBlueprint` → `Story`.
- Acceptance test: `Tests/SwiftInkRuntimeTests/Acceptance/` — a `@walking_skeleton`
  execution-equivalence scenario for `compile-weave-flat`.
- Commit: _(filled in by the walking-skeleton commit)_.
- Demo command: `swift test --filter <walking-skeleton test name>`.

## Design Implications (for DELIVER S3 WeaveResolver / codegen)
1. Emit the SIMPLE choice-text form (evalStack string via `str`), not inklecate's
   `$r` start-content pointer dance. Level-1 execution equivalence is the gate.
2. Container template = per-level: choice eval+`choicePoint(c-N)` in parent
   children; sibling `namedContent` map of `c-N` outcomes + `g-N` gathers; nested
   weaves nest their own `c/g` map inside the parent outcome container.
3. Loose-end resolution: choice body → nearest same-level gather; gather → next
   enclosing-level gather; top gather → `end`.
4. Address by **absolute-qualified paths from root** (`c-0`, `g-0`, `c-0.g-0`);
   no relative `.^.` caret arithmetic needed.
5. Flags: bracketed `*[t]` = `0x14` (choice-only, no echo); plain `*t` = `0x12`
   (start content, echo label into outcome); sticky `+` omits `0x10` once-only.

## Constraints Discovered
- Engine `resolveChoiceText()` strategy #1 (evalStack string) is the contract the
  codegen targets — keep the `str`/`^label`/`/str` ordering exact.
- The four-fixture gate (flat/nested/labeled/sealed) is the S3 COMMIT gate,
  satisfied across the walking skeleton + DISTILL/DELIVER — not all by this probe.
