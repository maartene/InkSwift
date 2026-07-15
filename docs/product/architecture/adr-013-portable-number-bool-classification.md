# ADR-013: Portable JSON Number/Bool Classification — JSONDecoder + Custom Decodable

**Status**: Accepted (guided-discovery decision locked 2026-07-15)
**Date**: 2026-07-15
**Deciders**: Maarten Engels (project owner), Morgan (nw-solution-architect)
**Feature**: native-runtime-linux (DD-1)

---

## Context

`SwiftInkRuntime` must build, test, and play identically on Linux and macOS
(feature `native-runtime-linux`, KPI-1/KPI-3). The single blocking source-level
defect is number/bool classification in the decoder.

`InkDecoder.decode(_:)` currently parses `.ink.json` via
`JSONSerialization.jsonObject` into `[String: Any]`, then `classify(_:)` matches
each scalar as `NSNumber` and hands it to `classifyNumber(_:)`
(`Sources/SwiftInkRuntime/Decoder/InkDecoder.swift:24-36` and `:123-138`).
`classifyNumber` decides int vs float vs bool using **CoreFoundation type
identity**: `CFGetTypeID(number) == CFBooleanGetTypeID()` for booleans, then
`CFNumberGetType(number as CFNumber)` against an explicit list of integer CF
number subtypes.

This path is **unreliable under swift-corelibs-foundation** (the non-Apple
Foundation used on Linux). The `NSNumber`/`CFNumber`/`CFBoolean` bridging and the
`CFNumberGetType` subtype reported for a JSON-parsed value are not guaranteed to
match Apple's CoreFoundation. The failure mode is **silent**: a `2.5` float can
classify as `.intValue(2)` and a `true` boolean as `.intValue(1)`, changing
rendered story text (`Health: 2` instead of `Health: 2.5`, `true` printed as `1`)
on Linux while every macOS test stays green. This is precisely the anxiety in the
JTBD (`job-linux-portability`) and the highest-risk silent bug in the feature
(KPI-3: zero misclassifications).

**Quality attributes for this decision** (ranked): Correctness (platform-identical
value typing) > Portability > Testability/Reliability > Maintainability. No new
runtime dependency is permitted; paradigm is object-oriented (value-type structs
with mutating methods, per CLAUDE.md).

DISCUSS deliberately left the *mechanism* open (open question 1); this ADR closes
it.

---

## Decision

Classify JSON numbers and booleans through **`JSONDecoder` + a custom `Decodable`**
for Ink node scalar values, replacing the `JSONSerialization` + CoreFoundation
type-identity path. Typing is driven by **decode success against the JSON token
grammar**, not by CF runtime type identity.

- The decoder's scalar value type conforms to `Decodable` and, from a
  `singleValueContainer()`, attempts decode in the order **Bool → Int → Double →
  String**. The first successful decode wins.
  - `true`/`false` JSON literals decode as `Bool` (and only as `Bool` — Foundation's
    `JSONDecoder` does not coerce `1`→`true`).
  - Integer literals (`2`) decode as `Int`; `Bool` and (for `2.5`) `Int` decodes fail
    first, so `2.5` falls through to `Double`.
  - This ordering is the load-bearing correctness property: the JSON *token* (literal
    `true`/`false`, integer, fractional) drives the type, and the token grammar is
    identical across Foundation implementations.
- All changes stay **inside `Decoder/`**. `ContainerNode`/`NodeKind` and the internal
  node-value representation are untouched at their public/internal boundary; only the
  path from raw bytes → node scalars changes. No new source files are required (the
  custom `Decodable` may live in `InkDecoder.swift` or a sibling `Decoder/` file — a
  crafter-level choice).
- The behaviour contract is unchanged: `.boolValue`, `.intValue`, `.floatValue` node
  tags for the same input, on every platform. US-01 (walking skeleton) validates this
  cross-platform against a committed macOS-captured fixture.

**Earned-Trust probe extension (DD-4)**: `InkDecoder.probe()` — the driven adapter's
startup probe — is extended to exercise *the specific substrate lie this decision
guards against*. The embedded probe fixture MUST contain a float (`2.5`), a boolean
(`true`), and an integer (`2`); the probe asserts they classify as `.floatValue` /
`.boolValue` / `.intValue`. A platform that misclassifies fails the probe, and
`Story.init(json:)` throws `StoryError.decoderProbeFailure(reason:)` — the
mistyping-on-Linux bug becomes non-representable at story startup ("wire then probe
then use"), not merely testable-around.

**Boundary-rule consequence (R3 generalization + collision, DD-5)**: boundary rule
R3 currently confines `JSONSerialization` to `Decoder/`. Its *intent* — "Ink
`.ink.json` decoding lives only in `Decoder/`" — must survive the API change, else
the rule matches nothing and the boundary erodes. The rule text generalizes to
"**Ink-format JSON decoding (`JSONSerialization`/`JSONDecoder` for the `.ink.json` →
node-tree substrate) confined to `Decoder/`**" in both `brief.md` and the
`.swiftlint.yml` `r3_jsonserialization_boundary` regex. **Collision (identified at
design time):** `Engine/InkEngine.swift:1056` already uses
`JSONDecoder().decode(StoryState.self, …)` for save/restore — an ADR-003 Codable
concern, *not* Ink-format parsing. A naive `JSONDecoder` regex whose `included`
scope covers `Engine/` would false-positive there. The DELIVER regex task MUST NOT
red that legitimate call site. Recommended resolution (default): keep
`JSONSerialization` banned across `Engine|Facade|Compiler`, and scope any added
`JSONDecoder` clause to **`Facade/` and `Compiler/` only** (not `Engine/`); the
StoryState save/restore stays a sanctioned ADR-003 exception. The `.swiftlint.yml`
edit is flagged as a required DELIVER task so CI keeps enforcing the boundary against
the new API.

---

## Alternatives Considered

### Option B — Manual numeric-token typing at the JSON layer

Parse the raw JSON tokens by hand (or post-process `JSONSerialization` output)
inspecting the literal form to decide int vs float vs bool.

**Evaluation**: Gives full control and is platform-stable in principle. But it
re-implements a JSON scalar tokenizer that `JSONDecoder` already provides correctly
and platform-uniformly, adding code surface and its own bug risk for zero benefit
over Option A. `JSONDecoder`'s single-value container *is* the token-driven typing
we want.

**Rejection rationale**: Reinvents a solved, standard-library capability; more code,
more risk, no correctness or portability gain over the chosen option.

### Option C — `#if os(...)` / `#if canImport` conditional classification path

Keep the CoreFoundation path on Apple platforms; use a different path only on Linux.

**Evaluation**: This is the **exact silent-divergence bug class the feature exists to
eliminate**. Two code paths for the same behaviour means the platforms can drift and
the drift is invisible on the Mac the fix is written on — reproducing the original
"works on my Mac" failure the JTBD calls out. It also doubles the test burden and
defeats the single-oracle strategy (ADR-014).

**Rejection rationale**: Introduces per-platform behaviour divergence — the precise
anti-goal. Forbidden by the Correctness quality attribute (platform-identical typing).

### Option D — `NSNumber.objCType` inspection

Replace `CFNumberGetType` with `objCType` character inspection to decide int vs
float vs bool.

**Evaluation**: Still routes through `NSNumber` bridging (the unreliable layer on
swift-corelibs-foundation) and inherits the `'c'` ambiguity — `objCType == "c"`
denotes both `Bool` and `Int8`/`char`, so bool-vs-int cannot be disambiguated
reliably. It is the same class of runtime-type-identity heuristic as the current
code, merely spelled differently.

**Rejection rationale**: Does not remove the `NSNumber`/CF dependency; `'c'`
Bool/Int8 ambiguity makes bool-vs-int classification unreliable — the same silent bug.

---

## Consequences

**Positive**:
- Number/bool/int typing is driven by the JSON token grammar, which is identical
  across Foundation implementations — the classification is platform-stable by
  construction (satisfies KPI-3, the Correctness quality attribute).
- Single code path for all platforms: no `#if`, no per-platform test matrix, one
  oracle (ADR-014).
- No new runtime dependency (`JSONDecoder` is Foundation, already present). The
  guardrail "no new external dependency" holds.
- The change is contained to `Decoder/`; `Engine/`, `Facade/`, `Compiler/` and the
  `NodeKind`/`ContainerNode` boundary are untouched. `InkDecoder` remains EXTEND, not
  a rewrite.
- The Earned-Trust probe extension (DD-4) makes the silent-mistyping failure refuse
  to start rather than render wrong text.

**Negative**:
- R3 must be reworded and the `.swiftlint.yml` regex updated (DELIVER task), with the
  `Engine/` StoryState save/restore collision handled as above — a small, precisely
  scoped enforcement change, not a behaviour change.
- `JSONSerialization` disappears from the codebase; the old R3 rule text (naming only
  `JSONSerialization`) would go vacuous if not generalized — hence the mandatory
  rewording.

**Enforcement / test obligation**:
- US-01 (walking skeleton) decodes The Intercept on Linux and asserts int/float/bool
  node tags identical to the committed macOS fixture (zero misclassifications).
- Targeted float/int/bool decode-parity assertions (ADR-014 DD-2) guard KPI-3 directly.
- The generalized R3 SwiftLint rule keeps the Ink-decoding boundary enforced against
  `JSONDecoder`, with the ADR-003 StoryState exception documented.
