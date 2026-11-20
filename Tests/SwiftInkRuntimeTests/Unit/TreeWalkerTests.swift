// Test Budget: 7 distinct behaviors x 2 = 14 max unit tests
// Behaviors:
//   B1 — Container exhaustion returns nil
//   B2 — .text node appends to outputStream
//   B3 — .newline appends "\n" to outputStream (line boundary signal)
//   B4 — .controlCommand "done"/"end" sets isEnded = true
//   (B5 — .divert updating containerPath — removed with the dead write it pinned:
//    InkEngine resolves every divert and owns the container stack.)
//   B6 — "out" control command suppresses the void value (emits nothing for it)
//   B7 — .variablePointer node pushes a pointer sentinel onto evalStack
//   B8 — variable assignment via pointer mutates the pointed-to global variable

import Testing
@testable import SwiftInkRuntime

@Suite("TreeWalker")
struct TreeWalkerTests {

    // B1: Container exhaustion returns nil
    @Test func `step returns nil when container is exhausted`() throws {
        let container = ContainerNode(children: [], namedContent: [:], flags: 0, name: nil)
        let walker = TreeWalker()
        var state = StoryState()
        let result = try walker.step(in: container, state: &state)
        #expect(result == nil)
    }

    @Test func `step returns nil when pointer index equals children count`() throws {
        let container = ContainerNode(
            children: [.text("hello")],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        state.pointer.index = 1  // already past the single child
        let result = try walker.step(in: container, state: &state)
        #expect(result == nil)
    }

    // B2: .text node appends to outputStream
    @Test func `step appends text node content to outputStream`() throws {
        let container = ContainerNode(
            children: [.text("Hello, world!")],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        _ = try walker.step(in: container, state: &state)
        #expect(state.outputStream == ["Hello, world!"])
        #expect(state.pointer.index == 1)
    }

    @Test func `step appends multiple text nodes in order`() throws {
        let container = ContainerNode(
            children: [.text("Line "), .text("one")],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        _ = try walker.step(in: container, state: &state)
        _ = try walker.step(in: container, state: &state)
        #expect(state.outputStream == ["Line ", "one"])
    }

    // B3: .newline appends "\n" to outputStream
    @Test func `step appends newline sentinel to outputStream for newline node`() throws {
        let container = ContainerNode(
            children: [.text("Line"), .newline],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        _ = try walker.step(in: container, state: &state)
        _ = try walker.step(in: container, state: &state)
        #expect(state.outputStream == ["Line", "\n"])
    }

    // B3a–c: newlines are de-duplicated and never lead (issue #26, reference
    // StoryState.PushToOutputStreamIndividual)
    @Test(arguments: [
        ([NodeKind.newline], [OutputItem]()),
        ([.text("Line"), .newline, .newline], ["Line", "\n"]),
        ([.text("Line"), .newline, .text("  "), .newline], ["Line", "\n", "  "]),
        ([.text("  "), .newline], ["  ", "\n"]),
    ])
    func `newline is dropped when the output is empty or already ends in a newline`(
        children: [NodeKind], expected: [OutputItem]
    ) throws {
        let container = ContainerNode(children: children, namedContent: [:], flags: 0, name: nil)
        let walker = TreeWalker()
        var state = StoryState()
        while try walker.step(in: container, state: &state) != nil {}
        #expect(state.outputStream == expected)
    }

    // B4: controlCommand "done"/"end" sets isEnded = true
    @Test(arguments: ["done", "end"])
    func `step sets isEnded to true for done or end control command`(command: String) throws {
        let container = ContainerNode(
            children: [.controlCommand(command)],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        _ = try walker.step(in: container, state: &state)
        #expect(state.isEnded == true)
    }

    // B6: "out" suppresses the void value — emits nothing to the output stream
    @Test func `out control command skips a void value and does not emit it to output`() throws {
        let walker = TreeWalker()
        var state = StoryState()
        // Push the void value (C# Runtime.Void) onto the eval stack
        state.evalStack.append(.void)
        try walker.dispatchNode(.controlCommand("out"), state: &state)
        #expect(state.outputStream.isEmpty, "out must not emit a void value to outputStream")
        #expect(state.evalStack.isEmpty, "a void value must be consumed from evalStack by out")
    }

    @Test func `out control command emits non-void value to output stream`() throws {
        let walker = TreeWalker()
        var state = StoryState()
        state.evalStack.append(.int(42))
        try walker.dispatchNode(.controlCommand("out"), state: &state)
        #expect(state.outputStream == ["42"])
    }

    // B7: .variablePointer node pushes a pointer value onto evalStack
    @Test func `variablePointer node pushes pointer value with correct name onto evalStack`() throws {
        let walker = TreeWalker()
        var state = StoryState()
        try walker.dispatchNode(.variablePointer(name: "score", contextIndex: -1), state: &state)
        if case .variablePointer(let name, let contextIndex) = state.evalStack.last {
            #expect(name == "score")
            #expect(contextIndex == -1)
        } else {
            Issue.record("Expected .variablePointer on evalStack but got \(String(describing: state.evalStack.last))")
        }
    }

    @Test func `variablePointer node pushes exactly one item onto evalStack`() throws {
        let walker = TreeWalker()
        var state = StoryState()
        try walker.dispatchNode(.variablePointer(name: "x", contextIndex: -1), state: &state)
        #expect(state.evalStack.count == 1)
    }

    // B8: variable assignment where stored value is a pointer mutates the pointed-to global
    @Test func `variableAssignment to pointer-holding variable mutates the pointed-to global`() throws {
        let walker = TreeWalker()
        var state = StoryState()
        // Set up: global "score" = 0, temp "total" holds a pointer to "score"
        state.variablesState["score"] = .int(0)
        state.variablesState["total"] = .variablePointer(name: "score", contextIndex: -1)
        // Push 10 to evalStack (the value to assign via the pointer)
        state.evalStack.append(.int(10))
        // Non-global assignment to "total" (re-assignment, isGlobal: false)
        try walker.dispatchNode(.variableAssignment(name: "total", isGlobal: false), state: &state)
        // "score" global must be updated to 10
        #expect(state.variablesState["score"] == .int(10))
    }

    @Test func `variableAssignment to pointer-holding variable does not overwrite the pointer itself`() throws {
        let walker = TreeWalker()
        var state = StoryState()
        state.variablesState["score"] = .int(0)
        state.variablesState["total"] = .variablePointer(name: "score", contextIndex: -1)
        state.evalStack.append(.int(10))
        try walker.dispatchNode(.variableAssignment(name: "total", isGlobal: false), state: &state)
        // "total" must still hold the pointer (not be replaced with 10)
        if case .variablePointer(let name, _) = state.variablesState["total"] {
            #expect(name == "score")
        } else {
            Issue.record("Expected total to remain a pointer but got \(String(describing: state.variablesState["total"]))")
        }
    }
}
