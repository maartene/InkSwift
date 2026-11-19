# ADR-018: Save-Format Compatibility for Typed Paths and Call Stack

**Status**: Accepted (maintainer confirmed Option A — existing saves must keep restoring, 2026-11-17). **Amended 2026-11-19**:
- [ADR-022](./adr-022-canonical-container-identity-visit-counts.md): `visitCounts` keys become canonical and are converted on restore. Compatibility is forward-only, so a new save is not supported on an older build.
- [ADR-020](./adr-020-continue-boundary-typed-output-stream.md): one new optional key for lookahead tags.
**Date**: 2026-11-17
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)
**Feature**: typed-runtime-paths (issue #25)
**Builds on**: ADR-003 (Codable format, internal, "explicit versioning if needed"), ADR-004

---

## Context

ADR-016/017 change the in-memory types of persisted `StoryState` fields:
`returnStack` (`[String]` → `[CallStackElement]`), `stackFrames[].pathFromRoot` and
`pointer.containerPath` (`[String]` → `ContainerPath`), `visitCounts` (`[String: Int]` →
keyed by `ContainerPath`), `chosenChoiceTargets` (`Set<String>` → `Set<ContainerPath>`),
`ChoiceData.continuationFrames`. Players' saves written by earlier builds exist in the wild.
The validated job `job-state-durability` (`docs/feature/state-blueprint-compatibility/`) is
"preserve a player's accumulated progress … or report unambiguously when it cannot be
restored". No test today restores a save captured by an *earlier build* — all save tests
round-trip within one build.

Technical constraint: `JSONEncoder` encodes a `Dictionary` with non-`String` keys as a flat
`[k, v, …]` array unless the key is `CodingKeyRepresentable`, whose runtime support is gated to
macOS 12.3 / iOS 15.4; the package deploys to macOS 10.15 / iOS 13.

## Decision

**Option A — wire-compatible encoding, no version field. Existing saves must keep
restoring.** The new types are typed in memory and encode to, and decode from, byte-identical
legacy strings:

| Field | Wire form (unchanged) |
|---|---|
| `returnStack` element, function | `"fnret:<dotted path>\|<index>"` (`"fnret:\|N"` at root) |
| `returnStack` element, tunnel | `"<dotted path>.<index>"` (`"N"` at root) |
| `pathFromRoot`, `containerPath` | `["a", "0", "g-2"]` |
| `visitCounts` | `{"a.b": 1}` — keys are `ContainerPath.description` |
| `chosenChoiceTargets` | sorted `["a.c-0", …]` |

The mapping lives in hand-written `Codable` (`StoryState` already has one); dictionary keys
are converted explicitly, not via `CodingKeyRepresentable`. Legacy-string grammar is confined
to these adapters.

**Earned-Trust probe**: before the first type change, capture golden saves from current
`main` (mid-tunnel, at a choice point, after a once-only choice, with visit counts) as
committed fixtures. Each typed slice must (1) restore them and continue with identical output,
and (2) re-encode a typed state to JSON structurally equal to its golden file — so saves from
the new build also restore on the previous build (rollback-safe).

**Known normalisation, accepted (2026-11-17, maintainer)**: the step that captured the goldens
(01-01) found that today's build does not re-save every save verbatim. A save taken with an
empty container stack (a top-level choice point) has `stackFrames: []`; on restore,
`InkEngine.rebuildContainerStack` synthesises one frame from `pointer`, and the next save
writes that frame out. The save plays identically, every build reads both forms (it is the
shape any save with frames already has), and the result is a fixed point after one round. This
is existing behaviour, not something #25 introduces, so the refactor preserves it: for such
goldens, re-save equality is checked against the golden with the synthesised frame, and a
second round must be identical (`TypedPaths_LegacySaveCompatibilityTests`). No issue is filed;
the normalisation is harmless and stable.

**Malformed return-stack entries are rejected (step 02-06)**: decoding a `returnStack` entry
that fits neither legacy form (`"<path>.<index>"`, `"fnret:<path>|<index>"`) now throws, so
`restoreState` reports the save as invalid instead of silently tolerating it. Every entry the
engine has written decodes. The only exception is a two-day window on `main` (2026-06-04
`30fe0ec` to 2026-06-06 `ea11694`), when `pushDivertTarget` also used the return stack. No
release tag contains that window, so no shipped save is affected.

## Alternatives Considered

### Option B — versioned migration (`formatVersion: 2`, structured JSON; reader accepts v1 and v2)
Cleaner wire, the ADR-003 "explicit versioning" route. **Rejected**: a permanent dual
reader for a pure representation change; a downgraded app cannot read v2 saves. Reserve
versioning for a change in *what* is saved.

### Option C — breaking change (new shape only; old saves throw `invalidStateData`)
Simplest code. **Rejected**: silently converts every in-flight player save into an
error, contradicting `job-state-durability`.

## Consequences

**Positive**: existing saves keep restoring; new saves remain readable by the previous release;
ADR-003's format stays internal and unversioned; the golden fixtures close a real test gap
(cross-build restore).

**Negative**: the legacy string grammar (`fnret:`, `|`, trailing index) survives inside the
`Codable` adapters, and the tunnel-return encoding stays ambiguous with a path whose last
component is a child index — the decoder must treat the last component as the return index,
exactly as the runtime does today.
