import Testing
import Foundation
@testable import SwiftInkRuntime

/// Regression for the nested-weave softlock: after choosing a once-only `*`
/// sub-choice whose body diverts back to a named gather, the runtime must
/// re-present the remaining sibling sub-choices instead of softlocking.
///
/// Root cause (compiler, not engine): the `cass` knot opens with block
/// conditionals, so its whole weave is physically nested under
/// `cond*-end` continuation containers. The bare-named divert
/// `-> cass_ask_what_he_needs_information_gathering` is emitted using the
/// discovery pre-pass's PREDICTED FLAT path, which does not match the real
/// physically-nested container path, so the divert dead-ends and the choice
/// stack exhausts (canContinue=false, currentChoices empty).
@Suite("Repro Cass softlock")
struct ReproCassTests {

    private static let storyPath =
        "/Users/Maarten.Engels/Developer/SharedWorldYourStory/Sources/SharedWorldYourStory/Model/Data/poc-borrowed-light-script.ink"

    /// Build the `cass` knot, driven up to its first choice menu.
    private func cassStory() throws -> Story {
        let source = try String(contentsOf: URL(fileURLWithPath: Self.storyPath), encoding: .utf8)
        let story = Story(blueprint: try InkCompiler.compile(source: source))
        try story.moveToKnot("cass")
        story.continueMaximally()
        return story
    }

    @Test func `level-2 gather re-presents remaining sub-choices after a once-only sub-choice loops back`() throws {
        let story = try cassStory()

        // Level 1: "Ask what he needs." opens the sub-choice menu.
        try story.chooseChoice(at: 0)
        story.continueMaximally()

        let subChoiceTexts = story.currentChoices.map(\.text)
        #expect(subChoiceTexts == [
            "Ask what the story was about.",
            "Ask where to start looking.",
            "Ask about Linnea.",
            "Tell him you'll look into it.",
        ])

        // Level 2: "Ask what the story was about." diverts back to the named
        // gather `cass_ask_what_he_needs_information_gathering`.
        try story.chooseChoice(at: 0)
        story.continueMaximally()

        // The bug: the divert dead-ends, the stack exhausts, and the story
        // softlocks. The fix re-presents the 3 still-unused sub-choices.
        #expect(story.canContinue == false)
        #expect(story.currentChoices.map(\.text) == [
            "Ask where to start looking.",
            "Ask about Linnea.",
            "Tell him you'll look into it.",
        ])
    }

    @Test func `level-2 menu keeps offering still-unused options on each loop until only the END path remains`() throws {
        let story = try cassStory()

        try story.chooseChoice(at: 0) // Ask what he needs.
        story.continueMaximally()

        // Take "Ask where to start looking." — the 3 still-unused remain
        // (the END-bound "Tell him…" stays available until chosen).
        try story.chooseChoice(at: 1)
        story.continueMaximally()
        #expect(story.currentChoices.map(\.text) == [
            "Ask what the story was about.",
            "Ask about Linnea.",
            "Tell him you'll look into it.",
        ])

        // Take "Ask what the story was about." — 2 remain.
        try story.chooseChoice(at: 0)
        story.continueMaximally()
        #expect(story.currentChoices.map(\.text) == [
            "Ask about Linnea.",
            "Tell him you'll look into it.",
        ])

        // Take "Ask about Linnea." — only the END-bound choice remains.
        try story.chooseChoice(at: 0)
        story.continueMaximally()
        #expect(story.currentChoices.map(\.text) == [
            "Tell him you'll look into it.",
        ])

        // The final choice diverts to `-> END`; the story ends, no softlock.
        try story.chooseChoice(at: 0)
        story.continueMaximally()
        #expect(story.canContinue == false)
        #expect(story.currentChoices.isEmpty)
    }
}
