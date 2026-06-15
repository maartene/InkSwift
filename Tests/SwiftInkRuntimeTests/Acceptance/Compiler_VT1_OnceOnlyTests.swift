// @us-01 @real-io @kpi-1
//
// VT1 / US-01 (slice-01) — compile and play the ONCE-ONLY variable-text form:
// shorthand `{!a|b}` and the bare `{|x|}` spelling (matrix row 27).
//
// Lowering (ground truth, verified against inklecate — see feature-delta DESIGN
// "Lowering Specification"):
//   once `{!a|b}`  = sequence + ONE appended empty stage; OP=MIN, BOUND=S (new
//                    last index) → advance then BLANK.    e.g. `{!x|}` → [x, "", ""]
//   bare `{|x|}`   = NOT special — a plain sequence; `|`-split → ["", "x", ""],
//                    OP=MIN, clamp.  Text appears on the SECOND visit, then silent.
//
// NOTE (upstream clarification): DISCUSS US-01 domain-example 3 said the bare
// `{|x|}` "lowers identically to the `!` spelling." The inklecate ground truth
// shows they are NOT identical — `{!x|}` emits on visit 0, bare `{|x|}` emits on
// visit 1 (leading empty stage). The oracle is authoritative; these tests assert
// the real per-spelling shape. Recorded in feature-delta DISTILL upstream issues.
//
// Correctness gate: hermetic Level-1 execution-equivalence — native compile vs the
// committed inklecate `.ink.json` oracle, both played through the pure-Swift
// `Story` (no inklecate, no JS bridge). Driving port: InkCompiler.compile(source:).
//
// DISABLED until DELIVER slice-01 lands `VariableTextEmitter` once-only lowering +
// the `UnsupportedConstructDetector` gate change; that step removes `.disabled`.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler VT1 — Once-only variable text ({!a|b} / {|x|})")
struct Compiler_VT1_OnceOnlyTests {

    // Scenario: A once-only form plays its text exactly once, matching the oracle.
    @Test
    func `a once-only form emits its text exactly once then falls silent, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-once-sticky", choiceScript: [0])

        #expect(result.native == result.oracle)
        #expect(result.native == ["The lock clicks open."])
    }

    // Scenario: The bare once-only spelling lowers as a plain sequence (leading
    // empty stage), matching the oracle — distinct from the "!" spelling.
    @Test
    func `the bare once spelling lowers to a leading-empty sequence, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-once-bare", choiceScript: [0])

        #expect(result.native == result.oracle)
        #expect(result.native == ["The corridor falls quiet."])
    }
}
