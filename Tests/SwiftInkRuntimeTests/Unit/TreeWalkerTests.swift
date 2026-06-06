// Test Budget: 8 distinct behaviors x 2 = 16 max unit tests
// Behaviors:
//   B1 — Container exhaustion returns nil
//   B2 — .text node appends to outputStream
//   B3 — .newline appends "\n" to outputStream (line boundary signal)
//   B4 — .controlCommand "done"/"end" sets isEnded = true
//   B5 — .divert updates containerPath and resets index to 0
//   B6 — "out" control command suppresses void sentinel (does not emit "void" text)
//   B7 — .variablePointer node pushes a pointer sentinel onto evalStack
//   B8 — variable assignment via pointer mutates the pointed-to global variable

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
            children: [.divert(target: "Knot1", isConditional: false, isVariable: false)],
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
            children: [.divert(target: "Knot2.stitch1", isConditional: false, isVariable: false)],
            namedContent: [:], flags: 0, name: nil
        )
        let walker = TreeWalker()
        var state = StoryState()
        _ = walker.step(in: container, state: &state)
        #expect(state.pointer.containerPath == ["Knot2", "stitch1"])
        #expect(state.pointer.index == 0)
    }

    // B6: "out" suppresses void sentinel — does not emit "void" text to output stream
    @Test func `out control command suppresses void sentinel and does not emit void to output`() {
        let walker = TreeWalker()
        var state = StoryState()
        // Push the void sentinel (string "void") onto the eval stack
        state.evalStack.append(.string("void"))
        walker.dispatchNode(.controlCommand("out"), state: &state)
        #expect(state.outputStream.isEmpty, "out must not emit the void sentinel to outputStream")
        #expect(state.evalStack.isEmpty, "void sentinel must be consumed from evalStack by out")
    }

    @Test func `out control command emits non-void value to output stream`() {
        let walker = TreeWalker()
        var state = StoryState()
        state.evalStack.append(.int(42))
        walker.dispatchNode(.controlCommand("out"), state: &state)
        #expect(state.outputStream == ["42"])
    }

    // B7: .variablePointer node pushes a pointer value onto evalStack
    @Test func `variablePointer node pushes pointer value with correct name onto evalStack`() {
        let walker = TreeWalker()
        var state = StoryState()
        walker.dispatchNode(.variablePointer(name: "score", contextIndex: -1), state: &state)
        if case .variablePointer(let name, let contextIndex) = state.evalStack.last {
            #expect(name == "score")
            #expect(contextIndex == -1)
        } else {
            Issue.record("Expected .variablePointer on evalStack but got \(String(describing: state.evalStack.last))")
        }
    }

    @Test func `variablePointer node pushes exactly one item onto evalStack`() {
        let walker = TreeWalker()
        var state = StoryState()
        walker.dispatchNode(.variablePointer(name: "x", contextIndex: -1), state: &state)
        #expect(state.evalStack.count == 1)
    }

    // B8: variable assignment where stored value is a pointer mutates the pointed-to global
    @Test func `variableAssignment to pointer-holding variable mutates the pointed-to global`() {
        let walker = TreeWalker()
        var state = StoryState()
        // Set up: global "score" = 0, temp "total" holds a pointer to "score"
        state.variablesState["score"] = .int(0)
        state.variablesState["total"] = .variablePointer(name: "score", contextIndex: -1)
        // Push 10 to evalStack (the value to assign via the pointer)
        state.evalStack.append(.int(10))
        // Non-global assignment to "total" (re-assignment, isGlobal: false)
        walker.dispatchNode(.variableAssignment(name: "total", isGlobal: false), state: &state)
        // "score" global must be updated to 10
        #expect(state.variablesState["score"] == .int(10))
    }

    @Test func `variableAssignment to pointer-holding variable does not overwrite the pointer itself`() {
        let walker = TreeWalker()
        var state = StoryState()
        state.variablesState["score"] = .int(0)
        state.variablesState["total"] = .variablePointer(name: "score", contextIndex: -1)
        state.evalStack.append(.int(10))
        walker.dispatchNode(.variableAssignment(name: "total", isGlobal: false), state: &state)
        // "total" must still hold the pointer (not be replaced with 10)
        if case .variablePointer(let name, _) = state.variablesState["total"] {
            #expect(name == "score")
        } else {
            Issue.record("Expected total to remain a pointer but got \(String(describing: state.variablesState["total"]))")
        }
    }
}
