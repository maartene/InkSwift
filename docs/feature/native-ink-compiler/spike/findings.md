# SPIKE Findings — native-ink-compiler weave (unblock slice 03)

**Date**: 2026-06-14 | **Agent**: Attila (nw-software-crafter) via `/nw-spike`
**Gate**: ADR-008 (Weave-Resolution Spike Gate) | **Time box**: ≤ 1h (used ~45m)

## Assumption tested (ONE)
> Ink's **weave** — choices + gathers with **indentation-driven loose-end
> resolution** — can be compiled to a `ContainerNode` tree that the EXISTING
> runtime engine plays **choice-for-choice identical** to the inklecate oracle.

This is the single highest-risk algorithm named by the feasibility study and
slice-03's risk note; DESIGN spike-gated S3 on it (Fork 3 / ADR-008).

## Verdict: **WORKS** ✅

Both corpus fixtures play **identical** to the committed inklecate oracle through
the real `Story`/`InkEngine`, along the committed choice scripts:

| Fixture | Choice script | Native == Oracle | Notes |
|---|---|---|---|
| `compile-weave-flat`   | `[0]`    | ✅ | bracketed once-only choices, single gather (warm-up) |
| `compile-weave-nested` | `[0, 0]` | ✅ | **decisive**: 2 weave levels, multi-level loose-end resolution |

Native (probe) playthrough for nested matched oracle exactly:
`["The door stands before you.", "Open it", "Step through", "You stepped through
into the dark.", "You pause at the threshold.", "The scene ends."]`

Probe: throwaway `@Test` (`Tests/SwiftInkRuntimeTests/SpikeWeaveProbe.swift`,
archived to `$TMPDIR/spike_native_ink_compiler_probe.swift`). Run:
`swift test --filter SpikeWeaveProbe` → 2/2 green in 5 ms.

## Why the probe is decisive without a full parser
Downstream is already proven: the engine plays inklecate JSON for the entire
oracle corpus, and `ContainerNode` is the established shared seam (DESIGN Fork 1A).
The only unproven link was **weave-resolution → engine-playable container tree**.
The probe hand-builds that tree (bypassing the not-yet-written choice parser) and
plays it through the real engine — isolating exactly the gated risk.

## Mechanism learnings (→ design implications for the WeaveResolver/codegen)

1. **No `$r` return-pointer machinery needed.** inklecate renders choice start
   content via a `^->`/`temp=$r`/`->.^.s` pointer dance + an `s` sub-container.
   The engine's `resolveChoiceText()` **strategy #1** reads a plain string off the
   evalStack, so the simple vocabulary suffices:
   `ev, str, ^<label>, /str, /ev, choicePoint(target, flg)`.
   → Codegen emits the **simple** form; it need not replicate inklecate's tree shape
   (consistent with the Level-1 execution-equivalence gate, not Level-2 structural).

2. **Container-construction template** (this becomes the codegen pattern, per ADR-008):
   - Each choice at a level → `ev/str/^label/str/ev` + `choicePoint(target: c-N)`
     in the *parent* container's `children`.
   - A **sibling `namedContent`** map holds the outcome containers `c-N` and the
     gather containers `g-N`. Nested weaves nest their own `c/g` map inside the
     parent choice's outcome container.
   - Each `c-N` body ends in a `divert` to its resolved gather; each `g-N` ends in
     a `divert` to its enclosing-level gather (or `end`/`done` at the top).

3. **Loose-end resolution rule (confirmed against the oracle):**
   - a choice body's loose end → the **nearest gather at its own level** after it;
   - a gather's loose end → the **next gather at the enclosing (shallower) level**;
   - top-level gather loose end → `end`.

4. **Addressing: use absolute-qualified paths from root.** The engine's
   `navigateAbsolute`/`resolveNamedPath` walk `namedContent`/numeric children from
   root, so targets like `c-0`, `g-0`, `c-0.g-0` resolve unambiguously regardless
   of execution position. → Codegen can emit absolute qualified targets and **avoid
   relative `.^.` caret arithmetic** entirely. (Relative paths remain available but
   are not required.)

5. **Choice-text vs output echo:**
   - **bracketed** `* [text] body` → label is choice-only; body does NOT echo the
     label (flg `0x14` = `hasChoiceOnlyContent | isOnceOnly`).
   - **plain** `* text` → label echoes into output; outcome container prepends
     `text(label), newline` (flg `0x12` = `hasStartContent | isOnceOnly`).
   - Once-only (`*`) sets `0x10`; sticky (`+`) omits it — handled by the engine's
     existing `isOnceOnly` suppression (already proven on the oracle path).

## Edge cases / scope NOT exercised by the probe (deferred to DISTILL/DELIVER S3)
- `labeled-gather` and `sealed` fixtures (the other two gate fixtures) — easier
  variants (named gather target; all-choices-divert-away). Full four-fixture gate
  belongs to the walking skeleton + DISTILL, not the throwaway probe.
- **Sticky vs once-only** replay suppression and **conditional `* {cond}`** choices
  (slice-03 IN scope, but lower algorithmic risk — engine already handles the flags).
- **Read counts / knot visit counters** (slice-03 rows 12-14).
- **Whitespace exactness**: the harness trims per line, so leading-space details
  (`^ You went left`) are not asserted; Level-1 line/choice identity is.
- The real **choice parser** (indentation tokenizer → weave IR) is unwritten; the
  probe hardcodes the IR. Building the general recursive resolver is DELIVER work.

## Promotion note
Promoted on 2026-06-14 — see `wave-decisions.md` for the gate decision.
