// @acceptance @real-io
//
// Issue #29 — a value printed (`out`) inside a string (`str`…`/str`) or a tag
// (`#`…`/#`) belongs to that string or tag, as literal text there does. The
// reference sends everything to the output stream and collects the span back
// at its end (Story.cs EndString ~1394, EndTag ~1315), so a printed value is
// part of the span; InkSwift accumulates spans separately, so `out` must too.
//
// The fixture puts a line after the string and after the tagged line: a value
// that leaked into the output would show up in one of them.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Engine — a value printed inside a string or tag")
struct Engine_OutputInsideSpanTests {

    @Test func `a printed value stays inside its string and tag, matching the reference`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON("runtime-out-inside-string-and-tag"))
        var lines: [String] = []
        var tags: [[String]] = []

        while story.canContinue && lines.count < 20 {
            lines.append(story.`continue`())
            tags.append(story.currentTags)
        }

        #expect(lines == [
            "Before the string.\n",
            "After the string.\n",
            "The built string is value 8.\n",
            "A tagged line.\n",
            "After the tag.\n",
        ])
        // Only the tagged line's own tags: InkSwift keeps a line's tags until the
        // next choice, where the reference clears them per line — a separate gap.
        #expect(tags.prefix(4) == [[], [], [], ["pic8.jpg"]])
        #expect(story.currentChoices.map(\.text) == ["Onward"])
    }
}
