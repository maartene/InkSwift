// @acceptance @real-io
//
// #30 — `currentTags` belong to the line `continue()` returned.
//
// The reference derives `currentTags` from the output stream, where tags sit
// at their position among the text (StoryState.cs currentTags ~355), and resets
// the output at the start of every Continue (Story.cs ResetOutput ~444). A tag
// that follows a newline starts the next line (Story.cs ~689-718). InkSwift
// kept tags in a separate list that only a choice cleared, so a tag stuck to
// every later line (ADR-020 §1-3).
//
// Every line and tag set below was probed with `inklecate -p` (1.2.1) on
// issue30-per-line-tags.ink. The fixture continues past each construct: an
// untagged line after a tagged one, lines that start with a tag (one reached
// through a divert), glue next to a tag, a tagged
// line inside a choice body, then more prose and a second choice.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct Engine_PerLineTagsTests {

    private static let fixture = "issue30-per-line-tags"

    private struct TaggedLine: Equatable, CustomStringConvertible {
        let text: String
        let tags: [String]
        var description: String { "\(text) \(tags)" }
    }

    /// `inklecate -p` on the fixture, choosing the first option each time. (The
    /// player prints a chosen option's echoed text after its `?> ` prompt.)
    private static let oracle: [TaggedLine] = [
        TaggedLine(text: "Line one.", tags: ["t1"]),
        TaggedLine(text: "An untagged line.", tags: []),
        TaggedLine(text: "A line that starts with a tag.", tags: ["t2"]),
        TaggedLine(text: "Another line that starts with a tag.", tags: ["t6"]),
        TaggedLine(text: "Glued on.", tags: ["t3"]),
        TaggedLine(text: "Before glue", tags: []),
        TaggedLine(text: "after a tag.", tags: ["t5"]),
        TaggedLine(text: "After glue.", tags: ["t7"]),
        TaggedLine(text: "Pick me", tags: []),
        TaggedLine(text: "Inside the choice.", tags: ["t4"]),
        TaggedLine(text: "Still inside.", tags: []),
        TaggedLine(text: "After the choice.", tags: []),
        TaggedLine(text: "More prose.", tags: []),
        TaggedLine(text: "Onward", tags: []),
    ]

    private static func oracleStory() throws -> Story {
        try Story(json: try CompilerOracle.oracleJSON(fixture))
    }

    private static func nativeStory() throws -> Story {
        Story(blueprint: try InkCompiler.compile(source: try CompilerOracle.source(fixture)))
    }

    /// Play choosing the first option, recording each non-empty line with the
    /// tags reported right after `continue()` returned it.
    private static func playTagged(_ story: Story) throws -> [TaggedLine] {
        var lines: [TaggedLine] = []
        var steps = 0
        while steps < 200 {
            steps += 1
            if story.canContinue {
                let text = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { lines.append(TaggedLine(text: text, tags: story.currentTags)) }
            } else if !story.currentChoices.isEmpty {
                try story.chooseChoice(at: 0)
            } else {
                break
            }
        }
        return lines
    }

    private static func wireObject(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // Scenario: #30 currentTags belong to the line continue() returned.
    @Test func `every line reports only its own tags, from inklecate json`() throws {
        #expect(try Self.playTagged(Self.oracleStory()) == Self.oracle)
    }

    @Test func `every line reports only its own tags, compiled natively`() throws {
        #expect(try Self.playTagged(Self.nativeStory()) == Self.oracle)
    }

    // F2: moveToKnot starts a fresh line; the tags of the last line do not follow.
    @Test func `moveToKnot to a knot whose first line is untagged reports no tags`() throws {
        let story = try Self.oracleStory()
        _ = story.`continue`()
        #expect(story.currentTags == ["t1"])

        try story.moveToKnot("plain")

        #expect(story.currentTags == [])
        #expect(story.`continue`() == "A plain knot line.\n")
        #expect(story.currentTags == [])
        #expect(story.`continue`() == "More of the plain knot.\n")
        #expect(story.currentTags == ["t8"])
    }

    // F2: after chooseChoice the first returned line carries only its own tags.
    @Test func `after chooseChoice the first line carries only its own tags`() throws {
        let story = try Self.oracleStory()
        while story.canContinue { _ = story.`continue`() }
        #expect(story.currentTags == ["t7"])

        try story.chooseChoice(at: 0)

        #expect(story.currentTags == [])
        #expect(story.`continue`() == "Pick me\n")
        #expect(story.currentTags == [])
        #expect(story.`continue`() == "Inside the choice.\n")
        #expect(story.currentTags == ["t4"])
    }

    // Found in 01-01: the line before a choice point was returned with no
    // choices offered yet; they appeared only on a further continue(). C# steps
    // on after the line until the pointer runs out at the choices, so they are
    // available as soon as Continue returns that line. Same on both paths: the
    // lookahead flushed at the `/ev` that ends the choice's eval block.
    @Test(arguments: [
        ("issue34-space-before-tag", "Next.", ["Onward"]),
        ("issue30-per-line-tags", "After glue.", ["Pick me"]),
    ])
    func `the line before a choice point is returned with its choices offered`(
        fixture: String, lineBeforeChoice: String, choices: [String]
    ) throws {
        for story in [
            try Story(json: try CompilerOracle.oracleJSON(fixture)),
            Story(blueprint: try InkCompiler.compile(source: try CompilerOracle.source(fixture))),
        ] {
            var line = ""
            while story.canContinue && line != lineBeforeChoice {
                line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            #expect(line == lineBeforeChoice)
            #expect(story.currentChoices.map(\.text) == choices)
            #expect(story.canContinue == false)
        }
    }

    // A choice collected while stepping past a line into more text is offered
    // only once that text is returned: C# rewinds such a Continue to the newline,
    // choice point included (Story.cs ContinueSingleStep, the snapshot at the last
    // newline). compile-choice-in-conditional-arm: the else arm prints "Other.",
    // offers its choice, and the knot goes on to "After the else block.".
    @Test(arguments: [true, false])
    func `a choice is not offered while the line after it is still to be returned`(fromJSON: Bool) throws {
        let fixture = "compile-choice-in-conditional-arm"
        let story = fromJSON
            ? try Story(json: try CompilerOracle.oracleJSON(fixture))
            : Story(blueprint: try InkCompiler.compile(source: try CompilerOracle.source(fixture)))
        var line = ""
        while story.canContinue && line != "Other." {
            line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        #expect(line == "Other.")
        #expect(story.currentChoices.isEmpty)
        #expect(story.canContinue)
        #expect(story.`continue`() == "After the else block.\n")
        #expect(story.currentChoices.map(\.text) == ["From the else arm"])
    }

    // ADR-020 §6: a tag the lookahead already collected for the next line is
    // saved at its stream position and restored with that line.
    // issue30-lookahead-tag.ink diverts after a tagged line into a knot whose
    // first line starts with a dynamic tag (`# {leading}`): the divert defers
    // the flush, so the tag closes before the tagged line is returned. (inklecate
    // json only: the native compiler rejects a tag with inline logic.)
    private static func lookaheadStory() throws -> Story {
        try Story(json: try CompilerOracle.oracleJSON("issue30-lookahead-tag"))
    }

    @Test func `a pending lookahead tag is saved in outputStreamTags and restored with its line`() throws {
        let story = try Self.lookaheadStory()
        #expect(story.`continue`() == "A tagged line.\n")
        #expect(story.currentTags == ["t1"])

        let saved = try story.saveState()
        let wire = try Self.wireObject(saved)
        let pending = try #require(wire["outputStreamTags"] as? [[String: Any]])
        #expect(pending.count == 1)
        #expect(pending.first?["at"] as? Int == 0)
        #expect(pending.first?["text"] as? String == "t2")
        #expect(wire["outputStream"] as? [String] == ["A line that starts with a tag."])
        #expect(wire["currentTags"] as? [String] == ["t1"])

        let restored = try Self.lookaheadStory()
        try restored.restoreState(saved)
        #expect(restored.currentTags == ["t1"])
        #expect(restored.`continue`() == "A line that starts with a tag.\n")
        #expect(restored.currentTags == ["t2"])
        #expect(restored.`continue`() == "After it.\n")
        #expect(restored.currentTags == [])
    }

    // Glue stops at a tag, as C# `TrimNewlinesFromOutputStream` stops at a
    // control command: the lookahead (after a divert) collects `# {glued}` while
    // "After it." still ends in its newline, and the glue must not join them.
    @Test func `glue after a lookahead tag does not join the line before the tag`() throws {
        let story = try Self.lookaheadStory()
        var lines: [TaggedLine] = []
        while story.canContinue {
            lines.append(TaggedLine(text: story.`continue`(), tags: story.currentTags))
        }

        #expect(lines.suffix(2) == [
            TaggedLine(text: "After it.\n", tags: []),
            TaggedLine(text: "Glued after a tag.\n", tags: ["t9"]),
        ])
        #expect(story.currentChoices.map(\.text) == ["Onward"])
    }

    // ADR-020 §3 prologue: a continue() that returns no line reports no tags.
    // (`inklecate -p` prints `Tagged.` with `# tags: t` and nothing after it.)
    @Test func `a continue that returns no line clears the last line's tags`() throws {
        let story = Story(blueprint: try InkCompiler.compile(source: "Tagged. # t\n~ temp x = 1\n-> DONE\n"))
        #expect(story.`continue`() == "Tagged.\n")
        #expect(story.currentTags == ["t"])

        while story.canContinue { #expect(story.`continue`() == "") }

        #expect(story.currentTags == [])
    }

    @Test func `a save with no pending tag omits outputStreamTags and keeps the line's tags`() throws {
        let story = try Self.oracleStory()
        #expect(story.`continue`() == "Line one.\n")

        let wire = try Self.wireObject(story.saveState())

        #expect(wire["outputStreamTags"] == nil)
        #expect(wire["currentTags"] as? [String] == ["t1"])
    }
}
