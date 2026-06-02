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
    @Test func `step returns nil when container is exhausted`() {
        let container = ContainerNode(children: [], namedContent: [:], flags: 0, name: nil)
        let walker = TreeWalker()
        var state = StoryState()
        let result = walker.step(in: container, state: &state)
        #expect(result == nil)
    }

    @Test func `step returns nil when pointer index equals children count`() {
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
    @Test func `step appends text node content to outputStream`() {
        let container = ContainerNode(
            children: [.text("Hello, world!")],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        _ = walker.step(in: container, state: &state)
        #expect(state.outputStream == ["Hello, world!"])
        #expect(state.pointer.index == 1)
    }

    @Test func `step appends multiple text nodes in order`() {
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
    @Test func `step appends newline sentinel to outputStream for newline node`() {
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
    @Test(arguments: ["done", "end"])
    func `step sets isEnded to true for done or end control command`(command: String) {
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
    @Test func `step updates containerPath from divert target`() {
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

    @Test func `step updates containerPath for dotted divert target`() {
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
