// @us-03 @real-io @kpi-1
//
// VT3 / US-03 (slice-03) — compile and play the CYCLE variable-text form `{&a|b}`
// (matrix row 26): N stages, advance one per visit, WRAP to the first via modulo
// over the stage count — cycling forever.
//
// Lowering (ground truth): OP=%, BOUND=S (stage count), no appended stage. The
// ONLY difference from a sequence is wrap-via-modulo vs clamp. Boundary fixtures
// (OQ-1): 2-stage wrap and the 4-stage modulo wrap (>2 stages, the off-by-one
// risk at the wrap boundary).
//
// Correctness gate: hermetic Level-1 execution-equivalence (native vs committed
// inklecate oracle, both via the pure-Swift `Story`). Driving port:
// InkCompiler.compile(source:).
//
// DISABLED until DELIVER slice-03 lands the wrap parameter on the parametrized
// lowering; that step removes `.disabled`.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler VT3 — Cycle variable text ({&a|b}, modulo wrap)")
struct Compiler_VT3_CycleTests {

    // Scenario: A two-stage cycle wraps forever, matching the oracle.
    @Test func `a two-stage cycle wraps forever, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-cycle-two", choiceScript: [0])

        #expect(result.native == result.oracle)
        #expect(Array(result.native.prefix(4)) == ["heads", "tails", "heads", "tails"])
    }

    // Scenario: A four-stage cycle wraps via modulo over >2 stages, matching the
    // oracle (no off-by-one at the wrap boundary).
    @Test func `a four-stage cycle wraps via modulo with no off-by-one, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-cycle-four", choiceScript: [0])

        #expect(result.native == result.oracle)
        #expect(Array(result.native.prefix(5)) == ["Spring", "Summer", "Autumn", "Winter", "Spring"])
    }
}
