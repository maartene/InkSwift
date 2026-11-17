// Tests for NodeKind enum — all node types per spike findings
// Driving port: NodeKind enum (pure value type, IS the driving port)
// Mandate M2: testing through the public interface of the enum itself

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("NodeKind")
struct NodeKindTests {

    // Test Budget:
    // Behavior 1: NodeKind exhaustively covers all Ink AST node kinds
    // Behavior 2: NodeKind associated values carry the correct payload types
    // Behavior 3: natively compiled path payloads reach the containers the decoded
    //             inklecate JSON's payloads reach (S4a, typed-runtime-paths 02-03)
    // Budget = 3 behaviors × 2 = 6 unit tests max

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
            .tunnelDivert(target: PathReference(parsing: "sub_room")),
            .choicePoint(target: PathReference(parsing: ".^.c-0"), flags: []),
            .variableAssignment(name: "x", isGlobal: true),
            .variableReference(name: "x"),
            .tagOpen,
            .tagClose,
            .voidValue,
            .pushDivertTarget(PathReference(parsing: "knot.0.$r1")),
            .readCount(PathReference(parsing: "knot")),
            .variablePointer(name: "score", contextIndex: -1),
            .boolValue(true),
        ]

        // Exhaustive switch proves every case compiles
        for node in nodes {
            switch node {
            case .text:            break
            case .newline:         break
            case .intValue:        break
            case .floatValue:      break
            case .boolValue:       break
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
            case .variablePointer: break
            }
        }

        #expect(nodes.count == 18)
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

        let choiceNode = NodeKind.choicePoint(target: PathReference(parsing: ".^.c-0"), flags: ChoiceFlags(rawValue: 18))
        if case .choicePoint(let target, let flags) = choiceNode {
            #expect(target == .relative(parentSteps: 1, tail: [.name("c-0")]))
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

    // MARK: - Behavior 3: native and decoded payloads agree

    /// inklecate and the native compiler both write a tunnel target absolute, so the
    /// typed payloads must be equal outright.
    @Test(arguments: ["compile-ceiling", "slice-t1-tunnels", "slice-t2-nested-tunnels"])
    func `natively compiled tunnel targets equal the decoded inklecate tunnel targets`(fixture: String) throws {
        let decoded = try InkDecoder().decode(Data(try CompilerOracle.oracleJSON(fixture).utf8))
        let native = try InkCompiler.compile(source: try CompilerOracle.source(fixture)).root

        let expected = pathPayloads(in: decoded).filter { $0.key == "->t->" }.map(\.reference)
        #expect(expected.isEmpty == false)
        #expect(pathPayloads(in: native).filter { $0.key == "->t->" }.map(\.reference) == expected)
    }

    /// Choice and read-count paths differ in spelling between the two trees
    /// (inklecate writes `.^.^.c-0`, the compiler `knot.c-0` against its own
    /// layout), so each native payload is checked against what the decoder yields
    /// for that payload's JSON spelling: an index stays an index, a name a name.
    @Test(arguments: ["rc-choicelabel-guard", "rc-choicelabel-inline", "compile-weave-nested", "compile-ceiling"])
    func `every natively compiled path payload is what the decoder yields for its JSON spelling`(
        fixture: String
    ) throws {
        let native = try InkCompiler.compile(source: try CompilerOracle.source(fixture)).root
        let payloads = pathPayloads(in: native)
        #expect(payloads.isEmpty == false)

        for payload in payloads {
            let node = #"{"\#(payload.key)":"\#(payload.reference)"}"#
            let json = #"{"inkVersion":21,"root":["# + node + #",null]}"#
            let decoded = try InkDecoder().decode(try #require(json.data(using: .utf8)))
            let reference = try #require(decoded.children.first.flatMap(pathPayload(of:)))
            #expect(reference.key == payload.key)
            #expect(reference.reference == payload.reference)
        }
    }
}

/// A node's path payload with the `.ink.json` key that carries it, else nil.
private func pathPayload(of node: NodeKind) -> (key: String, reference: PathReference)? {
    switch node {
    case .readCount(let reference): return ("CNT?", reference)
    case .choicePoint(let reference, _): return ("*", reference)
    case .tunnelDivert(let reference): return ("->t->", reference)
    case .pushDivertTarget(let reference): return ("^->", reference)
    default: return nil
    }
}

/// Every path payload in the tree, in children order, then named content by name.
private func pathPayloads(in container: ContainerNode) -> [(key: String, reference: PathReference)] {
    var payloads: [(key: String, reference: PathReference)] = []
    for child in container.children {
        if case .container(let nested) = child {
            if let name = nested.name, container.namedContent[name] != nil { continue }
            payloads += pathPayloads(in: nested)
        } else if let payload = pathPayload(of: child) {
            payloads.append(payload)
        }
    }
    for (_, nested) in container.namedContent.sorted(by: { $0.key < $1.key }) {
        payloads += pathPayloads(in: nested)
    }
    return payloads
}
