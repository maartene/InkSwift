// Test Budget: 11 distinct behaviors x 2 = 22 max unit tests
// Behaviors:
//   B1 — init(root:) does not crash; canContinue is true for non-empty root
//   B2 — stepToNextLine() returns text collected from .text + .newline nodes
//   B3 — isEnded becomes true after a "done" control command; canContinue is false
//   B4 — chooseChoice(at:) throws StoryError.invalidChoiceIndex for out-of-range index
//   B5 — saveState() returns non-empty Data after at least one step has been taken
//   B6 — restoreState(_:) throws StoryError.invalidStateData for undecodable input
//   B7 — restoreState(saveState()) restores engine to an equivalent state
//   B8 — restoreState(_:) throws StoryError.invalidStateData for valid JSON not decoding to StoryState
//   B9 — function call via f() divert returns to caller and leaves return value on eval stack
//   B10 — tunnel entry (->t->) jumps to sub_room and produces sub_room content
//   B11 — tunnel return (->->) resumes execution after the tunnel divert in the caller

import Testing
import Foundation
@testable import SwiftInkRuntime

// MARK: - Test helpers

private func makeContainer(_ children: NodeKind...) -> ContainerNode {
    ContainerNode(children: children, namedContent: [:], flags: 0, name: nil)
}

@Suite("InkEngine")
struct InkEngineTests {

    // B1a: init does not crash and canContinue is true for a non-empty root
    @Test func `init with non-empty root does not crash and canContinue is true`() {
        let container = makeContainer(.text("Hello"), .newline)
        let engine = InkEngine(root: container)
        #expect(engine.canContinue == true)
    }

    // B1b: canContinue is false for an empty root container
    @Test func `canContinue is false for empty root container`() {
        let container = makeContainer()
        let engine = InkEngine(root: container)
        #expect(engine.canContinue == false)
    }

    // B2a: stepToNextLine returns text from a .text + .newline sequence (includes trailing \n)
    @Test func `stepToNextLine returns text from text and newline nodes`() {
        let container = makeContainer(.text("Hello, world"), .newline)
        let engine = InkEngine(root: container)
        let line = engine.stepToNextLine()
        #expect(line == "Hello, world\n")
    }

    // B2b: currentText reflects the last completed line after step() (includes trailing \n)
    @Test func `step advances and currentText is the last completed line`() {
        let container = makeContainer(.text("First line"), .newline)
        let engine = InkEngine(root: container)
        engine.step()
        #expect(engine.currentText == "First line\n")
    }

    // B3a: isEnded is true after a "done" control command; canContinue is false
    @Test func `canContinue is false after done control command`() {
        let container = makeContainer(.controlCommand("done"))
        let engine = InkEngine(root: container)
        engine.step()
        #expect(engine.canContinue == false)
    }

    // B3b: canContinue is false after an "end" control command
    @Test func `canContinue is false after end control command`() {
        let container = makeContainer(.controlCommand("end"))
        let engine = InkEngine(root: container)
        engine.step()
        #expect(engine.canContinue == false)
    }

    // B4a: chooseChoice(at:) throws invalidChoiceIndex for index beyond range
    @Test func `chooseChoice throws invalidChoiceIndex for out-of-range index`() throws {
        let container = makeContainer(.text("Start"), .newline)
        let engine = InkEngine(root: container)
        #expect(throws: StoryError.invalidChoiceIndex(99)) {
            try engine.chooseChoice(at: 99)
        }
    }

    // B4b: chooseChoice(at:) throws invalidChoiceIndex for negative index
    @Test func `chooseChoice throws invalidChoiceIndex for negative index`() throws {
        let container = makeContainer(.text("Start"), .newline)
        let engine = InkEngine(root: container)
        #expect(throws: StoryError.invalidChoiceIndex(-1)) {
            try engine.chooseChoice(at: -1)
        }
    }

    // B5: saveState() returns non-empty Data after at least one step has been taken
    @Test func `saveState returns non-empty Data after one step`() throws {
        let container = makeContainer(.text("Hello"), .newline, .controlCommand("done"))
        let engine = InkEngine(root: container)
        engine.step()
        let data = try engine.saveState()
        #expect(data.count > 0)
    }

    // B6: restoreState(_:) throws invalidStateData for garbage bytes
    @Test func `restoreState throws invalidStateData for undecodable input`() {
        let container = makeContainer(.text("Hello"), .newline)
        let engine = InkEngine(root: container)
        let garbage = Data([0xFF, 0xFE, 0xAB, 0xCD])
        #expect(throws: StoryError.invalidStateData) {
            try engine.restoreState(garbage)
        }
    }

    // B7: restoreState(saveState()) restores engine to an equivalent state
    // Uses two-line container: after reading first line, save state.
    // Restore into fresh engine — it must NOT re-output the first line.
    // If containerStack is not rebuilt, the fresh engine restarts from the beginning.
    @Test func `restoreState from saveState does not re-emit already-consumed text`() throws {
        // Two-line story: "Line A" then "Line B" then done
        let container = makeContainer(
            .text("Line A"), .newline,
            .text("Line B"), .newline,
            .controlCommand("done")
        )
        let engine = InkEngine(root: container)

        // Step once: consume "Line A"
        let firstLine = engine.stepToNextLine()
        #expect(firstLine == "Line A\n")

        // Save state mid-story (after Line A, before Line B)
        let savedData = try engine.saveState()

        // Restore into a fresh engine at same root
        let freshEngine = InkEngine(root: container)
        try freshEngine.restoreState(savedData)

        // Fresh engine should produce "Line B" next, NOT "Line A" again
        let nextLine = freshEngine.stepToNextLine()
        #expect(nextLine == "Line B\n")
    }

    // B8: restoreState(_:) throws invalidStateData for valid JSON that doesn't decode to StoryState
    @Test func `restoreState throws invalidStateData for valid JSON not matching StoryState schema`() {
        let container = makeContainer(.text("Hello"), .newline)
        let engine = InkEngine(root: container)
        // Valid JSON object that is not a StoryState
        let wrongJSON = Data(#"{"foo": "bar", "baz": 42}"#.utf8)
        #expect(throws: StoryError.invalidStateData) {
            try engine.restoreState(wrongJSON)
        }
    }

    // B9: function call via f() divert executes function and returns caller output
    // Verifies that after a function call completes, the return value is available
    // and execution continues in the caller context.
    // Tested through the Story facade (driving port) using the real C3 fixture.
    @Test func `function call via f() divert executes function body and return value is available in caller`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice-c3-functions", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)
        let story = try Story(json: json)
        // Advance past "You enter." and choice presentation
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 0)  // "Calculate inline." → double(5) → "The result is 10."
        var lines: [String] = []
        while story.canContinue {
            let trimmed = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append(trimmed) }
        }
        #expect(lines.contains { $0.contains("The result is 10.") },
                "Function double(5) must return 10 and appear in output")
    }

    @Test func `void function call via f() divert does not emit void text into output`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice-c3-functions", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)
        let story = try Story(json: json)
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 2)  // "Void call inline." → setSideEffect() → "Done." (no "void")
        var lines: [String] = []
        while story.canContinue {
            let trimmed = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append(trimmed) }
        }
        #expect(lines.contains { $0.contains("Done.") })
        #expect(!lines.contains { $0.lowercased().contains("void") })
    }

    // B10: tunnel entry (->t->) diverts to sub_room and sub_room content is produced
    // Tested via Story facade using the real T1 fixture.
    @Test func `tunnel entry diverts to sub room and produces sub room content`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice-t1-tunnels", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)
        let story = try Story(json: json)
        _ = story.`continue`()  // "Before tunnel."
        let line2 = story.`continue`()  // must be "Sub room content."
        #expect(line2.contains("Sub room content."),
                "Tunnel entry must divert to sub_room and produce sub_room content")
    }

    // B11: tunnel return (->->) resumes execution after the ->t-> node in the caller
    // After tunnel body completes, "After tunnel." is the next line (not end-of-story).
    @Test func `tunnel return resumes caller execution and produces after-tunnel text`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice-t1-tunnels", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)
        let story = try Story(json: json)
        _ = story.`continue`()  // "Before tunnel."
        _ = story.`continue`()  // "Sub room content."
        let line3 = story.`continue`()  // must be "After tunnel."
        #expect(line3.contains("After tunnel."),
                "Tunnel return (->->) must resume caller context and produce after-tunnel text")
    }
}
