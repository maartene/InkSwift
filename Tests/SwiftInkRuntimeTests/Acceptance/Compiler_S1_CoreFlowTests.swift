// @us-02 @real-io @kpi-1
//
// S1 / US-02 — compile a linear core-flow story: knots, stitches, divert forms
// (absolute + stitch-relative), and glue (matrix rows 1-5, 15). Native compile
// plays line-for-line identical to the inklecate oracle.
//
// Driving port: InkCompiler.compile(source:). RED until DELIVER S1.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler S1 — Core Flow (knots, stitches, diverts, glue)")
struct Compiler_S1_CoreFlowTests {

    @Test func `a multi-knot linear story compiles and plays, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-linear-flow")

        #expect(result.native == result.oracle)
    }

    @Test func `glue joins lines exactly as the oracle produces them`() throws {
        // The fixture joins "You step inside." and "The room is cold..." with <>.
        // Equivalence to the oracle proves glue is encoded identically.
        let result = try CompilerOracle.compileAndPlay("compile-linear-flow")

        #expect(result.native == result.oracle)
        #expect(result.native.contains { $0.contains("You step inside.") })
    }
}
