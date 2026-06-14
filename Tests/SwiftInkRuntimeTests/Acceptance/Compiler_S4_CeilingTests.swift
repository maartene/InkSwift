// @us-05 @real-io @kpi-1
//
// S4 / US-05 — compile the full supported ceiling: inline / block / switch-style
// conditionals, functions `=== f() ===` + inline calls `{f()}`, tunnels
// `-> k ->`, reference parameters `ref x`, and tags `#tag`
// (matrix rows 22-24, 29-35). Native compile plays identical to the inklecate
// oracle up to The Intercept ceiling.
//
// Driving port: InkCompiler.compile(source:). RED until DELIVER S4.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler S4 — Supported Ceiling (conditionals, functions, tunnels, ref params, tags)")
struct Compiler_S4_CeilingTests {

    @Test func `a story exercising the full supported ceiling compiles and plays, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-ceiling")

        #expect(result.native == result.oracle)
    }

    @Test func `inline function calls, tunnels and ref-param mutation match the oracle`() throws {
        // double(2) → 4 strength; tunnel detour runs then returns; raise(ref force)
        // mutates the caller's variable so "Force is now 3". The whole sequence
        // matching the oracle proves all four mechanisms compile correctly.
        let result = try CompilerOracle.compileAndPlay("compile-ceiling")

        #expect(result.native == result.oracle)
        #expect(result.oracle.contains { $0.contains("strength") })
        #expect(result.oracle.contains("Force is now 3."))
    }

    // End-to-end ceiling oracle: The Intercept is the comprehensive supported-set
    // story (existing fixture). DESCOPED (user-approved 2026-06-14): TheIntercept.ink
    // line 86 uses a variable-text sequence `{|...|}`, which is OUTSIDE the locked
    // supported set (matrix rows 25-28) and is correctly rejected by the compiler
    // (S6 / DDD-12 / DDD-8). The runtime plays it via inklecate's visit-count
    // lowering, so this is a documented compiler/runtime parity gap, NOT a defect —
    // see feature-delta `DELIVER / [WHY] Upstream Issues`. Re-enable this test if/when
    // deterministic variable-text sequence codegen is added to the compiler.
    @Test(.disabled("Descoped: TheIntercept uses an unsupported variable-text sequence (line 86); rejected by S6/DDD-12. Documented parity gap — see DELIVER Upstream Issues."))
    func `The Intercept compiles natively and plays identical to the inklecate oracle`() throws {
        let oracleJSON = try CompilerOracle.oracleJSON("TheIntercept")
        let interceptScript = [0, 2, 1, 0, 0, 1, 2, 0, 1, 0]

        let oracleLines = try CompilerOracle.play(
            Story(json: oracleJSON), choiceScript: interceptScript, maxLines: 100
        )

        let source = try CompilerOracle.source("TheIntercept")
        let nativeStory = Story(blueprint: try InkCompiler.compile(source: source))
        let nativeLines = try CompilerOracle.play(
            nativeStory, choiceScript: interceptScript, maxLines: 100
        )

        #expect(nativeLines == oracleLines)
    }
}
