import Testing
import Foundation
@testable import SwiftInkRuntime

// Test Budget: 11 distinct behaviors x 2 = 22 max unit tests
// Behaviors:
//   B1 — default StoryState initialises with zero/empty fields
//   B2 — StoryState encodes to JSON without throwing
//   B3 — StoryState round-trips through JSONEncoder/JSONDecoder (static fixture)
//   B4 — InkValue cases encode/decode correctly (parametrized over 4 cases)
//   B5 — mid-story StoryState (after stepping a real engine) round-trips through saveState/restoreState
//   B6 — StoryState round-trips chosenChoiceTargets through encode/decode
//   B7 — StoryState decodes from JSON missing chosenChoiceTargets without error (backward compat)
//   B8 — ChoiceData round-trips flags through encode/decode
//   B9 — ChoiceData decodes from JSON missing flags without error (backward compat)
//   B10 — typed path fields encode to the legacy wire form (ADR-018)
//   B11 — legacy wire strings decode to typed paths and re-encode byte-identically
//   B12 — the typed output stream saves as its text and newline strings, tags left out (ADR-020 §6)

@Suite("StoryState")
struct StoryStateTests {

    private static let choice1 = ContainerPath(components: [.name("root"), .name("choice1")])
    private static let choice2 = ContainerPath(components: [.name("root"), .name("choice2")])

    // Behavior 1: StoryState can be initialized with default values
    @Test func `default StoryState has expected initial values`() {
        let state = StoryState()
        #expect(state.pointer.containerPath == ContainerPath(components: []))
        #expect(state.pointer.index == 0)
        #expect(state.outputStream.isEmpty)
        #expect(state.variablesState.isEmpty)
        #expect(state.visitCounts.isEmpty)
        #expect(state.currentTags.isEmpty)
        #expect(state.currentChoices.isEmpty)
        #expect(state.isEnded == false)
    }

    // Behavior 2: StoryState encodes to JSON without throwing
    @Test func `StoryState encodes to JSON without throwing`() throws {
        let state = StoryState()
        let encoder = JSONEncoder()
        _ = try encoder.encode(state)
    }

    // Behavior 3: StoryState round-trips through JSONEncoder/JSONDecoder
    @Test func `StoryState round-trips through JSONEncoder and JSONDecoder`() throws {
        var state = StoryState()
        state.pointer = StoryPointer(containerPath: ContainerPath(components: [.name("root"), .name("knot1")]), index: 3)
        state.outputStream = ["Hello, ", "world!"]
        state.variablesState = ["score": .int(42), "name": .string("Ink")]
        state.visitCounts = [ContainerPath(components: [.name("knot1")]): 2]
        state.currentTags = ["author: Maarten"]
        state.currentChoices = [ChoiceData(text: "Go left", targetPath: "root.left", continuationFrames: [], index: 0)]
        state.isEnded = true

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StoryState.self, from: data)

        #expect(decoded.pointer.containerPath == ContainerPath(components: [.name("root"), .name("knot1")]))
        #expect(decoded.pointer.index == 3)
        #expect(decoded.outputStream == ["Hello, ", "world!"])
        #expect(decoded.visitCounts == [ContainerPath(components: [.name("knot1")]): 2])
        #expect(decoded.currentTags == ["author: Maarten"])
        #expect(decoded.isEnded == true)
        #expect(decoded.currentChoices.count == 1)
        #expect(decoded.currentChoices[0].text == "Go left")
        #expect(decoded.currentChoices[0].targetPath == "root.left")
        #expect(decoded.currentChoices[0].index == 0)
    }

    // Behavior 4: InkValue cases encode/decode correctly
    @Test(arguments: [
        InkValue.int(7),
        InkValue.float(3.14),
        InkValue.string("hello"),
        InkValue.bool(true)
    ])
    func `InkValue cases encode and decode correctly`(value: InkValue) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InkValue.self, from: data)
        #expect(decoded == value)
    }

    // Behavior 5: mid-story StoryState round-trips through saveState/restoreState
    // Enters through InkEngine driving port (saveState/restoreState), loads a real fixture,
    // steps at least one passage, then verifies the Codable round-trip preserves key fields.
    @Test func `mid-story StoryState round-trips through saveState and restoreState`() throws {
        // Arrange: load test.ink.json from bundle and decode into a ContainerNode
        let url = try #require(Bundle.module.url(forResource: "test.ink", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let root = try InkDecoder().decode(data)

        // Act: step through at least one passage to populate state
        let engine = InkEngine(root: root)
        _ = engine.stepToNextLine()

        let originalVisitCounts = engine.state.visitCounts
        let originalOutputStream = engine.state.outputStream
        let originalEvalStack = engine.state.evalStack

        // Save state through driving port
        let savedData = try engine.saveState()
        #expect(savedData.count > 0)

        // Decode the saved data to get the actual persisted pointer (saveState syncs containerStack)
        let savedState = try JSONDecoder().decode(StoryState.self, from: savedData)

        // Restore into a fresh engine
        let engine2 = InkEngine(root: root)
        try engine2.restoreState(savedData)

        // Assert: key fields survive the round-trip (pointer compared against what was actually saved)
        #expect(engine2.state.pointer.containerPath == savedState.pointer.containerPath)
        #expect(engine2.state.pointer.index == savedState.pointer.index)
        #expect(engine2.state.visitCounts == originalVisitCounts)
        #expect(engine2.state.outputStream == originalOutputStream)
        #expect(engine2.state.evalStack == originalEvalStack)
    }

    // Behavior 6: StoryState round-trips chosenChoiceTargets through encode/decode
    @Test func `StoryState round-trips chosenChoiceTargets through encode and decode`() throws {
        var state = StoryState()
        state.chosenChoiceTargets = [Self.choice1, Self.choice2]

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StoryState.self, from: data)

        #expect(decoded.chosenChoiceTargets == [Self.choice1, Self.choice2])
    }

    // Behavior 7: StoryState decodes from JSON missing chosenChoiceTargets without error (backward compat)
    @Test func `StoryState decodes from JSON missing chosenChoiceTargets without throwing`() throws {
        // Build a minimal valid StoryState JSON without chosenChoiceTargets key
        let state = StoryState()
        let encoder = JSONEncoder()
        var jsonObject = try JSONSerialization.jsonObject(with: encoder.encode(state)) as! [String: Any]
        jsonObject.removeValue(forKey: "chosenChoiceTargets")
        let legacyData = try JSONSerialization.data(withJSONObject: jsonObject)

        let decoded = try JSONDecoder().decode(StoryState.self, from: legacyData)
        #expect(decoded.chosenChoiceTargets == [])
    }

    // Behavior 8: ChoiceData round-trips flags through encode/decode
    @Test func `ChoiceData round-trips flags through encode and decode`() throws {
        let choice = ChoiceData(text: "Go left", targetPath: "root.left", continuationFrames: [], index: 0, flags: ChoiceFlags(rawValue: 3))

        let encoder = JSONEncoder()
        let data = try encoder.encode(choice)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ChoiceData.self, from: data)

        #expect(decoded.flags == ChoiceFlags(rawValue: 3))
        #expect(decoded.text == "Go left")
        #expect(decoded.targetPath == "root.left")
        #expect(decoded.index == 0)
    }

    // Behavior 9: ChoiceData decodes from JSON missing flags without error (backward compat)
    @Test func `ChoiceData decodes from JSON missing flags without throwing`() throws {
        let choice = ChoiceData(text: "Go right", targetPath: "root.right", continuationFrames: [], index: 1, flags: [])
        let encoder = JSONEncoder()
        var jsonObject = try JSONSerialization.jsonObject(with: encoder.encode(choice)) as! [String: Any]
        jsonObject.removeValue(forKey: "flags")
        let legacyData = try JSONSerialization.data(withJSONObject: jsonObject)

        let decoded = try JSONDecoder().decode(ChoiceData.self, from: legacyData)
        #expect(decoded.flags == ChoiceFlags(rawValue: 0))
        #expect(decoded.text == "Go right")
    }

    // Behavior 10: typed path fields encode to the legacy wire form (ADR-018)
    @Test func `typed path fields encode to the legacy strings of the save wire`() throws {
        var state = StoryState()
        let knotStitch = ContainerPath(components: [.name("café"), .index(0), .name("g-2")])
        state.pointer = StoryPointer(containerPath: knotStitch, index: 4)
        state.stackFrames = [
            ContainerStackFrame(pathFromRoot: ContainerPath(components: []), executionIndex: 1),
            ContainerStackFrame(pathFromRoot: knotStitch, executionIndex: 4, isChoiceContinuationRoot: true)
        ]
        state.visitCounts = [knotStitch: 2, ContainerPath(components: [.name("café")]): 1]
        state.chosenChoiceTargets = [
            ContainerPath(components: [.index(0), .index(0), .name("c-1")]),
            ContainerPath(components: [.name("café"), .name("c-0")]),
            ContainerPath(components: [.index(0), .index(0), .name("c-0")])
        ]

        let wire = try Self.wireObject(of: state)

        let pointer = try #require(wire["pointer"] as? [String: Any])
        #expect(pointer["containerPath"] as? [String] == ["café", "0", "g-2"])
        let frames = try #require(wire["stackFrames"] as? [[String: Any]])
        #expect(frames.map { $0["pathFromRoot"] as? [String] } == [[], ["café", "0", "g-2"]])
        #expect(wire["visitCounts"] as? [String: Int] == ["café.0.g-2": 2, "café": 1])
        #expect(wire["chosenChoiceTargets"] as? [String] == ["0.0.c-0", "0.0.c-1", "café.c-0"])
    }

    // Behavior 11: legacy wire strings decode to typed paths and re-encode byte-identically
    @Test(arguments: ["", "café", "0.0.c-0", "tunnel_a.0.g-2.$r1", "007.5", "-1.+5", "a..b"])
    func `a saved path string decodes to a typed path and re-encodes unchanged`(saved: String) throws {
        let components = saved.isEmpty ? [] : saved.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var wire = try Self.wireObject(of: StoryState())
        wire["pointer"] = ["containerPath": components, "index": 0]
        wire["stackFrames"] = [["pathFromRoot": components, "executionIndex": 2, "isChoiceContinuationRoot": false]]
        wire["visitCounts"] = [saved: 3]
        wire["chosenChoiceTargets"] = [saved]
        let legacyData = try JSONSerialization.data(withJSONObject: wire, options: .sortedKeys)

        let decoded = try JSONDecoder().decode(StoryState.self, from: legacyData)

        #expect(decoded.pointer.containerPath.description == saved)
        #expect(decoded.stackFrames.map(\.pathFromRoot.description) == [saved])
        #expect(decoded.visitCounts.keys.map(\.description) == [saved])
        #expect(decoded.chosenChoiceTargets.map(\.description) == [saved])
        let reencoder = JSONEncoder()
        reencoder.outputFormatting = .sortedKeys
        let reencoded = try JSONSerialization.data(
            withJSONObject: JSONSerialization.jsonObject(with: reencoder.encode(decoded)),
            options: .sortedKeys
        )
        #expect(reencoded == legacyData)
    }

    @Test func `saved index, name and root components decode to their typed cases`() throws {
        var wire = try Self.wireObject(of: StoryState())
        wire["pointer"] = ["containerPath": ["knot", "4", "007"], "index": 0]
        wire["visitCounts"] = ["": 1, "knot.4": 2]
        let decoded = try JSONDecoder().decode(StoryState.self, from: JSONSerialization.data(withJSONObject: wire))
        #expect(decoded.pointer.containerPath == ContainerPath(components: [.name("knot"), .index(4), .name("007")]))
        #expect(decoded.visitCounts == [.root: 1, ContainerPath(components: [.name("knot"), .index(4)]): 2])
    }

    // Behavior 12: the outputStream wire stays a [String] of text and "\n" items
    @Test func `output stream saves its text and newline items in order and leaves tags out`() throws {
        var state = StoryState()
        state.outputStream = [.text("Hello"), .tag("greeting"), .newline, .text("Next")]
        let wire = try Self.wireObject(of: state)
        #expect(wire["outputStream"] as? [String] == ["Hello", "\n", "Next"])
        let restored = try JSONDecoder().decode(StoryState.self, from: JSONEncoder().encode(state))
        #expect(restored.outputStream == [.text("Hello"), .newline, .text("Next")])
    }

    private static func wireObject(of state: StoryState) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }
}
