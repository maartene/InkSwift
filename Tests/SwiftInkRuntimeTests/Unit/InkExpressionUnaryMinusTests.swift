// Unit-level pins for prefix `-` (arithmetic negation) in the expression parser.
// It lowers to the runtime native function `_` (Negate) — deliberately distinct
// from binary `-` subtraction, matching `NativeFunctionCall.Negate` in the
// reference runtime.
//
// The played-output equivalence lives in `Compiler_S2_UnaryMinusTests`; these
// assert the AST shape so a regression points at the parser.

import Testing
@testable import SwiftInkRuntime

@Suite("InkExpressionParser — unary minus")
struct InkExpressionUnaryMinusTests {

    // U1 — a negated literal. This compiler does not constant-fold, so it lowers
    // to `5, "_"` rather than the literal -5 that inklecate emits; the played
    // value is the same.
    @Test func `parses a negated literal as a negate unary`() throws {
        #expect(try InkExpressionParser.parse("-5") == .unary(op: "_", operand: .intLiteral(5)))
    }

    // U2 — a negated variable, the form that actually needs the runtime operator.
    @Test func `parses a negated variable as a negate unary`() throws {
        #expect(try InkExpressionParser.parse("-x")
            == .unary(op: "_", operand: .variableReference("x")))
    }

    // U3 — the prefix binds to a parenthesised sub-expression as a whole.
    @Test func `parses a negated parenthesised expression`() throws {
        #expect(try InkExpressionParser.parse("-(a + b)") == .unary(
            op: "_",
            operand: .binary(op: "+", left: .variableReference("a"), right: .variableReference("b"))
        ))
    }

    // U4 — binary minus followed by a prefix minus: `2 - -3` is subtraction of a
    // negation, NOT a `--` token. Pins that adding the prefix did not change how
    // binary subtraction tokenizes.
    @Test func `distinguishes binary minus from a following prefix minus`() throws {
        #expect(try InkExpressionParser.parse("2 - -3") == .binary(
            op: "-",
            left: .intLiteral(2),
            right: .unary(op: "_", operand: .intLiteral(3))
        ))
    }

    // U5 — the prefix binds tighter than `*`, so `-i * 2` is `(-i) * 2`
    // (inklecate lowers it as `{"VAR?":"i"},"_",2,"*"`).
    @Test func `binds tighter than multiplication`() throws {
        #expect(try InkExpressionParser.parse("-i * 2") == .binary(
            op: "*",
            left: .unary(op: "_", operand: .variableReference("i")),
            right: .intLiteral(2)
        ))
    }

    // U6 — negation composes with itself and with logical-not, each keeping its
    // own native symbol (`_` vs `!`).
    @Test func `composes with itself and with logical not`() throws {
        #expect(try InkExpressionParser.parse("--x")
            == .unary(op: "_", operand: .unary(op: "_", operand: .variableReference("x"))))
        #expect(try InkExpressionParser.parse("!-x")
            == .unary(op: "!", operand: .unary(op: "_", operand: .variableReference("x"))))
    }
}
