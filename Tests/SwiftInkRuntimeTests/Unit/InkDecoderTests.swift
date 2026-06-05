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
    // Behavior 2: f() dict node is classified as .divert, not .controlCommand
    // Behavior 3: ->t-> dict node is classified as .tunnelDivert(target:)
    // Behavior 4: {"^var":"name","ci":-1} dict is classified as .variablePointer(name:contextIndex:)
    // Budget = 4 behaviors × 2 = 8 unit tests max

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
            #expect(key == "café")
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
            #expect(key == "knot")
        } else {
            Issue.record("Expected .readCount(\"knot\") but got \(firstChild)")
        }
    }

    // MARK: - Behavior 2: f() dict classified as .divert

    @Test func `InkDecoder classifies f() dict node as divert to named function`() throws {
        let json = """
        {"inkVersion":21,"root":[{"f()":"double"},null]}
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)

        let firstChild = try #require(root.children.first)
        if case .divert(let target, let isConditional, _) = firstChild {
            // f() diverts carry "f():" prefix so the engine can push a return address
            #expect(target == "f():double")
            #expect(isConditional == false)
        } else {
            Issue.record("Expected .divert(\"f():double\", ...) but got \(firstChild)")
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
            #expect(target == "sub_room")
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
}
