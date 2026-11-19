// Tests for InkDecoder — node classification via decode pipeline
// Driving port: InkDecoder.decode(_:) — the public API
// Mandate M2: classifyDict is private; tested through the public decode pipeline

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("InkDecoder")
struct InkDecoderTests {

    // Test Budget:
    // Behavior 1: CNT? dict node is classified as .readCount(key), not .controlCommand("CNT?")
    // Behavior 2: f() dict node is classified as .functionCall(target:), not .controlCommand
    // Behavior 3: ->t-> dict node is classified as .tunnelDivert(target:)
    // Behavior 4: {"^var":"name","ci":-1} dict is classified as .variablePointer(name:contextIndex:)
    // Behavior 5: every path-bearing payload (CNT?, *, ->t->, f(), ^->) decodes to a
    //             typed PathReference, relative or absolute (typed-runtime-paths 02-03, 02-05)
    // Behavior 6: a "->" divert decodes to a typed DivertTarget — a variable target
    //             when "var" is present, else a path — with its "c" flag (02-04)
    // Behavior 7: the startup probe refuses a scalar fixture whose float, bool
    //             or int slot comes back mistyped (ADR-023 §4, issue #37)
    // Budget = 7 behaviors × 2 = 14 unit tests max

    // MARK: - Behavior 1: CNT? dict classified as readCount

    @Test func `InkDecoder classifies CNT? dict node as readCount not controlCommand`() throws {
        // Construct minimal valid Ink JSON with a CNT? dict directly in the root array
        // Format: {"inkVersion":21,"root":[{"CNT?":"café"},null]}
        // The root array contains the CNT? dict as a direct element (not wrapped in a sub-array)
        let json = """
        {"inkVersion":21,"root":[{"CNT?":"caf\\u00E9"},null]}
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)

        // The first child of the root container must be .readCount("café")
        let firstChild = try #require(root.children.first)
        if case .readCount(let key) = firstChild {
            #expect(key == .absolute(ContainerPath(components: [.name("café")])))
        } else {
            Issue.record("Expected .readCount(\"café\") but got \(firstChild)")
        }
    }

    @Test func `InkDecoder does not classify CNT? dict node as controlCommand`() throws {
        let json = """
        {"inkVersion":21,"root":[{"CNT?":"knot"},null]}
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)

        let firstChild = try #require(root.children.first)
        if case .controlCommand = firstChild {
            Issue.record("CNT? must not be classified as .controlCommand — got \(firstChild)")
        }
        if case .readCount(let key) = firstChild {
            #expect(key == .absolute(ContainerPath(components: [.name("knot")])))
        } else {
            Issue.record("Expected .readCount(\"knot\") but got \(firstChild)")
        }
    }

    // MARK: - Behavior 5: path payloads decode to typed path references

    /// Node shapes as inklecate writes them (compare `rc-choicelabel-guard.ink.json`,
    /// `compile-weave-nested.ink.json`, `compile-ceiling.ink.json`).
    @Test(arguments: [
        (#"{"CNT?":".^"}"#, "readCount", PathReference.relative(parentSteps: 1, tail: [])),
        (#"{"CNT?":".^.^.g-0"}"#, "readCount", .relative(parentSteps: 2, tail: [.name("g-0")])),
        (#"{"CNT?":"knot.stitch"}"#, "readCount", .absolute(ContainerPath(components: [.name("knot"), .name("stitch")]))),
        (#"{"*":".^.^.c-0","flg":20}"#, "choicePoint", .relative(parentSteps: 2, tail: [.name("c-0")])),
        (#"{"*":"0.c-1","flg":20}"#, "choicePoint", .absolute(ContainerPath(components: [.index(0), .name("c-1")]))),
        (#"{"->t->":"detour"}"#, "tunnelDivert", .absolute(ContainerPath(components: [.name("detour")]))),
        (#"{"f()":"double"}"#, "functionCall", .absolute(ContainerPath(components: [.name("double")]))),
        (#"{"^->":"0.c-0.$r2"}"#, "pushDivertTarget",
         .absolute(ContainerPath(components: [.index(0), .name("c-0"), .name("$r2")]))),
    ])
    func `a path-bearing node decodes to its typed path reference`(
        node: String, kind: String, expected: PathReference
    ) throws {
        let json = #"{"inkVersion":21,"root":["# + node + #",null]}"#
        let root = try InkDecoder().decode(try #require(json.data(using: .utf8)))

        let decoded = try #require(root.children.first)
        #expect(Self.pathPayload(of: decoded)?.kind == kind)
        #expect(Self.pathPayload(of: decoded)?.reference == expected)
    }

    private static func pathPayload(of node: NodeKind) -> (kind: String, reference: PathReference)? {
        switch node {
        case .readCount(let reference): return ("readCount", reference)
        case .choicePoint(let reference, _): return ("choicePoint", reference)
        case .tunnelDivert(let reference): return ("tunnelDivert", reference)
        case .functionCall(let reference): return ("functionCall", reference)
        case .pushDivertTarget(let reference): return ("pushDivertTarget", reference)
        default: return nil
        }
    }

    // MARK: - Behavior 6: diverts decode to typed divert targets

    /// Divert shapes as inklecate writes them (compare `compile-ceiling.ink.json`
    /// for path and conditional diverts, `TheIntercept.ink.json` for `"var":true`).
    @Test(arguments: [
        (#"{"->":"$r","var":true}"#, DivertTarget.variable(name: "$r"), false),
        (#"{"->":"knot_target","var":true,"c":true}"#, .variable(name: "knot_target"), true),
        (#"{"->":"knot.stitch"}"#, .path(.absolute(ContainerPath(components: [.name("knot"), .name("stitch")]))), false),
        (#"{"->":".^.b","c":true}"#, .path(.relative(parentSteps: 1, tail: [.name("b")])), true),
        (#"{"->":"0.g-0"}"#, .path(.absolute(ContainerPath(components: [.index(0), .name("g-0")]))), false),
    ])
    func `a divert decodes to its typed target and conditionality`(
        node: String, expected: DivertTarget, isConditional: Bool
    ) throws {
        let json = #"{"inkVersion":21,"root":["# + node + #",null]}"#
        let root = try InkDecoder().decode(try #require(json.data(using: .utf8)))

        let decoded = try #require(root.children.first)
        guard case .divert(let target, let decodedIsConditional) = decoded else {
            Issue.record("Expected .divert but got \(decoded)")
            return
        }
        #expect(target == expected)
        #expect(decodedIsConditional == isConditional)
    }

    // MARK: - Behavior 2: f() dict classified as .functionCall

    @Test func `InkDecoder classifies f() dict node as a function call to the named function`() throws {
        let json = """
        {"inkVersion":21,"root":[{"f()":"double"},null]}
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)

        let firstChild = try #require(root.children.first)
        if case .functionCall(let target) = firstChild {
            #expect(target == .absolute(ContainerPath(components: [.name("double")])))
        } else {
            Issue.record("Expected .functionCall(target: double) but got \(firstChild)")
        }
    }

    @Test func `InkDecoder does not classify f() dict node as controlCommand`() throws {
        let json = """
        {"inkVersion":21,"root":[{"f()":"myfunc"},null]}
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)

        let firstChild = try #require(root.children.first)
        if case .controlCommand = firstChild {
            Issue.record("f() must not be classified as .controlCommand — got \(firstChild)")
        }
    }

    // MARK: - Behavior 3: ->t-> dict classified as .tunnelDivert

    @Test func `InkDecoder classifies tunnel divert dict as tunnelDivert with correct target`() throws {
        let json = """
        {"inkVersion":21,"root":[{"->t->":"sub_room"},null]}
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)

        let firstChild = try #require(root.children.first)
        if case .tunnelDivert(let target) = firstChild {
            #expect(target == .absolute(ContainerPath(components: [.name("sub_room")])))
        } else {
            Issue.record("Expected .tunnelDivert(target: \"sub_room\") but got \(firstChild)")
        }
    }

    @Test func `InkDecoder does not classify tunnel divert dict as controlCommand`() throws {
        let json = """
        {"inkVersion":21,"root":[{"->t->":"some_knot"},null]}
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)

        let firstChild = try #require(root.children.first)
        if case .controlCommand = firstChild {
            Issue.record("->t-> must not be classified as .controlCommand — got \(firstChild)")
        }
    }

    // MARK: - Behavior 4: {"^var":"name","ci":-1} classified as .variablePointer

    @Test func `InkDecoder classifies variable pointer dict as variablePointer with name and contextIndex`() throws {
        let json = """
        {"inkVersion":21,"root":[{"^var":"score","ci":-1},null]}
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)

        let firstChild = try #require(root.children.first)
        if case .variablePointer(let name, let contextIndex) = firstChild {
            #expect(name == "score")
            #expect(contextIndex == -1)
        } else {
            Issue.record("Expected .variablePointer(name: \"score\", contextIndex: -1) but got \(firstChild)")
        }
    }

    @Test func `InkDecoder does not classify variable pointer dict as controlCommand`() throws {
        let json = """
        {"inkVersion":21,"root":[{"^var":"score","ci":-1},null]}
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)

        let firstChild = try #require(root.children.first)
        if case .controlCommand = firstChild {
            Issue.record("^var dict must not be classified as .controlCommand — got \(firstChild)")
        }
    }

    // MARK: - Behavior 7: the scalar probe refuses mistyped values

    /// The probe's own fixture types `2.5`, `2.0` and `1e2` as floats, `true`
    /// as a bool and `42` as an int. Each argument puts a wrongly typed token in
    /// one slot, as a reader with the issue #37 defect would type it.
    @Test(arguments: [
        #"{"inkVersion":21,"root":[2.5,true,42,2,1e2,null],"listDefs":{}}"#,
        #"{"inkVersion":21,"root":[2.5,true,42,2.0,100,null],"listDefs":{}}"#,
        #"{"inkVersion":21,"root":[2,true,42,2.0,1e2,null],"listDefs":{}}"#,
        #"{"inkVersion":21,"root":[2.5,1,42,2.0,1e2,null],"listDefs":{}}"#,
        #"{"inkVersion":21,"root":[2.5,true,42.0,2.0,1e2,null],"listDefs":{}}"#,
    ])
    func `the scalar probe refuses to start on a mistyped value`(fixture: String) throws {
        let error = try #require(throws: InkDecodeError.self) {
            try InkDecoder().probeScalarTyping(of: fixture)
        }

        #expect(error == .probeClassificationDrift)
        #expect(StoryError(error) == .decoderProbeFailure(reason: "number/bool classification drift"))
    }

    @Test func `the scalar probe accepts its own fixture`() throws {
        try InkDecoder().probeScalarTyping(of: InkDecoder.scalarProbeFixture)
    }
}
