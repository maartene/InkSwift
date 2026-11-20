# ADR-024: Numeric Semantics — Double Arithmetic, 32-bit Float Printing, C#-Style Coercion

**Status**: Accepted (maintainer, 2026-11-19 — overrides the proposed 32-bit rounding). **Implemented**: printing (§2) in **2.1.2** (step 01-02); coercion and casts (§3-4) in **2.1.6** (step 03-01).
**Date**: 2026-11-19
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)
**Feature**: reference-fidelity-backlog (issue #37 part 2, issue #36 casts, finding F1)
**Amends**: no ADR. No ADR has decided `InkValue`'s arithmetic, coercion or printing. ADR-003 covers its save encoding, which is unchanged.

---

## Context

The C# runtime's float values are 32-bit (`float`). Arithmetic is 32-bit, and values print
with `ToString(CultureInfo.InvariantCulture)`. That gives `2`, `0.3` and `0.33333334`.

InkSwift stores `InkValue.float(Double)`, computes in `Double` and prints with `String(f)`
(`StoryState.swift:91`). That gives `2.0`, `0.30000000000000004` and `0.3333333333333333`.

Related defects found in the same model:

- **FLOOR and CEILING.** For a float, they return `.int` (`StoryState.swift:144-156`); C#
  returns a float (`NativeFunctionCall.cs:382-383`). So `CEILING(1.2) / 3` is integer
  division. This is the actual cause of upstream `TestFloorCeilingAndCasts` failing in
  runtime mode.
- **Equality.** `==` and `!=` use `InkValue`'s synthesised `Equatable`
  (`TreeWalker.swift:327-328`), so `1 == 1.0` is false.
- **MIN and MAX** return their operand unconverted. C# coerces both operands of every binary
  native function to one type first (`CoerceValuesToSingleType`): bool → int → float → string.

## Decision

1. **Storage and arithmetic stay `Double`.** There is no 32-bit rounding. The save wire,
   `getVariable`'s `Double`, and host expectations are all unchanged.
2. **Printing only.** A float prints as the shortest round-trip form of its 32-bit value
   (Swift `Float(value).description`), without a trailing `.0`. So `2.0` prints `2`, `0.1 + 0.2`
   prints `0.3`, `1.0 / 3` prints `0.33333334`, and `2.0 / 3` prints `0.6666667`. This is a
   single formatting function used by `out`, string concatenation and choice text.
3. **One coercion point for binary operators.** Every binary native function first coerces
   both operands to the *higher* of their two types, in C#'s `ValueType` order:
   bool < int < float < string (`CoerceValuesToSingleType`, `NativeFunctionCall.cs:231-250`).
   - **int and float**: both become float. `==` and `!=` compare the coerced values, so
     `1 == 1.0` is true. `MIN`, `MAX`, the comparisons and the arithmetic all go through
     this point.
   - **string and number** (or string and bool): both become strings, with the number
     printed by the formatting function in §2. So `"a" + 1` concatenates to `"a1"`; today
     `adding` falls through to `.float` and prints `1` (`StoryState.swift:98-103`). `==`
     and `!=` compare the strings.
   - C# defines no other string operators except `?` and `!?` (ADR-025). For an operator
     with no string form (`-`, `*`, `<`, …) on a coerced string, InkSwift's behaviour is a
     DELIVER probe against C#, which raises a runtime error there.
   - **bool**: coerced to int when the other operand is an int or a float.
4. **Casts match C#:**
   - `FLOOR` and `CEILING` of a float return a float.
   - `INT` truncates to an int.
   - `FLOAT` returns a float.
   - On an int, `FLOOR`, `CEILING` and `INT` are the identity.
5. **#27 hook (3.0.0).** Each typed `setVariable` overload enters `InkValue` through its own
   constructor (`.int`, `.float(Double)`, `.bool`, `.string`, and later a divert-target case).
   Host values do not go through the binary-operator coercion point; that point applies
   only when story operators later combine the stored value with others. No rounding is
   involved.

## Deliberate divergence (to record in `docs/reference/differences-from-inklecate.md` during DELIVER)

Because arithmetic stays 64-bit, results that 32-bit arithmetic would round differently can
print or compare differently. Examples:

- long accumulated sums;
- comparisons near a 32-bit rounding boundary (`0.1 + 0.2 == 0.3` is true in 32-bit and
  false in 64-bit);
- integers above 2^24 converted to float.

**Reasoning (maintainer).** `Double` is Swift's natural floating type and what hosts read
through `getVariable`. 32-bit rounding everywhere would add a normalisation step at every float
producer, for gains only in edge cases that real stories rarely reach. Printing, which every
story shows, matches.

## Alternatives Considered

- **Round every float to 32-bit at one normalisation point, keeping `Double` storage.** This
  is the originally proposed C1(b): the most faithful option, with no API change. **Rejected**
  by the maintainer (reasoning above).
- **Store `InkValue.float(Float)`.** Fully faithful, but `getVariable` would return `Float`
  and break hosts' `as? Double`. That is a breaking change, so it would have to wait for
  3.0.0. **Rejected.**
- **Keep `String(Double)` printing.** **Rejected**: every whole-number float prints `2.0`, and
  sums print binary noise.

## Consequences

**Positive**
- Printed floats match inklecate in the common cases.
- Casts and mixed int/float operations follow the reference, which unblocks
  `TestFloorCeilingAndCasts` and `TestArithmetic` (runtime). The probe confirms.

**Negative**
- A documented arithmetic-precision divergence remains.

**Release-note callout**:
- float values now print as inklecate prints them;
- `FLOOR`/`CEILING` results keep a fractional type;
- `1 == 1.0` is true;
- string + number concatenates (`"a" + 1` is `a1`).

**Resolved in DELIVER (01-02), see Implementation Notes** (was open, not a blocker): the exponent spelling. Swift prints `1e+20`; .NET may
print `1E+20`. Probe against inklecate, and add the result to the differences doc if they
diverge.

## Implementation Notes (finalize, 2026-11-20)

- **§2 printing** shipped in **2.1.2** (01-02), ahead of ADR-023 (U1). **Exponent spelling
  probe resolved**: inklecate prints .NET "G" layout (`1E+20`, `1E-07`, `Infinity`,
  `100000000`), and InkSwift now matches it. Locale (inkle/ink#916): InkSwift always prints
  `.`; recorded in the differences doc.
- **§3-4 coercion and casts** shipped in **2.1.6** (03-01). **§3 probe resolved** (U8): an
  operator with no string form on a string operand appends C#'s
  "Cannot perform operation '<op>' on String" to `currentErrors` and ends the flow through
  `forceEnd()`.
- The deliberate precision divergence (`{0.1 + 0.2 == 0.3}` is true on inklecate, false here)
  is pinned by a test and listed in the differences doc.
