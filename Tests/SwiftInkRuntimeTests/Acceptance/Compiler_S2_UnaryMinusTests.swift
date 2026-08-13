// @regression @real-io @kpi-1
//
// S2 regression — unary minus (arithmetic negation).
//
// `~ x = -5` threw `unexpectedToken("-")`: the tokenizer emitted a `-` token but
// `parseOperand` had no prefix-minus branch (only `not` / `!`), and the engine
// had no `_` native operator at all — so even a correct inklecate json could not
// have been played.
//
// Ground truth (inklecate 1.2.1, see the committed oracle):
//   -5        constant-folded to the literal -5   (no operator emitted)
//   -i        {"VAR?":"i"},"_"                    (Negate, "_" — distinct from
//                                                  binary "-" subtraction)
//   -(i + 1)  {"VAR?":"i"},1,"+","_"
//   2 - -3    2,-3,"-"                            (the -3 folded too)
//   -i * 2    {"VAR?":"i"},"_",2,"*"              (unary binds tighter than *)
//
// The reference runtime defines Negate for int and float only
// (`NativeFunctionCall.cs`: `AddIntUnaryOp(Negate, x => -x)` and the float pair).
//
// This compiler does NOT constant-fold: `-5` lowers to `5,"_"`. That is a
// structural difference from the oracle json, not a behavioural one — the played
// output is identical, which is what the equivalence gate checks.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler S2 — Unary minus")
struct Compiler_S2_UnaryMinusTests {

    // Scenario: every negation form plays identically to the oracle.
    @Test func `unary minus in all its forms matches the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-unary-minus")

        #expect(result.native == result.oracle)
    }

    // Scenario: the integer results are asserted explicitly so a regression names
    // the offending form. The float line is checked separately because its
    // rendering is this runtime's concern and is identical on both paths.
    @Test func `each negation form produces the expected value`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-unary-minus")

        #expect(result.oracle.contains("A: -5"))   // negated literal
        #expect(result.oracle.contains("B: -7"))   // negated variable
        #expect(result.oracle.contains("D: -8"))   // negated parenthesised sum
        #expect(result.oracle.contains("E: 5"))    // subtraction of a negative
        #expect(result.oracle.contains("G: -14"))  // unary binds tighter than *
        #expect(result.oracle.contains("H: -7"))   // negation inline in content
        #expect(result.oracle.contains { $0.hasPrefix("C: -2") })  // negated float
        #expect(result.native == result.oracle)
    }
}
