// @regression @real-io @kpi-1
//
// S4 regression — Issue #8's literal reproduction: a tag written AFTER the
// choice-only bracket, `* [Choice A] # sidequest`.
//
// This is NOT a choice tag. Verified against inklecate 1.2.1 (see the committed
// oracle): the tag lowers INTO the outcome container as an ordinary content tag
// on the picked continuation —
//
//   {"c-0":["^ ","#","^sidequest","/#","\n",{"->":"goal"}, …]}
//
// so `Choice.tags` correctly stays empty and the tag surfaces in
// `Story.currentTags` once the choice is taken. (A genuine choice tag is written
// INSIDE the bracket, `* [Choice A # sidequest]`, and is covered by the S4
// ceiling suite.)
//
// Defect this pins (fixed 2026-08-09): `InkParser.outcomeStatement` only routed
// an outcome through the tag-aware `parseContentSegments` when it contained `{`;
// otherwise it became a raw `.text` statement. So the post-bracket `# sidequest`
// was emitted as LITERAL TEXT — the visible-garbage symptom reported in #8 —
// and never became a tag. Adding an unrelated `{…}` to the same line made the
// tag work, which isolated the cause.
//
// The engine side already handled this correctly: the oracle-json test below
// passed before the fix as well, and is kept as a guard.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler S4 — Post-bracket choice tags attach to the continuation")
struct Compiler_S4_ChoiceContinuationTagTests {

    /// Play to the choice, take `index`, and return the continuation's lines and
    /// the tags reported for each of them.
    private func takeChoice(_ story: Story, _ index: Int) throws -> (lines: [String], tags: [[String]]) {
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: index)
        var lines: [String] = []
        var tags: [[String]] = []
        while story.canContinue {
            lines.append(story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines))
            tags.append(story.currentTags)
        }
        return (lines, tags)
    }

    // Scenario: compiled natively, the post-bracket tag becomes a tag on the
    // continuation rather than literal output text.
    @Test
    func `a post-bracket tag becomes a continuation tag when compiled natively`() throws {
        let source = try CompilerOracle.source("compile-choice-continuation-tag")
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        let result = try takeChoice(story, 0)

        #expect(result.tags.contains { $0.contains("sidequest") })
        #expect(result.lines.contains { $0.contains("sidequest") } == false)
        #expect(result.lines.contains("Goal reached."))
    }

    // Scenario: the same story loaded from the inklecate oracle json. This is the
    // engine half and already worked — kept as a guard so a future engine change
    // cannot regress it silently.
    @Test
    func `a post-bracket tag becomes a continuation tag when loaded from the oracle`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON("compile-choice-continuation-tag"))

        let result = try takeChoice(story, 0)

        #expect(result.tags.contains { $0.contains("sidequest") })
        #expect(result.lines.contains { $0.contains("sidequest") } == false)
    }

    // Scenario: `Choice.tags` stays EMPTY for this spelling — the tag belongs to
    // the continuation, not to the choice. Issue #8 expected it on the choice;
    // inklecate says otherwise, and the oracle is authoritative.
    @Test
    func `a post-bracket tag does not populate Choice-tags`() throws {
        let source = try CompilerOracle.source("compile-choice-continuation-tag")
        let story = Story(blueprint: try InkCompiler.compile(source: source))
        while story.canContinue { _ = story.`continue`() }

        #expect(story.currentChoices.map(\.text) == ["Choice A", "Choice B"])
        #expect(story.currentChoices.allSatisfy { $0.tags.isEmpty })
    }

    // Scenario: full played-output equivalence with the oracle for both choices.
    @Test(arguments: [0, 1])
    func `the played output matches the oracle for either choice`(choice: Int) throws {
        let result = try CompilerOracle.compileAndPlay(
            "compile-choice-continuation-tag", choiceScript: [choice]
        )

        #expect(result.native == result.oracle)
    }
}
