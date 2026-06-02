import Testing
import Foundation
@testable import SwiftInkRuntime

// Test Budget: 5 distinct behaviors x 2 = 10 max unit tests
// Behaviors:
//   B1 — default StoryState initialises with zero/empty fields
//   B2 — StoryState encodes to JSON without throwing
//   B3 — StoryState round-trips through JSONEncoder/JSONDecoder (static fixture)
//   B4 — InkValue cases encode/decode correctly (parametrized over 4 cases)
//   B5 — mid-story StoryState (after stepping a real engine) round-trips through saveState/restoreState

@Suite("StoryState")
struct StoryStateTests {

    // Behavior 1: StoryState can be initialized with default values
    @Test func `default StoryState has expected initial values`() {
        let state = StoryState()
        #expect(state.pointer.containerPath == [])
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
        state.pointer = StoryPointer(containerPath: ["root", "knot1"], index: 3)
        state.outputStream = ["Hello, ", "world!"]
        state.variablesState = ["score": .int(42), "name": .string("Ink")]
        state.visitCounts = ["knot1": 2]
        state.currentTags = ["author: Maarten"]
        state.currentChoices = [ChoiceData(text: "Go left", targetPath: "root.left", index: 0)]
        state.isEnded = true

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StoryState.self, from: data)

        #expect(decoded.pointer.containerPath == ["root", "knot1"])
        #expect(decoded.pointer.index == 3)
        #expect(decoded.outputStream == ["Hello, ", "world!"])
        #expect(decoded.visitCounts == ["knot1": 2])
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
}
