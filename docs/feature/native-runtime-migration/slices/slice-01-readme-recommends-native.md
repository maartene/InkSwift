# Slice 01 — README recommends the native runtime

**Feature**: native-runtime-migration
**Story**: US-01
**Job**: job-runtime-consolidation
**Size**: ≤ 1 day (~0.5d)
**Role**: "Discover the recommendation" — the first consumer touchpoint. Highest
visibility, lowest risk. (Delivery priority P3 — depends on the guide + parity docs
existing so its links resolve.)

## Learning hypothesis

> An existing/prospective InkSwift user who reads a repositioned README will choose the
> native `SwiftInkRuntime` for a new project — and, when a documented gap applies to
> their story, will knowingly stay on the JS-bridge — *because the recommendation is
> stated honestly with gaps up front*.

If false (README over-claims or hides gaps), a consumer migrates and hits a gap, losing
trust — the exact failure the "encourage, gaps documented" tone forbids.

## In scope

- Reposition `README.md` so `SwiftInkRuntime` is the recommended runtime for new
  projects (no JS engine, native compiler, Apple + Linux); remove the stale
  "experimental / plays the first 100 lines of the Intercept" wording.
- An honest "Known gaps vs the JS-bridge" note linking the parity statement (US-04) and
  the migration guide (US-03); no "full parity" claim.
- Reframe the existing JS-bridge section as the legacy path, pointing to the guide.

## Out of scope

- The deprecation attribute (Slice 02), the migration guide (Slice 03), the parity
  statement (Slice 04) — this slice *links* the last two, does not author them.
- Removing the JS-bridge or its README section (never in scope for this feature).
- Any code change.

## Real-consumer data (not synthetic)

- The current `README.md` line 4 banner ("experimental… first 100 lines") and the
  "Supported features" / "Getting started" sections that teach `InkStory`.
- A new-project SwiftUI-game adopter; a `LIST`-using adopter (must be sent to the bridge).

## Dogfood moment

Read the repositioned README as a new adopter: can you tell within the first screen that
native is recommended, and can a `LIST` user tell they should stay on the bridge?

## Taste tests

- **Thin?** Yes — one document, the runtime-guidance framing.
- **End-to-end?** Yes — a consumer reads the README and reaches a runtime choice.
- **User-visible?** Yes — the rendered README on `github.com/maartene/InkSwift`.
- **Independent value?** Yes — corrects a live, misleading claim even before the other slices.

## Acceptance criteria

See US-01 in `../feature-delta.md`. Green = README recommends `SwiftInkRuntime`, states
honest gaps with resolving links, no "full parity" claim, JS-bridge reframed as legacy.
