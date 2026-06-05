// Tests for NodeKind enum — all node types per spike findings
// Driving port: NodeKind enum (pure value type, IS the driving port)
// Mandate M2: testing through the public interface of the enum itself

import Testing
@testable import SwiftInkRuntime

@Suite("NodeKind")
struct NodeKindTests {

    // Test Budget:
    // Behavior 1: NodeKind exhaustively covers all Ink AST node kinds
    // Behavior 2: NodeKind associated values carry the correct payload types
    // Budget = 2 behaviors × 2 = 4 unit tests max

    // MARK: - Behavior 1: All node kinds are present

    @Test func `all ink node kinds are representable`() {
        // Exhaustive switch — compiler enforces completeness at build time.
        // If any required case is missing, this file will not compile.
        let nodes: [NodeKind] = [
            .text("hello"),
            .newline,
            .intValue(1),
            .floatValue(1.5),
            .controlCommand("ev"),
            .nativeFunction("+"),
            .divert(target: "knot", isConditional: false, isVariable: false),
            .tunnelDivert(target: "sub_room"),
            .choicePoint(target: "c-0", flags: []),
            .variableAssignment(name: "x", isGlobal: true),
            .variableReference(name: "x"),
            .tagOpen,
            .tagClose,
            .voidValue,
            .pushDivertTarget("test"),
            .readCount("knot"),
        ]

        // Exhaustive switch proves every case compiles
        for node in nodes {
            switch node {
            case .text:            break
            case .newline:         break
            case .intValue:        break
            case .floatValue:      break
            case .controlCommand:  break
            case .nativeFunction:  break
            case .divert:          break
            case .tunnelDivert:    break
            case .choicePoint:     break
            case .variableAssignment: break
            case .variableReference:  break
            case .tagOpen:         break
            case .tagClose:        break
            case .voidValue:       break
            case .container:       break
            case .pushDivertTarget: break
            case .readCount:       break
            }
        }

        #expect(nodes.count == 16)
    }

    // MARK: - Behavior 2: Associated values carry correct payload types

    @Test func `associated values carry correct payloads`() {
        let textNode = NodeKind.text("hello world")
        if case .text(let value) = textNode {
            #expect(value == "hello world")
        } else {
            Issue.record("Expected .text node")
        }

        let intNode = NodeKind.intValue(42)
        if case .intValue(let value) = intNode {
            #expect(value == 42)
        } else {
            Issue.record("Expected .intValue node")
        }

        let floatNode = NodeKind.floatValue(3.14)
        if case .floatValue(let value) = floatNode {
            #expect(abs(value - 3.14) < 0.001)
        } else {
            Issue.record("Expected .floatValue node")
        }

        let divertNode = NodeKind.divert(target: "knot.stitch", isConditional: true, isVariable: false)
        if case .divert(let target, let isConditional, let isVariable) = divertNode {
            #expect(target == "knot.stitch")
            #expect(isConditional == true)
            #expect(isVariable == false)
        } else {
            Issue.record("Expected .divert node")
        }

        let choiceNode = NodeKind.choicePoint(target: "c-0", flags: ChoiceFlags(rawValue: 18))
        if case .choicePoint(let target, let flags) = choiceNode {
            #expect(target == "c-0")
            #expect(flags == ChoiceFlags(rawValue: 18))
        } else {
            Issue.record("Expected .choicePoint node")
        }

        let varAssign = NodeKind.variableAssignment(name: "counter", isGlobal: false)
        if case .variableAssignment(let name, let isGlobal) = varAssign {
            #expect(name == "counter")
            #expect(isGlobal == false)
        } else {
            Issue.record("Expected .variableAssignment node")
        }

        let varRef = NodeKind.variableReference(name: "counter")
        if case .variableReference(let name) = varRef {
            #expect(name == "counter")
        } else {
            Issue.record("Expected .variableReference node")
        }
    }
}
