// @regression @real-io @kpi-1
//
// S4 regression — MULTIPLE choice-level tags inside one choice-only bracket:
// `* [Tagged choice # one # two]`.
//
// Ground truth (inklecate 1.2.1, see the committed oracle): each `#` opens its
// own tag pair inside the choice's text-generation block —
//
//   "ev","str","^Tagged choice ","#","^one ","/#","#","^two","/#","/str","/ev"
//
// Note the FIRST tag's raw text is "one " WITH a trailing space: inklecate emits
// the source text between the markers verbatim, and the reference runtime cleans
// it when the Tag is constructed (`Story.cs` EndTag →
// `state.CleanOutputWhitespace(...)`). So the observable tag list is
// ["one", "two"], trimmed, on both sides.
//
// Two defects pinned here (fixed 2026-08-13):
//   1. Compiler — `WeaveEmitter.splitChoiceLabelTag` split on the FIRST `#` only,
//      so the label yielded the single tag "one # two".
//   2. Engine — `TreeWalker`'s `.tagClose` appended the accumulator raw, so even
//      a correct inklecate json produced ["one ", "two"] rather than the
//      reference's cleaned ["one", "two"].
//
// The choice TEXT keeps its trailing space ("Tagged choice ") — that is verbatim
// inklecate behaviour, established when single-tag support landed.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler S4 — Multiple tags on one bracketed choice")
struct Compiler_S4_ChoiceMultiTagTests {

    private func choices(of story: Story) -> [Choice] {
        while story.canContinue { _ = story.`continue`() }
        return story.currentChoices
    }

    /// The tags reported for the first content line.
    private func firstLineTags(of story: Story) -> [String] {
        _ = story.`continue`()
        return story.currentTags
    }

    // Scenario: tag text is CLEANED the way the reference runtime cleans it —
    // edges trimmed AND each internal whitespace run collapsed to one space.
    //
    // Verified against inklecate 1.2.1 for the fixture's `#  spaced   tag`: the
    // compiler emits the json text "^spaced   tag" (edges trimmed, run kept) and
    // the official player then reports `# tags: spaced tag`. Trimming alone would
    // leave "spaced   tag" and diverge from the reference.
    @Test func `tag text is cleaned like the reference runtime, on both paths`() throws {
        let source = try CompilerOracle.source("compile-choice-multi-tag")
        let native = Story(blueprint: try InkCompiler.compile(source: source))
        let oracle = try Story(json: try CompilerOracle.oracleJSON("compile-choice-multi-tag"))

        #expect(firstLineTags(of: native) == ["spaced tag"])
        #expect(firstLineTags(of: oracle) == ["spaced tag"])
    }

    // Scenario: compiled natively, every tag in the bracket is captured, trimmed.
    @Test func `every tag in a bracketed choice is captured when compiled natively`() throws {
        let source = try CompilerOracle.source("compile-choice-multi-tag")
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        let parsed = choices(of: story)

        #expect(parsed.map(\.text) == ["Tagged choice ", "Plain choice"])
        #expect(parsed.first?.tags == ["one", "two"])
        #expect(parsed.last?.tags == [])
    }

    // Scenario: the same story from the inklecate oracle json. This is the engine
    // half — it produced ["one ", "two"] before the tag text was cleaned.
    @Test func `every tag is captured and cleaned when loaded from the oracle`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON("compile-choice-multi-tag"))

        let parsed = choices(of: story)

        #expect(parsed.map(\.text) == ["Tagged choice ", "Plain choice"])
        #expect(parsed.first?.tags == ["one", "two"])
    }

    // Scenario: the two paths agree — the equivalence the suite exists to protect.
    @Test func `native and oracle agree on the choice tags`() throws {
        let source = try CompilerOracle.source("compile-choice-multi-tag")
        let native = choices(of: Story(blueprint: try InkCompiler.compile(source: source)))
        let oracle = choices(of: try Story(json: try CompilerOracle.oracleJSON("compile-choice-multi-tag")))

        #expect(native.map(\.tags) == oracle.map(\.tags))
        #expect(native.map(\.text) == oracle.map(\.text))
    }

    // Scenario: played output is unchanged by the tags — no tag text leaks into
    // either side's rendered lines, for either choice.
    @Test(arguments: [0, 1])
    func `the played output matches the oracle for either choice`(choice: Int) throws {
        let result = try CompilerOracle.compileAndPlay(
            "compile-choice-multi-tag", choiceScript: [choice]
        )

        #expect(result.native == result.oracle)
        #expect(result.native.contains { $0.contains("#") } == false)
    }
}
