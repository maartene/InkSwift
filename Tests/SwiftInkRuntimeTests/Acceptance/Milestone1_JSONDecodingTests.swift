// @real-io @adapter-integration
// Adapter: InkDecoder (sole caller of JSONSerialization — Rule R3)
// All scenarios disabled — enable one at a time during DELIVER Milestone 1.

import Testing
@testable import SwiftInkRuntime

@Suite struct Milestone1_JSONDecodingTests {

    // GIVEN: a minimal valid Ink JSON string (inkVersion 21)
    // WHEN: InkDecoder.decode() is called
    // THEN: the result is a ContainerNode with at least one child

    @Test
    func `decoder parses minimal Ink JSON into a ContainerNode tree`() throws {
        let json = #"{"inkVersion":21,"root":[["\n",null],null],"listDefs":{}}"#
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)
        #expect(root.children.isEmpty == false)
    }

    // GIVEN: InkDecoder is initialised
    // WHEN: probe() is called
    // THEN: no error is thrown

    @Test
    func `InkDecoder probe passes for the bundled test fixture`() throws {
        let decoder = InkDecoder()
        try decoder.probe()
    }

    // GIVEN: a JSON string with inkVersion set to an unsupported value
    // WHEN: Story(json:) is called
    // THEN: StoryError.unsupportedInkVersion is thrown

    @Test
    func `Story init throws for an unsupported ink version`() throws {
        let json = #"{"inkVersion":19,"root":[["\n",null],null],"listDefs":{}}"#
        #expect {
            try Story(json: json)
        } throws: { error in
            guard case StoryError.unsupportedInkVersion(let version) = error else {
                return false
            }
            return version == 19
        }
    }

    // GIVEN: an Ink JSON container whose last element is null
    // WHEN: InkDecoder decodes it
    // THEN: ContainerNode.namedContent is empty and flags is 0

    @Test
    func `container null last element produces empty named content and zero flags`() throws {
        let json = #"{"inkVersion":21,"root":[["\n",null],null],"listDefs":{}}"#
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)
        #expect(root.namedContent.isEmpty)
        #expect(root.flags == 0)
    }

    // GIVEN: an Ink JSON container whose last element is a dict with named sub-containers
    // WHEN: InkDecoder decodes it
    // THEN: ContainerNode.namedContent contains those sub-containers

    @Test
    func `container dict last element populates named sub-containers`() throws {
        let json = "{\"inkVersion\":21,\"root\":[\"\\n\",{\"Knot1\":[\"\\n\",null],\"#f\":1}],\"listDefs\":{}}"
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)
        #expect(root.namedContent["Knot1"] != nil)
    }

    // GIVEN: an Ink JSON node containing an integer value
    // WHEN: InkDecoder classifies it
    // THEN: the NodeKind is .intValue, not .floatValue

    @Test
    func `decoder classifies whole numbers as intValue not floatValue`() throws {
        let json = "{\"inkVersion\":21,\"root\":[42,null],\"listDefs\":{}}"
        let data = try #require(json.data(using: .utf8))
        let decoder = InkDecoder()
        let root = try decoder.decode(data)
        guard case .intValue(let value) = root.children.first else {
            Issue.record("Expected first child to be .intValue, got \(String(describing: root.children.first))")
            return
        }
        #expect(value == 42)
    }
}
