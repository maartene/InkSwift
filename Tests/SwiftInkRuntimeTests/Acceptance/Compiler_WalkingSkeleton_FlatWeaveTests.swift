// @walking_skeleton @driving_port
//
// WALKING SKELETON (native-ink-compiler) — promoted from the validated weave
// probe (SPIKE Phase 3 / ADR-008). ONE end-to-end slice proving the weave
// pipeline wires through the REAL driving port `InkCompiler.compile(source:)`:
// the FLAT single-level weave (two bracketed once-only choices + one trailing
// gather, falling to `-> END`) compiles natively and plays line-for-line /
// choice-for-choice identical to the committed inklecate oracle along script [0].
//
// Deliberately thin: nested / labeled / sealed weaves, sticky `+`, plain-label
// echo, conditional choices and read counts are OUT of scope (DELIVER S3) and
// may remain RED. This test must be GREEN.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler walking skeleton — flat weave")
struct Compiler_WalkingSkeleton_FlatWeaveTests {

    @Test func `the flat weave compiles via the real driving port and plays oracle-identical along script zero`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-weave-flat", choiceScript: [0])

        #expect(result.native == result.oracle,
                "flat weave native compile diverged from the inklecate oracle")
    }
}
