# DISTILL Upstream Issues — compiler-variable-text

**Date**: 2026-06-15 | Author: acceptance designer (DISTILL)

Gaps/contradictions surfaced while writing the acceptance tests against prior-wave
artifacts. None block DISTILL (reconciliation passed, 0 contradictions); recorded for
DELIVER and for the record.

## U-1 — DISCUSS US-01 example 3: bare `{|x|}` is NOT identical to `{!x|}` (CLARIFICATION)

**Where**: feature-delta DISCUSS / US-01 "Domain Examples" #3 and the UAT scenario "The
bare once-only spelling lowers identically to the '!' spelling."

**Issue**: DISCUSS states the bare `{|x|}` spelling "lowers identically to the `!`
spelling." The inklecate ground truth (and DESIGN's Lowering Specification, verified
before this wave) shows they differ:

- `{!x|}` (shorthand once) → stages `[x, "", ""]`, `visit 2 MIN` → text emits on **visit 0**.
- `{|x|}` (bare) → a **plain sequence** `["", "x", ""]`, `visit 2 MIN` → text emits on **visit 1**.

So with a sticky-choice loop, `{!x|}` shows its text on the first entry; `{|x|}` shows
nothing on the first entry and the text on the second. They are NOT interchangeable.

**Resolution**: DESIGN is authoritative (DESIGN DDD-4 / Lowering table explicitly: "bare
`{|x|}` is NOT special — a plain sequence"). The acceptance tests (`Compiler_VT1_*`)
assert the real per-spelling shape (`vt-once-sticky` vs `vt-once-bare`). No code change
needed; the DISCUSS wording is the imprecise artifact. TheIntercept line 86
`{|I rattle…|}` is the **bare** form, so its native compile lowers as a plain sequence —
consistent with US-04.

**Action**: none required for DELIVER behaviour. Optional: soften the DISCUSS US-01
example-3 wording on a future edit. Not a back-propagation blocker.

## U-2 — Existing reject suites assert rows 25-27 as unsupported (REQUIRED DELIVER EDIT)

**Where**: `Compiler_S6_UnsupportedRejectionTests.swift` (`rejectCorpus`) and
`Compiler_S5_FeatureReferenceConsistencyTests.swift` (`documentedUnsupported`).

**Issue**: both suites currently assert `reject-seq`/`reject-cycle`/`reject-once` reject
(green today). This feature flips them to compile. When the slice-01 gate change lands,
those assertions RED.

**Action (DELIVER, slice that lands the gate — slice-01)**:
- S6: drop `reject-seq`/`reject-cycle`/`reject-once` from `rejectCorpus` (keep
  shuffle/thread/list/random/external).
- S5: move those three from `documentedUnsupported` to `documentedSupported` (needs
  playable oracle fixtures for the moved entries, or point them at the new `vt-*` family).
- `docs/product/ink-feature-reference.md`: rows 25-27 MUST-REJECT → MUST-COMPILE (the
  DISCUSS downstream doc-update note). The S5 suite is the SSOT the prose mirrors.

## U-3 — Predecessor fixture `reject-once.ink` uses an escaped `\!` (latent, low)

**Where**: `Tests/SwiftInkRuntimeTests/Fixtures/reject-once.ink` =
`You knock. {\!The door is new to you.|You have been here before.}`.

**Issue**: the `\!` is an escaped literal bang, so inklecate reads it as a 2-stage
*sequence* `["!The door…", "You have been here before."]`, not a once-only form. It was
harmless while the whole variable-text family rejected wholesale. Once rows 25-27 compile,
this fixture is mislabelled. (Same shell-escaping artifact bit the initial authoring of
`vt-once-sticky.ink`, fixed here by writing the byte-exact `!`.)

**Action (DELIVER, when reworking S5/S6 per U-2)**: if `reject-once` is repurposed as a
*supported* once fixture, write the unescaped `{!…|}` form (byte-exact). Low priority.
