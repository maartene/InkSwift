// @acceptance @real-io
//
// Issue #35, step 05-02 — backslash escapes read as inklecate reads them
// (ADR-026 §5): `\x` is the literal `x` and never acts as a stop, in prose,
// choice text, alternatives, tags and string literals
// (`ContentTextAllowingEcapeChar`, InkParser_Content.cs:117-199).
//
// Also pins glue before a tag (`Text <> # t` / `glued.`), which the native
// compiler used to read as plain text ending in `<>`.
//
// Expected texts recorded from inklecate 1.2.1 (`-p`, invariant culture) on
// 2026-11-20. Every fixture continues past the construct it pins with prose
// and a choice. On glue-before-tag, `inklecate -p` also joins the line after
// `glued.` ("Text glued.After the glue."); the InkSwift runtime on inklecate's
// JSON does not, and the native path is held to the runtime path.
//
// Driving ports: InkCompiler.compile(source:) and Story(json:).

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — backslash escapes print literally (#35)")
struct Compiler_EscapeTests {

    /// One observable step of a playthrough: a line with its tags, or the
    /// choices offered.
    enum Step: Equatable {
        case line(String, tags: [String])
        case choices([String])
    }

    /// Play `story`, always taking `choiceScript` (first choice when empty),
    /// recording every non-empty line with its tags and every choice point.
    static func steps(_ story: Story, choiceScript: [Int] = [], stepCeiling: Int = 500) throws -> [Step] {
        var steps: [Step] = []
        var cursor = 0
        for _ in 0..<stepCeiling {
            if story.canContinue {
                let line = story.continue().trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty || !story.currentTags.isEmpty {
                    steps.append(.line(line, tags: story.currentTags))
                }
            } else if !story.currentChoices.isEmpty {
                steps.append(.choices(story.currentChoices.map(\.text)))
                let pick = choiceScript.isEmpty ? 0 : choiceScript[cursor % choiceScript.count]
                try story.chooseChoice(at: pick % story.currentChoices.count)
                cursor += 1
            } else {
                break
            }
        }
        return steps
    }

    static func native(_ fixture: String, choiceScript: [Int] = []) throws -> [Step] {
        try steps(Story(blueprint: try InkCompiler.compile(source: try CompilerOracle.source(fixture))),
                  choiceScript: choiceScript)
    }

    static func runtime(_ fixture: String, choiceScript: [Int] = []) throws -> [Step] {
        try steps(Story(json: try CompilerOracle.oracleJSON(fixture)), choiceScript: choiceScript)
    }

    // MARK: - #35

    static let issue35 = "issue35-escapes"

    static let issue35Expected: [Step] = [
        .line("Prose {a} and # hash.", tags: []),
        .line("Tagged.", tags: ["a{b}"]),
        .line("String: c{d}.", tags: []),
        .line("After the escapes.", tags: []),
        .choices(["Keep going"]),
        .line("Keep going", tags: []),
        .line("The choice played.", tags: []),
    ]

    @Test func `#35 backslash escapes print literally in prose, tags and strings`() throws {
        let native = try Self.native(Self.issue35)
        let runtime = try Self.runtime(Self.issue35)

        #expect(native == Self.issue35Expected)
        #expect(runtime == Self.issue35Expected)
    }

    // MARK: - Choices, alternatives and a literal backslash

    static let choicesAndAlternatives = "escapes-in-choices-and-alternatives"

    static let choicesAndAlternativesExpected: [Step] = [
        .line("a|b and !x and a come first.", tags: []),
        .line("A literal backslash \\ and a pipe | stay.", tags: []),
        .choices(["Pick [x] now", "Bar a|b choice"]),
        .line("Pick [x] now", tags: []),
        .line("Picked the bracket.", tags: []),
        .line("c and y and |b come first.", tags: []),
        .line("A literal backslash \\ and a pipe | stay.", tags: []),
        .choices(["Bar a|b choice"]),
        .line("Bar a|b choice", tags: []),
        .line("Picked the bar.", tags: []),
        .line("After the choice.", tags: []),
        .line("The end.", tags: []),
        .choices(["Final choice"]),
        .line("Final choice", tags: []),
        .line("Done.", tags: []),
    ]

    @Test func `escapes in choice text and alternatives and a literal backslash play as inklecate`() throws {
        let native = try Self.native(Self.choicesAndAlternatives)
        let runtime = try Self.runtime(Self.choicesAndAlternatives)

        #expect(native == Self.choicesAndAlternativesExpected)
        #expect(runtime == Self.choicesAndAlternativesExpected)
    }

    // MARK: - modeAndContent: an escaped first character is no mode marker

    // Probed with inklecate 1.2.1: inklecate escapes any `\x` in any stage, and
    // an escaped `!`/`&` is the literal first character of a plain sequence.
    @Test(arguments: [
        ("{\\!a|b} {\\&c|d} {a|b\\!}", ["!a &c a", "b d b!"]),
        ("{!a\\|b|c} {&x\\&|y}", ["a|b x&", "c y"]),
        ("{ \\!a|b}", ["!a", "b"]),
    ])
    func `an escaped first character is literal stage text, not a mode marker`(body: String, rounds: [String]) throws {
        let source = "- (top)\n\(body)\n* [Again] -> top\n* [Stop]\n    Stopped.\n    -> END\n"
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        var lines: [String] = []
        for _ in rounds {
            lines += try CompilerOracle.play(story, maxLines: 1)
            try story.chooseChoice(at: 0)
        }
        #expect(lines == rounds)
    }

    // inklecate: "Expected some kind of logic, conditional or sequence within
    // braces: { ... } but saw '\x} B'". A leading escape does not make a
    // brace body a sequence.
    @Test(arguments: ["A {\\x} B\nAfter.\n", "A {\\!a} B\nAfter.\n"])
    func `a brace body with an escape and no bar is no sequence`(source: String) {
        #expect(throws: (any Error).self) { try InkCompiler.compile(source: source) }
    }

    // MARK: - Glue before a tag

    static let glueBeforeTag = "glue-before-tag"

    @Test func `glue before a tag joins the line to the next one, as inklecate`() throws {
        let native = try Self.native(Self.glueBeforeTag)
        let runtime = try Self.runtime(Self.glueBeforeTag)

        #expect(native.first == .line("Text glued.", tags: ["t"]))
        #expect(native == runtime)
    }
}
