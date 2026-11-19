# ADR-023: JSON Number Typing by Token Text — Hand-Written Ink JSON Reader

**Status**: Accepted (maintainer, 2026-11-19 — option C1(a))
**Date**: 2026-11-19
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)
**Feature**: reference-fidelity-backlog (issue #37, part 1)
**Supersedes**: the *mechanism* of ADR-013 (`JSONDecoder` + Bool→Int→Double decode order). ADR-013's goal, platform-identical scalar typing, and its Earned-Trust probe stand.

---

## Context

ADR-013 replaced the CoreFoundation type-identity classification with `JSONDecoder` and a
custom `Decodable` that tries Bool, then Int, then Double. It rejected "manual numeric-token
typing" (its Option B) as reinventing a capability `JSONDecoder` already had.

Issue #37 shows that capability is missing. `JSONDecoder` decodes the token `2.0` as `Int` 2,
because the value is exactly representable. inklecate writes float literals as `1.0`, `2.0`,
so `1.0 / 3` becomes integer division (`0`) and `7 / 2.0` becomes `3`. This affects every story
loaded from JSON that uses a whole-number float literal. `JSONDecoder` does not expose a
number's text, so no decode order can recover it.

**Reference.** `SimpleJson.cs` is a hand-written reader. A number token containing `.`, `e`
or `E` is a float; anything else is an int (~225-245).

## Decision

1. **Replace the parsing mechanism inside `Decoder/`** with a small hand-written reader over
   the input bytes. It produces the existing `InkJSONValue` (object, array, string, bool,
   int, double, null). The number rule is SimpleJson's: float if and only if the token
   contains `.`, `e` or `E`.
2. **The surface is unchanged.** `InkJSONValue`, `ContainerNode`, `NodeKind` and
   `InkDecoder.decode(_:)` stay as they are.
3. **Linux portability still holds, more strongly.** The reader is pure Swift over `[UInt8]`.
   It uses no Foundation JSON implementation, no `NSNumber` and no CoreFoundation, so it
   cannot differ between swift-corelibs-foundation and Apple Foundation. ADR-013's
   correctness argument (typing driven by token grammar, not runtime type identity) now holds
   by construction, not by trusting `JSONDecoder`'s behaviour.
4. **Earned Trust.** The `InkDecoder.probe()` scalar fixture gains `2.0` (must be a float) and
   `1e2` (must be a float), next to `2.5`, `true` and `42`. Drift refuses to start with
   `StoryError.decoderProbeFailure`.
5. **Boundary R3 is unchanged.** Ink-format JSON parsing stays confined to `Decoder/`. The
   `r3_jsondecoder_boundary` rule keeps guarding `Facade/` and `Compiler/`; the ADR-003
   `StoryState` save/restore exception stays.
6. **Malformed input still throws** `InkDecodeError.malformedJSON`. Unicode escapes and string
   escapes follow JSON (RFC 8259).

## Alternatives Considered

- **`JSONSerialization` + `NSNumber.objCType`** (ADR-013's Option D). **Rejected**, for the
  reasons ADR-013 gave: it brings back `NSNumber` bridging, which is unreliable on
  swift-corelibs-foundation, and the `'c'` Bool/Int8 ambiguity.
- **Pre-scan the raw bytes for float tokens and map them onto the `JSONDecoder` tree.**
  **Rejected**: it is a second tokenizer anyway, plus an order mapping that breaks on
  unordered object keys.
- **Keep `JSONDecoder` and document the difference.** **Rejected**: values change, not just
  the printing. This is the most serious defect in the backlog.

## Consequences

**Positive**
- Whole-number floats keep their type, and float arithmetic from JSON matches the reference.
- One decode path on every platform, with no Foundation JSON dependency left in the hot path.

**Negative**
- About 150 lines of owned parsing code. This is mitigated by the probe and the decode-parity
  fixtures (ADR-014), which assert int, float and bool typing on macOS and Linux.
- A story whose output changes (it used to print integer results) needs a release-note
  callout.
