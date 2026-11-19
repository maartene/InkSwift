// @acceptance @real-io
//
// #37 / ADR-024 §2 — floats print as inklecate prints them.
//
// ink floats are 32-bit and print with C# `float.ToString(InvariantCulture)`
// (Value.cs FloatValue; maintainer joethephish on inkle/ink#842: "just the
// default C# behaviour"). InkSwift keeps `Double` for storage and arithmetic
// and prints the shortest round-trip digits of the 32-bit value in .NET's
// spelling: no trailing `.0`, scientific form `1E+20` / `1E-05` outside
// .NET's fixed-notation range, `Infinity` / `-Infinity` / `NaN`.
//
// Every expected line below was probed with `inklecate -p` (1.2.1) before the
// change. Both paths are asserted: the native compiler, and inklecate's json
// on the runtime, whose whole-number floats (`2.0`, `1.0`) decode as floats
// since step 01-03 (ADR-023).

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct Engine_FloatFormattingTests {

    private static let fixture = "issue37-float-printing"

    private func nativeStory() throws -> Story {
        Story(blueprint: try InkCompiler.compile(source: try CompilerOracle.source(Self.fixture)))
    }

    // Scenario: Floats print as inklecate prints them — in output and from a
    // variable — then the flow continues through the choice and past it.
    //
    // The choice's text is not asserted on this path: the native compiler
    // keeps `{sum}` in choice text literally (a separate compiler gap); the
    // runtime-path test below pins float formatting in choice text.
    @Test func `floats print as inklecate prints them`() throws {
        let story = try nativeStory()

        let lines = try CompilerOracle.play(story)
        #expect(Array(lines.prefix(3)) == [
            "A: 2 B: 0.33333334 C: 1.5 D: 0.3 E: 3.5",
            "Two thirds: 0.6666667 and the sum: 0.3",
            "The floats are printed.",
        ])
        #expect(lines.last == "You took the coins.")
    }

    // Scenario: whole-number floats in inklecate JSON stay floats. inklecate
    // writes `1.0 / 3` as `"ev",1.0,3,"/"`; decoded as an int, `1.0` made it
    // integer division (`0`) and `7 / 2.0` printed `3`. Played from inklecate's
    // json, the story prints what the native path and `inklecate -p` print,
    // and continues past the floats to the choice and beyond it.
    @Test func `whole-number floats in inklecate JSON stay floats`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON(Self.fixture))

        #expect(try CompilerOracle.play(story) == [
            "A: 2 B: 0.33333334 C: 1.5 D: 0.3 E: 3.5",
            "Two thirds: 0.6666667 and the sum: 0.3",
            "The floats are printed.",
            "Take 0.3 coins",
            "You took the coins.",
        ])
    }

    // Scenario: a choice whose text interpolates a float shows it as inklecate
    // does. Choice text is built by string accumulation (`str`…`/str`), so this
    // also pins the formatter on that path. Runs on inklecate's json: `sum`
    // (0.1 + 0.2) is unaffected by the whole-number decode bug fixed in 01-03.
    @Test func `a choice that interpolates a float shows it as inklecate does`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON(Self.fixture))
        while story.canContinue { _ = story.`continue`() }

        #expect(story.currentChoices.map(\.text) == ["Take 0.3 coins"])
        try story.chooseChoice(at: 0)
        #expect(try CompilerOracle.play(story) == ["Take 0.3 coins", "You took the coins."])
    }

    // Scenario: values outside .NET's fixed-notation range, overflow beyond
    // Float's range, NaN and negative zero are spelled the way inklecate spells them.
    @Test(arguments: [
        ("{100000.0 * 1000000000.0 * 1000000.0}", "1E+20"),
        ("{1.0 / 10000000}", "1E-07"),
        ("{1000000000.0 * 1000000000.0 * 1000000000.0 * 1000000000.0 * 1000.0}", "Infinity"),
        ("{-1000000000.0 * 1000000000.0 * 1000000000.0 * 1000000000.0 * 1000.0}", "-Infinity"),
        ("{1000000000.0}", "1E+09"),
        ("{123456789.0 * 10}", "1.234568E+09"),
        ("{12345.0 * 1000000.0}", "1.2345E+10"),
        ("{10000000.0 * 10}", "100000000"),
        ("{123456789.0}", "123456790"),
        ("{0.0001}", "0.0001"),
        ("{0.00001}", "1E-05"),
        ("{0.000015}", "1.5E-05"),
        ("{-0.00001}", "-1E-05"),
        ("{0.0 * -1.0}", "-0"),
        ("{-2.0}", "-2"),
    ])
    func `float spelling matches inklecate at the edges of its range`(expression: String, expected: String) throws {
        let source = "Value: \(expression)\nAfter.\n-> END\n"
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        #expect(try CompilerOracle.play(story) == ["Value: \(expected)", "After."])
    }

    // Infinity minus infinity. The value overflows Double here (1e324), and
    // already overflows Float in inklecate's 32-bit arithmetic.
    @Test func `NaN prints as NaN like inklecate`() throws {
        let source = """
        VAR big = 0.0
        ~ big = 1000000000.0 * 1000000000.0
        ~ big = big * big * big * big * big * big * big * big * big * big * big * big * big * big * big * big * big * big
        Value: {big - big}
        After.
        -> END
        """
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        #expect(try CompilerOracle.play(story) == ["Value: NaN", "After."])
    }

    // Documented ADR-024 divergence: arithmetic stays 64-bit, so 0.1 + 0.2 is
    // not 0.3 on InkSwift. inklecate computes in 32-bit and prints `true`.
    // Recorded in docs/reference/differences-from-inklecate.md.
    @Test func `0.1 plus 0.2 equals 0.3 is false — the documented ADR-024 precision divergence`() throws {
        let story = Story(blueprint: try InkCompiler.compile(source: "Eq: {0.1 + 0.2 == 0.3}\nAfter.\n-> END\n"))

        #expect(try CompilerOracle.play(story) == ["Eq: false", "After."])
    }

    // Scenario: printing only — the host still reads the 64-bit value.
    @Test func `getVariable still returns the Double value of a float`() throws {
        let story = try nativeStory()
        _ = story.`continue`()

        #expect(story.getVariable("sum") as? Double == 0.1 + 0.2)
    }

    // Scenario: the save wire for a float is unchanged — the full 64-bit value.
    @Test func `a saved float keeps its full Double value on the wire and after restore`() throws {
        let story = try nativeStory()
        _ = story.`continue`()

        let saved = try story.saveState()
        #expect(String(decoding: saved, as: UTF8.self).contains("0.30000000000000004"))

        let restored = try nativeStory()
        try restored.restoreState(saved)
        #expect(restored.getVariable("sum") as? Double == 0.1 + 0.2)
    }
}
