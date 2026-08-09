// @regression @real-io @kpi-1
//
// VT4 — regression guard: a LEADING ALTERNATIVE MARKER inside `{ … }` wins over
// the inline-conditional `:` and the alternative `|`.
//
// Ground truth (verified against inklecate 1.2.1 — see the committed
// `compile-brace-markers.ink.json` oracle): the marker is read first, after any
// leading whitespace, and classifies the WHOLE body:
//   {!a: x}   → once-only over the single stage "a: x"   (NOT `!a` ? x : "")
//   { !a: q } → same; whitespace before the marker is skipped
//   {!a}      → once-only over "a"                       (NOT the boolean !a)
//   {&a: y}   → cycle over "a: y"
//   {\!a: …}  → escaped: plain sequence, first char literal
// while an UNMARKED body keeps its existing meaning:
//   {a: yes|no}   → inline conditional
//   {(!a): yes|no} → inline conditional on a parenthesised logical-not
//
// Defect this pins (fixed 2026-08-09): `InkParser.scanBraceSegment` tested for a
// top-level `:` before the leading marker, so every marked body carrying a `:` —
// and every marked body with neither `:` nor `|` — was misclassified. The `!`
// forms silently produced the wrong output rather than failing; `{&a: x}` threw
// `unexpectedToken("&")`. Shuffle `{~…}` is unaffected: it is rejected upstream
// by `UnsupportedConstructDetector`, which is pinned by VT0 and by the unit-level
// guard in `InkParserBraceMarkerTests`.
//
// Correctness gate: hermetic Level-1 execution-equivalence — native compile vs the
// committed inklecate `.ink.json` oracle, both played through the pure-Swift
// `Story`. The fixture is played TWICE (sticky `Again` choice) so once-only,
// cycle and sequence are distinguishable: a spent once-only blanks, a cycle
// repeats, a sequence advances.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler VT4 — Leading brace marker beats the conditional colon")
struct Compiler_VT4_BraceMarkerPrecedenceTests {

    // Scenario: every marked and unmarked brace form plays identically to the
    // oracle across two visits.
    @Test
    func `a leading alternative marker classifies the whole brace body, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-brace-markers", choiceScript: [0, 1])

        #expect(result.native == result.oracle)
    }

    // Scenario: first visit — each form emits its opening stage. Asserted
    // explicitly so a regression names the offending form instead of only
    // reporting "two arrays differ".
    @Test
    func `the first visit emits each form's opening stage, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-brace-markers", choiceScript: [0, 1])

        #expect(result.oracle.prefix(8) == [
            "Once: a: x",              // marker beats `:` — NOT the branch "x"
            "Spaced: a: q",            // whitespace before the marker is skipped
            "OnceBare: a",             // marker with neither `:` nor `|` — NOT "true"
            "Cycle: a: y",             // `&` marker beats `:` too
            "Seq: First",              // unchanged: marker + `|`, already correct
            "Escaped: !a: NotEscaped", // `\` keeps the `!` literal, plain sequence
            "Cond: no",                // unmarked: still an inline conditional
            "ParenNot: yes",           // parenthesised `!` still an expression
        ])
        #expect(result.native == result.oracle)
    }

    // Scenario: second visit — the modes diverge, which is what proves the body
    // was classified as an alternative rather than a conditional. A conditional
    // would repeat its branch unchanged on every visit.
    @Test
    func `the second visit blanks once-only forms while cycles repeat, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-brace-markers", choiceScript: [0, 1])

        #expect(result.oracle.suffix(8) == [
            "Once:",                   // once-only spent — blank, not "x" again
            "Spaced:",                 // ditto
            "OnceBare:",               // ditto
            "Cycle: a: y",             // cycle wraps — repeats its single stage
            "Seq: Second",             // sequence advances
            "Escaped: Other",          // escaped sequence advances
            "Cond: no",                // conditional is visit-independent
            "ParenNot: yes",           // expression is visit-independent
        ])
        #expect(result.native == result.oracle)
    }
}
