// @regression @real-io
//
// #34 — the whitespace before a `#` tag is trimmed only on its TRAILING side.
//
// The native parser trimmed the literal before a `#` on both sides, so on
// `{n > 0: A} after. # t` the literal " after. " lost its leading space and the
// line printed "Aafter." instead of inklecate's "A after.".
//
// Reference (inklecate 1.2.1): `InkParser_Content.cs` `TrimEndWhitespace` only
// ever trims the END of a line's text; the compiled json keeps the literal
// verbatim ("^ after. ") and the runtime cleans the trailing space at line end.
// ADR-026 §1 limits this fix to trimming the trailing whitespace before `#`.
//
// Every expected line below was probed with `inklecate -p` (1.2.1) before the
// fix was written.
//
// Tags on lines AFTER the tagged one are deliberately NOT asserted here: a
// line's tags currently stick in `currentTags` until the next choice (#30, a
// runtime bug fixed separately in step 02-02).

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct Compiler_TagTrimTests {

    private static let fixture = "issue34-space-before-tag"

    // Scenario: #34 space before a tag after an inline conditional is kept.
    @Test func `#34 space before a tag after an inline conditional is kept`() throws {
        let story = Story(blueprint: try InkCompiler.compile(source: try CompilerOracle.source(Self.fixture)))

        #expect(story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines) == "A after.")
        #expect(story.currentTags == ["t"])
        #expect(story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines) == "Next.")
        while story.canContinue { _ = story.`continue`() }
        #expect(story.currentChoices.map(\.text) == ["Onward"])
        try story.chooseChoice(at: 0)
        #expect(story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines) == "After the choice.")
    }

    // Scenario: the natively compiled fixture plays exactly like inklecate's json
    // on the same runtime, through the choice and the content after it.
    @Test func `#34 fixture compiled natively plays like the inklecate oracle`() throws {
        let (native, oracle) = try CompilerOracle.compileAndPlay(Self.fixture)

        #expect(oracle == ["A after.", "Next.", "After the choice."])
        #expect(native == oracle)
    }

    // Scenario: each probed tag position prints what `inklecate -p` prints.
    //
    // Also probed, NOT pinned: glue before a tag, `Text <> # t` + `glued.`.
    // inklecate joins it into "Text glued."; the native compiler prints the glue
    // literally ("Text <>" / "glued.") with or without this fix. Recorded in
    // docs/reference/differences-from-inklecate.md, outside ADR-026 §4's scope.
    @Test(arguments: [
        ("VAR n = 1\n{n > 0: A} after. # t\nNext.\n-> END\n", ["A after.", "Next."]),
        ("VAR x = 5\n{x} text # t\nNext.\n-> END\n", ["5 text", "Next."]),
        ("Text   # t\nNext.\n-> END\n", ["Text", "Next."]),
        ("Before.\n# t\nNext.\n-> END\n", ["Before.", "Next."]),
    ])
    func `text before a tag prints like inklecate at every probed position`(source: String, expected: [String]) throws {
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        #expect(try CompilerOracle.play(story) == expected)
    }
}
