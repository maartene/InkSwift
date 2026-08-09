// @regression @real-io @kpi-1
//
// S2 regression — a comparison operator inside a `~` logic line must not be
// mistaken for the assignment operator.
//
// `logicKind` classified a line as an assignment with `trimmedBody.contains("=")`
// and `splitAssignment` split at the FIRST `=`, so `~ describe(x >= y)` was read
// as an assignment to the bogus target `"describe(x >"`. inklecate 1.2.1 compiles
// and runs the same source (see the committed oracle), so this is a false
// rejection, not an unsupported construct.
//
// The companion unit suite (`InkParserAssignmentTargetTests`) pins the
// classification and the located-error cases; this asserts played-output
// equivalence for the forms that must RUN.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler S2 — Comparison operators inside logic lines")
struct Compiler_S2_ComparisonArgumentTests {

    // Scenario: a function call whose argument is a comparison RUNS — observed via
    // the counter it increments — and a genuine assignment with a comparison
    // right-hand side still assigns.
    //
    // The callee mutates a global rather than printing, on purpose: text output
    // from a void function invoked as a `~` statement is dropped by the engine for
    // the first such call. That reproduces on the ORACLE json too (i.e. with no
    // native compile involved), so it is a separate pre-existing defect and is
    // deliberately not entangled with this regression.
    @Test
    func `comparisons in call arguments and assignment right-hand sides match the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-comparison-argument")

        #expect(result.native == result.oracle)
        #expect(result.oracle == ["Calls: 2", "X: true"])
    }
}
