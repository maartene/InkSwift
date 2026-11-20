// @real-io
// Bug-fix regression tests for values the evaluation stack must hold.
//
// #46 — reading a variable that does not exist (a temp whose declaration was
// skipped by a false conditional) pushed nothing, so `Value: {y}.` printed
// `Value: .` and `{y + 2}` lost an operand. The C# reference (Story.cs,
// VariableReference) warns and pushes IntValue(0); inklecate prints `Value: 0.`
// `Sum: 2.` and `Difference: -2.`. `{y + 2}` alone cannot show the missing
// operand: with one value the `+` was skipped and the lone 2 still printed;
// `{y - 2}` printed `2` instead of `-2`. `{(y + 1) / 2}` pins that the 0 is
// an integer: integer division gives `0`, where a float 0 would give `0.5`.
//
// Driving ports: InkCompiler.compile(source:) → Story(blueprint:) (native) and
// Story(json:) on inklecate's committed JSON (runtime), played the same way.
// Fixture: bug-missing-temp-reads-zero.ink(.json) — continues past the read
// with prose, a choice and the choice's content.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Bug — evaluation stack values")
struct Bug_EvalStackValuesTests {

    private static let missingTempFixture = "bug-missing-temp-reads-zero"

    private static let missingTempPlaythrough = [
        "Value: 0.",
        "Sum: 2.",
        "Difference: -2.",
        "Half: 0.",
        "After.",
        "Go",
        "Gone."
    ]

    private static func stories(_ name: String) throws -> [Story] {
        let native = Story(blueprint: try InkCompiler.compile(source: try CompilerOracle.source(name)))
        let runtime = try Story(json: try CompilerOracle.oracleJSON(name))
        return [native, runtime]
    }

    @Test func `a temp whose declaration was skipped reads as 0 and play continues past it`() throws {
        for story in try Self.stories(Self.missingTempFixture) {
            let lines = try CompilerOracle.play(story)

            #expect(lines == Self.missingTempPlaythrough)
        }
    }

    @Test func `a story that read a missing temp offers the choice that follows it`() throws {
        for story in try Self.stories(Self.missingTempFixture) {
            while story.canContinue { _ = story.`continue`() }

            #expect(story.currentChoices.map(\.text) == ["Go"])
        }
    }

    @Test func `the native compile plays the missing temp as inklecate's JSON does`() throws {
        let result = try CompilerOracle.compileAndPlay(Self.missingTempFixture)

        #expect(result.native == result.oracle)
    }
}
