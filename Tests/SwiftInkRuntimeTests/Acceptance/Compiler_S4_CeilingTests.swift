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
    // story (existing fixture). It was DESCOPED (user-approved 2026-06-14) solely
    // because TheIntercept.ink line 86 uses a once-only variable-text form
    // `{|I rattle...|}` (matrix row 27), then outside the supported set.
    //
    // @us-04 @kpi-1 @kpi-2 (compiler-variable-text US-04 — distinct from this
    // file's @us-05 native-ink-compiler ceiling tests above).
    // This is the US-04 acceptance test for the `compiler-variable-text` feature.
    // Slices 01-03 lowered the variable-text forms (rows 25-27), so the line-86
    // once-only form `{|...|}` that originally caused the descope now compiles.
    //
    // STILL BLOCKED (slice-04 RED finding, 2026-06-15): re-enabling the trait
    // surfaces TWO compiler gaps unrelated to variable text and OUT OF SCOPE for
    // this feature — the 2026-06-14 descope premise (line-86 variable-text only)
    // was incomplete:
    //   1. `not` unary operator in conditions (50 uses, e.g. `{not think:...}`) —
    //      runtime already supports unary `!`; mechanical compiler-only fix.
    //   2. dotted read-count references in conditions, e.g.
    //      `{harris_demands_component.cant_talk_right: ...}` → inklecate `CNT?`
    //      addressing of a NAMED stitch — a substantial compiler capability that
    //      belongs to native-ink-compiler, not this slice.
    // Escalated to nw-solution-architect (re-scope) + nw-acceptance-designer
    // (AT re-enable timing). Trait stays `.disabled` until those land; the AT
    // genuinely fails and must NOT be weakened.
    @Test(.disabled("BLOCKED slice-04: TheIntercept native compile needs out-of-scope compiler features (not-unary operator + dotted read-count addressing of named stitches); descope premise falsified. Escalated to architect/acceptance-designer."))
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
