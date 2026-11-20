// @acceptance @real-io
//
// #28 (reference-fidelity-backlog step 02-04, ADR-020 §5) — running out of
// content reports the C# error. When a continue() stops without a safe exit
// (`done`, `end`, a forced end) and without choices, C# Story.ContinueInternal
// (Story.cs ~502-516) reports a message chosen by the call-stack top. inkjs
// reports the same text behind its "RUNTIME ERROR: (<pointer>): " prefix;
// InkSwift reports the bare message (ADR-017).
//
// A ran-out fixture ends by definition, so each one plays real prose before
// the stop, and the test asserts that prose, then the error.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Engine — #28 running out of content reports the C# error")
struct Engine_EndOfContentErrorTests {

    static let ranOutMessage = "ran out of content. Do you need a '-> DONE' or '-> END'?"
    static let tunnelMessage = "unexpectedly reached end of content. Do you need a '->->' to return from a tunnel?"

    /// Continue until the story cannot, without choosing: trimmed non-empty lines.
    private func playUntilStopped(_ story: Story) -> [String] {
        var lines: [String] = []
        var steps = 0
        while story.canContinue && steps < 100 {
            let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty == false { lines.append(line) }
            steps += 1
        }
        return lines
    }

    private static func runtimeStory(_ fixture: String) throws -> Story {
        try Story(json: try CompilerOracle.oracleJSON(fixture))
    }

    private static func nativeStory(_ fixture: String) throws -> Story {
        Story(blueprint: try InkCompiler.compile(source: try CompilerOracle.source(fixture)))
    }

    private static func nativeStory(source: String) throws -> Story {
        Story(blueprint: try InkCompiler.compile(source: source))
    }

    @Test func `a function body that runs out over a tunnel frame reports the tunnel message`() throws {
        let story = try Self.runtimeStory("pop-function-exhaustion-over-tunnel")

        let lines = playUntilStopped(story)

        #expect(lines == ["Before the tunnel.", "Inside the tunnel.", "Inside f."])
        #expect(story.currentErrors == [Self.tunnelMessage])
    }

    @Test(arguments: ["runtime", "native"])
    func `a knot that runs out on an empty stack reports the ran-out message after its prose`(path: String) throws {
        let story = path == "runtime"
            ? try Self.runtimeStory("issue28-ran-out-in-knot")
            : try Self.nativeStory("issue28-ran-out-in-knot")

        let lines = playUntilStopped(story)

        #expect(lines == ["Before the knot.", "Inside the knot."])
        #expect(story.currentErrors == [Self.ranOutMessage])
        #expect(story.canContinue == false)
    }

    @Test(arguments: [
        "Hello.\n-> DONE\n",
        "Hello.\n-> END\n",
        "Hello.\n* A choice\n    -> END\n",
        "Hello.\n-> knot\n== knot ==\nInside.\n* A choice\n    -> DONE\n",
    ])
    func `done, end and a stop at a choice point report no end-of-content error`(source: String) throws {
        let story = try Self.nativeStory(source: source)

        let lines = playUntilStopped(story)

        #expect(lines.isEmpty == false)
        #expect(story.currentErrors.isEmpty)
    }

    // inklecate puts this labelled gather in the root weave's content array, so
    // a divert to it by name must fall out into the parent when it runs out, as
    // C# IncrementContentPointer does, and reach the root's `done`. inklecate -p
    // ends this path cleanly; before the fix the runtime ran out instead.
    //
    // Both paths (step 02-07): the native compiler keeps the gather in a named
    // root container, so it puts the root's `done` after the gather's choice
    // points, where inklecate's layout falls out into that `done`.
    @Test(arguments: ["runtime", "native"])
    func `a labelled root gather with its choices used up ends safely on both paths`(path: String) throws {
        let story = path == "runtime"
            ? try Self.runtimeStory("divert-to-labelled-root-gather")
            : try Self.nativeStory("divert-to-labelled-root-gather")

        let lines = try CompilerOracle.play(story, choiceScript: [1])

        #expect(lines == ["Start of the story.", "Leaving the top."])
        #expect(story.engine.didSafeExit)
        #expect(story.currentErrors.isEmpty)
    }

    // ADR-017: an error is unrecoverable, so it is never written to a save.
    @Test func `the end-of-content error is never saved and restoreState clears it`() throws {
        let story = try Self.runtimeStory("issue28-ran-out-in-knot")
        _ = playUntilStopped(story)
        try #require(story.currentErrors == [Self.ranOutMessage])

        let saved = try story.saveState()
        try story.restoreState(saved)

        #expect(String(decoding: saved, as: UTF8.self).contains("ran out") == false)
        #expect(story.currentErrors.isEmpty)
    }

    @Test func `moveToKnot clears the end-of-content error and the knot plays again`() throws {
        let story = try Self.runtimeStory("issue28-ran-out-in-knot")
        _ = playUntilStopped(story)
        try #require(story.currentErrors == [Self.ranOutMessage])

        try story.moveToKnot("somewhere")

        #expect(story.currentErrors.isEmpty)
        #expect(playUntilStopped(story) == ["Inside the knot."])
        #expect(story.currentErrors == [Self.ranOutMessage])
    }
}
