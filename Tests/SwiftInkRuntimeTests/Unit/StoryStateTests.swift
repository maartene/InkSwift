import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("StoryState")
struct StoryStateTests {

    // Behavior 1: StoryState can be initialized with default values
    @Test("default StoryState has expected initial values")
    func defaultStoryStateHasExpectedInitialValues() {
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
    @Test("StoryState encodes to JSON without throwing")
    func storyStateEncodesToJSONWithoutThrowing() throws {
        let state = StoryState()
        let encoder = JSONEncoder()
        _ = try encoder.encode(state)
    }

    // Behavior 3: StoryState round-trips through JSONEncoder/JSONDecoder
    @Test("StoryState round-trips through JSONEncoder and JSONDecoder")
    func storyStateRoundTrips() throws {
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
    @Test("InkValue cases encode and decode correctly", arguments: [
        InkValue.int(7),
        InkValue.float(3.14),
        InkValue.string("hello"),
        InkValue.bool(true)
    ])
    func inkValueCasesRoundTrip(value: InkValue) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InkValue.self, from: data)
        #expect(decoded == value)
    }
}
