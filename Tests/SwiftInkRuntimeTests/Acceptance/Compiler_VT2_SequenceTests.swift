// @us-02 @real-io @kpi-1
//
// VT2 / US-02 (slice-02) — compile and play the SEQUENCE variable-text form
// `{a|b|c}` (matrix row 25): N stages, advance one per visit, CLAMP on the last.
//
// Lowering (ground truth): OP=MIN, BOUND=S−1 (last index), no appended stage.
// Boundary fixtures (OQ-1): 3-stage clamp-at-last and the 2-stage sequence (the
// boundary that must NOT be confused with the once-only form — slice-01).
//
// The mixed fixture discharges DESIGN OQ-3 (promoted to a DISTILL acceptance
// criterion): a body mixing a variable-text group and a conditional must produce
// NO stage-container key collision (distinct `seq{N}-*` vs `cond{N}-*` prefixes)
// and play oracle-identically.
//
// Correctness gate: hermetic Level-1 execution-equivalence (native vs committed
// inklecate oracle, both via the pure-Swift `Story`). Driving port:
// InkCompiler.compile(source:).
//
// DISABLED until DELIVER slice-02 lands the parametrized sequence lowering; that
// step removes `.disabled`.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler VT2 — Sequence variable text ({a|b|c}, clamp-at-last)")
struct Compiler_VT2_SequenceTests {

    // Scenario: A three-stage sequence advances then clamps, matching the oracle.
    @Test func `a three-stage sequence advances then clamps on the last stage, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-seq-three", choiceScript: [0])

        #expect(result.native == result.oracle)
        #expect(Array(result.native.prefix(4)) == ["red", "green", "blue", "blue"])
    }

    // Scenario: A two-stage prose sequence renders each stage then clamps —
    // the boundary vs the once-only form.
    @Test func `a two-stage sequence renders each stage then clamps, distinct from once-only`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-seq-two", choiceScript: [0])

        #expect(result.native == result.oracle)
        #expect(Array(result.native.prefix(3)) == ["Day.", "Night.", "Night."])
    }

    // Scenario (OQ-3 / DISTILL AC): a body mixing variable text and a conditional
    // produces no key collision and plays oracle-identically.
    @Test func `a body mixing variable text and a conditional has no key collision and matches the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-mixed", choiceScript: [0])

        #expect(result.native == result.oracle)
        #expect(Array(result.native.prefix(3)) == [
            "First time. The sign glows red.",
            "Back again. The sign glows green.",
            "Back again. The sign glows blue.",
        ])
    }
}
