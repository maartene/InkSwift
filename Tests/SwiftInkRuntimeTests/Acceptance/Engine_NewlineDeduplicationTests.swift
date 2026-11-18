// @acceptance @real-io
//
// Issue #26 — the runtime de-duplicates newlines as it writes them, so
// inklecate JSON with nested blocks plays no extra blank lines. inklecate puts
// a `"\n"` after each block's rejoin point (`"nop","\n"`) and at the start of
// each branch, so an inner block's own trailing `"\n"` is followed by more. The
// reference drops a newline when the output already ends in one or holds no
// content yet (StoryState.cs PushToOutputStreamIndividual).
//
// The lines are compared untrimmed: a doubled newline is exactly the defect,
// and the other playthrough helpers trim it away. Every nested block is
// followed by prose in the same scope, and the story ends at a choice, so a
// rejoin newline is always in play.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Engine — newline de-duplication")
struct Engine_NewlineDeduplicationTests {

    /// Continue until the story cannot, without choosing: raw `continue()` results.
    private func rawLines(_ story: Story) -> [String] {
        var lines: [String] = []
        while story.canContinue && lines.count < 100 {
            lines.append(story.`continue`())
        }
        return lines
    }

    @Test func `inklecate JSON with nested blocks plays one newline per line, matching the reference`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON("runtime-newline-dedup-nested-blocks"))

        #expect(rawLines(story) == [
            "Inner.\n",
            "After the nested block.\n",
            "Outer.\n",
            "B.\n",
            "After the inner block.\n",
            "After the outer block.\n",
        ])
        #expect(story.currentChoices.map(\.text) == ["Onward"])

        try story.chooseChoice(at: 0)

        #expect(rawLines(story) == ["Onward\n", "Chosen.\n"])
    }
}
