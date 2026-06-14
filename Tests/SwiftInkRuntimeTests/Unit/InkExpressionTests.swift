// Test Budget: 3 distinct behaviors x 2 = 6 max unit tests (Mandate 1).
// Behaviors for the 02-01 expression substrate (enabling step — no S2 acceptance
// scenario flips GREEN here; full S2 GREEN is deferred to 02-02):
//   B1 — the Pratt sub-parser parses arithmetic with correct precedence
//        (`*` `/` `%` bind tighter than `+` `-`) into a typed expression AST.
//   B2 — RuntimeObjectEmitter lowers an expression to POSTFIX (RPN) runtime nodes:
//        operands depth-first then the operator; int/float literals lower to
//        .intValue/.floatValue and operators to .nativeFunction(symbol).
//   B3 — UNIT INVARIANT: a played inline integer arithmetic expression
//        `{2 + 3 * 4}` yields "14" (precedence correct) when run on the engine.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("InkExpressionParser — Pratt precedence-climbing")
struct InkExpressionParserTests {

    // B1a — multiplication binds tighter than addition: `2 + 3 * 4` parses as
    // `2 + (3 * 4)`, NOT `(2 + 3) * 4`.
    @Test func `parses multiplication as binding tighter than addition`() throws {
        let expression = try InkExpressionParser.parse("2 + 3 * 4")
        guard case let .binary(rootOp, left, right) = expression else {
            Issue.record("expected a binary root, got \(expression)")
            return
        }
        #expect(rootOp == "+")
        #expect(left == .intLiteral(2))
        #expect(right == .binary(op: "*", left: .intLiteral(3), right: .intLiteral(4)))
    }

    // B1b — additive operators are left-associative: `10 - 2 - 3` parses as
    // `(10 - 2) - 3`, so the right operand is the bare literal 3.
    @Test func `parses left-associative additive chain`() throws {
        let expression = try InkExpressionParser.parse("10 - 2 - 3")
        guard case let .binary(rootOp, left, right) = expression else {
            Issue.record("expected a binary root, got \(expression)")
            return
        }
        #expect(rootOp == "-")
        #expect(right == .intLiteral(3))
        #expect(left == .binary(op: "-", left: .intLiteral(10), right: .intLiteral(2)))
    }

    // B1c — a float operand parses to a float literal node.
    @Test func `parses a float literal operand`() throws {
        let expression = try InkExpressionParser.parse("1.5 + 2")
        guard case let .binary(_, left, _) = expression else {
            Issue.record("expected a binary root, got \(expression)")
            return
        }
        #expect(left == .floatLiteral(1.5))
    }

    // B1d — an escaped quote inside a string literal does NOT terminate the
    // scan; the inner escaped-quote characters are carried in the contents
    // rather than truncating at the first `\"`.
    @Test func `parses a string literal containing escaped quotes`() throws {
        let expression = try InkExpressionParser.parse(#""He said \"hello\"""#)
        #expect(expression == .stringLiteral(#"He said \"hello\""#))
    }
}

@Suite("RuntimeObjectEmitter — arithmetic expression lowering")
struct RuntimeObjectEmitterExpressionTests {

    // B2a — `{2 + 3 * 4}` lowers to the committed oracle postfix order:
    // ev, 2, 3, 4, *, +, out, /ev. Operands emit depth-first, then the operator;
    // literals → .intValue, operators → .nativeFunction.
    @Test func `lowers inline arithmetic to oracle postfix node order`() throws {
        let expression = try InkExpressionParser.parse("2 + 3 * 4")
        let nodes = RuntimeObjectEmitter.lowerInlineExpression(expression)

        #expect(describe(nodes) == ["ev", "int:2", "int:3", "int:4", "fn:*", "fn:+", "out", "/ev"])
    }

    // B2b — a float operand lowers to .floatValue carrying the operand value.
    @Test func `lowers a float operand to a float value node`() throws {
        let expression = try InkExpressionParser.parse("1.5 + 2")
        let nodes = RuntimeObjectEmitter.lowerInlineExpression(expression)

        #expect(describe(nodes) == ["ev", "float:1.5", "int:2", "fn:+", "out", "/ev"])
    }

    // B3 — UNIT INVARIANT: playing the lowered `{2 + 3 * 4}` yields "14".
    @Test func `played inline integer arithmetic yields fourteen`() throws {
        let expression = try InkExpressionParser.parse("2 + 3 * 4")
        var children = RuntimeObjectEmitter.lowerInlineExpression(expression)
        children.append(.newline)
        let root = ContainerNode(children: children, namedContent: [:], flags: 0, name: nil)

        let engine = InkEngine(root: root)
        engine.step()

        #expect(engine.currentText == "14\n")
    }
}

// MARK: - Test helpers

/// Render a node sequence into intention-revealing tokens so the postfix order
/// can be asserted without NodeKind conforming to Equatable.
private func describe(_ nodes: [NodeKind]) -> [String] {
    nodes.map { node in
        switch node {
        case .controlCommand(let command): return command
        case .nativeFunction(let symbol): return "fn:\(symbol)"
        case .intValue(let value): return "int:\(value)"
        case .floatValue(let value): return "float:\(formatFloat(value))"
        default: return "other"
        }
    }
}

private func formatFloat(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
}
