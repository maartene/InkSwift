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
    // Budget = 2 behaviors × 2 = 4 unit tests max

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
}
