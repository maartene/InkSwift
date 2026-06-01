// Test Budget: 5 distinct behaviors x 2 = 10 max unit tests
// Behaviors:
//   B1 — Container exhaustion returns nil
//   B2 — .text node appends to outputStream
//   B3 — .newline appends "\n" to outputStream (line boundary signal)
//   B4 — .controlCommand "done"/"end" sets isEnded = true
//   B5 — .divert updates containerPath and resets index to 0

import Testing
@testable import SwiftInkRuntime

@Suite("TreeWalker")
struct TreeWalkerTests {

    // B1: Container exhaustion returns nil
    @Test("step returns nil when container is exhausted")
    func stepReturnsNilWhenContainerIsExhausted() {
        let container = ContainerNode(children: [], namedContent: [:], flags: 0, name: nil)
        let walker = TreeWalker()
        var state = StoryState()
        let result = walker.step(in: container, state: &state)
        #expect(result == nil)
    }

    @Test("step returns nil when pointer index equals children count")
    func stepReturnsNilWhenPointerAtEnd() {
        let container = ContainerNode(
            children: [.text("hello")],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        state.pointer.index = 1  // already past the single child
        let result = walker.step(in: container, state: &state)
        #expect(result == nil)
    }

    // B2: .text node appends to outputStream
    @Test("step appends text node content to outputStream")
    func stepAppendsTextNodeToOutputStream() {
        let container = ContainerNode(
            children: [.text("Hello, world!")],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        _ = walker.step(in: container, state: &state)
        #expect(state.outputStream == ["Hello, world!"])
    }

    @Test("step appends multiple text nodes in order")
    func stepAppendsMultipleTextNodesInOrder() {
        let container = ContainerNode(
            children: [.text("Line "), .text("one")],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        _ = walker.step(in: container, state: &state)
        _ = walker.step(in: container, state: &state)
        #expect(state.outputStream == ["Line ", "one"])
    }

    // B3: .newline appends "\n" to outputStream
    @Test("step appends newline sentinel to outputStream for newline node")
    func stepAppendsNewlineSentinelForNewlineNode() {
        let container = ContainerNode(
            children: [.newline],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        _ = walker.step(in: container, state: &state)
        #expect(state.outputStream == ["\n"])
    }

    // B4: controlCommand "done"/"end" sets isEnded = true
    @Test("step sets isEnded to true for done or end control command",
          arguments: ["done", "end"])
    func stepSetsIsEndedForDoneOrEnd(command: String) {
        let container = ContainerNode(
            children: [.controlCommand(command)],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        _ = walker.step(in: container, state: &state)
        #expect(state.isEnded == true)
    }

    // B5: .divert updates containerPath and resets index to 0
    @Test("step updates containerPath from divert target")
    func stepUpdateContainerPathFromDivert() {
        let container = ContainerNode(
            children: [.divert(target: "Knot1", isConditional: false)],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        _ = walker.step(in: container, state: &state)
        #expect(state.pointer.containerPath == ["Knot1"])
        #expect(state.pointer.index == 0)
    }

    @Test("step updates containerPath for dotted divert target")
    func stepUpdateContainerPathFromDottedDivert() {
        let container = ContainerNode(
            children: [.divert(target: "Knot2.stitch1", isConditional: false)],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        _ = walker.step(in: container, state: &state)
        #expect(state.pointer.containerPath == ["Knot2", "stitch1"])
        #expect(state.pointer.index == 0)
    }
}
