// @us-03 @real-io @kpi-1
//
// S2 / US-03 — compile a state-driven story: VAR globals, CONST (with the
// COMPILE-TIME inlining the runtime assumes inklecate did — D6), temp vars,
// assignment, variable-read-in-output, arithmetic/logic operators, and string
// interpolation (matrix rows 16-21, 31). Native compile plays identical to the
// inklecate oracle, which proves the D6 CONST-inlining obligation is honored
// (its omission would surface here as an oracle divergence).
//
// Driving port: InkCompiler.compile(source:). RED until DELIVER S2.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler S2 — Variables & Expressions (VAR, CONST, temp, operators)")
struct Compiler_S2_VariablesTests {

    @Test func `a state-driven story compiles and plays, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-variables")

        #expect(result.native == result.oracle)
    }

    @Test func `CONST inlining and arithmetic render values identical to the oracle`() throws {
        // The fixture prints `{score + BONUS}` (3 + CONST 10 → 13) and
        // `{2 + 3 * 4}` (→ 14). Equivalence proves CONSTs are inlined and
        // operators evaluate as inklecate computes them.
        let result = try CompilerOracle.compileAndPlay("compile-variables")

        #expect(result.native == result.oracle)
        #expect(result.oracle.contains("Total: 13"))
        #expect(result.oracle.contains("Math: 14"))
    }

    @Test func `compound assignment operators reassign the variable, matching the oracle`() throws {
        // Regression for the compound-assignment operators (`+=`, `-=`) being
        // parsed but never taking effect: `counter` starts at 10, `+= 5` -> 15,
        // `-= 3` -> 12, and — inside the picked choice — `+= 100` -> 112. Only
        // `+=`/`-=` are exercised: `*=`/`/=`/`%=` were verified against
        // inklecate 1.2.1 to be rejected at compile time (not real Ink syntax),
        // so there is nothing to desugar for them.
        let result = try CompilerOracle.compileAndPlay("compile-compound-assignment", choiceScript: [0])

        #expect(result.native == result.oracle)
        #expect(result.oracle.contains("After plus: 15"))
        #expect(result.oracle.contains("After minus: 12"))
        #expect(result.oracle.contains("Choice counter: 112"))
    }
}
