# Slice 03 — Migration guide maps InkStory to the native API

**Feature**: native-runtime-migration
**Story**: US-03
**Job**: job-runtime-consolidation
**Size**: ≤ 1 day
**Role**: "Map my code" — the destination the deprecation warning and the README point
to. (Delivery priority P2 — after the parity statement, so its caveats cross-reference
the gaps.)

## Learning hypothesis

> A complete `InkStory → Story/InkCompiler` mapping table — including shape differences
> and the one call with NO native equivalent (Combine observation) — lets an existing
> consumer rewrite their code call-by-call without reading source or asking the
> maintainer.

If false (the table omits a public method, or silently drops the Combine gap), a consumer
strands mid-migration or discovers a missing capability only after committing.

## In scope

- `docs/how-to/migrate-from-js-bridge.md` with a mapping table covering 100% of the
  `InkStory` public surface (per `Sources/InkSwift/InkStory.swift`).
- Explicit shape-difference flags: tags `[String:String]`→`[String]`; state
  `String`→`Data`; `getVariable` `JXValue`→`Any?`; added `throws` on choice/knot/state.
- The ⚠️ no-native-equivalent row for Combine reactive observation; names the v3.0.0 runway.

## Out of scope

- A step-by-step end-to-end walkthrough of migrating a whole app — that is the OFFERED
  `migration-playbook` [HOW] expansion (`migrate-from-js-bridge-playbook.md`), not
  auto-authored at this density.
- The parity/gaps statement itself (Slice 04) — this guide *links* it for caveats.
- Any code change.

## Real-consumer data (not synthetic)

- The README's own playback loop (`while story.canContinue { story.continueStory() }`)
  and SwiftUI Combine example (`@StateObject var story = InkStory()`, observed variables).
- The verified `InkStory` public surface: `loadStory(json:)`/`loadStory(ink:)`,
  `continueStory()`, `options`, `chooseChoiceIndex`, `moveToKnitStitch`, `currentTags`/
  `globalTags`, `getVariable`/`setVariable`, `stateToJSON`/`loadState`,
  `registerObservedVariable`/`oberservedVariables`, `retainTags`, the `Option` struct.

## Dogfood moment

Take the README's own two code samples (the CLI playback loop and the SwiftUI view) and
rewrite them using only the guide's table — confirm every call resolves to a row, and the
Combine observation lands on the explicit ⚠️ no-equivalent row.

## Taste tests

- **Thin?** Yes — one how-to doc, one mapping table.
- **End-to-end?** Yes — a consumer translates real calls to native.
- **User-visible?** Yes — the rendered mapping table in `docs/how-to/`.
- **Independent value?** Yes — a consumer can migrate from it even before the README or
  deprecation land.

## Acceptance criteria

See US-03 in `../feature-delta.md`. Green = 100% public-API coverage (equivalent or
explicit "no equivalent"), shape differences flagged, Combine gap explicit, v3.0.0 named.
