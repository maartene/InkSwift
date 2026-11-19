// @acceptance @real-io
//
// #28 — `-> END` discards pending choices; `-> DONE` keeps them.
//
// C# `end` calls StoryState.ForceEnd (StoryState.cs ~1185-1195), which resets
// the call stack, removes the current choices, nulls the pointer and sets
// didSafeExit; `done` only stops the flow and keeps the choices (Story.cs
// ~1544-1566). A choice generated earlier in the same continue — here inside a
// block conditional, the inkle/ink#978 shape — is therefore never offered when
// the flow then reaches `-> END`. InkSwift kept it (ADR-020 §4).
//
// Both outcomes were probed with `inklecate -p` (1.2.1) and with the reference
// runtime through the InkSwift JS bridge (`InkStory`, macOS only, below). Each
// fixture continues past the conditional and past the choice: the END variant
// asserts none of the choice's content plays, the DONE variant that it does,
// followed by prose and a second choice.

import Testing
import Foundation
@testable import SwiftInkRuntime
#if os(macOS)
import InkSwift
#endif

@Suite struct Engine_FlowEndStateTests {

    private static let endFixture = "issue28-end-discards-choices"
    private static let doneFixture = "issue28-done-keeps-choices"

    /// `inklecate -p` (which prints a chosen option's echoed text after its
    /// `?> ` prompt): the lines before the flow stops at `-> END` / `-> DONE`.
    private static let linesBeforeStop = ["Before the block.", "Inside the arm.", "After the block."]

    private static func story(_ fixture: String) throws -> Story {
        try Story(json: try CompilerOracle.oracleJSON(fixture))
    }

    private func continueMaximally(_ story: Story) -> [String] {
        var lines: [String] = []
        while story.canContinue {
            let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty == false { lines.append(line) }
        }
        return lines
    }

    @Test func `-> END after a generated choice discards it and ends the story`() throws {
        let story = try Self.story(Self.endFixture)

        let lines = continueMaximally(story)

        #expect(lines == Self.linesBeforeStop)
        #expect(story.currentChoices.isEmpty)
        #expect(story.canContinue == false)
        #expect(story.currentErrors.isEmpty)
    }

    @Test func `-> DONE after a generated choice keeps it and choosing it plays its content`() throws {
        let story = try Self.story(Self.doneFixture)

        #expect(continueMaximally(story) == Self.linesBeforeStop)
        #expect(story.currentChoices.map(\.text) == ["A choice that DONE keeps"])

        try story.chooseChoice(at: 0)
        #expect(continueMaximally(story) == ["A choice that DONE keeps", "Chosen content.", "After the choice."])
        #expect(story.currentChoices.map(\.text) == ["Onward"])

        try story.chooseChoice(at: 0)
        #expect(continueMaximally(story) == ["Onward", "Last line."])
        #expect(story.currentErrors.isEmpty)
    }

    @Test func `a save after -> END keeps isEnded and carries no flow-end reason`() throws {
        let story = try Self.story(Self.endFixture)
        _ = continueMaximally(story)

        let data = try story.saveState()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["isEnded"] as? Bool == true)
        let wire = try #require(String(data: data, encoding: .utf8))
        #expect(wire.contains("safeExit") == false)
        #expect(wire.contains("stopReason") == false)

        let restored = try Self.story(Self.endFixture)
        try restored.restoreState(data)
        #expect(restored.canContinue == false)
        #expect(restored.currentChoices.isEmpty)
    }

    #if os(macOS)
    /// The reference runtime, through the JS bridge, agrees on both shapes.
    @Test(arguments: [(endFixture, [String]()), (doneFixture, ["A choice that DONE keeps"])])
    func `the JavaScript runtime offers the same choices after -> END and -> DONE`(
        fixture: String, expectedChoices: [String]
    ) throws {
        let oracle = InkStory()
        oracle.loadStory(json: try CompilerOracle.oracleJSON(fixture))
        while oracle.canContinue { oracle.continueStory() }

        let native = try Self.story(fixture)
        _ = continueMaximally(native)

        #expect(oracle.options.map(\.text) == expectedChoices)
        #expect(native.currentChoices.map(\.text) == expectedChoices)
    }
    #endif
}
