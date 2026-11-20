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
//
// #44 — the runtime used the ordinary string "void" as its no-value sentinel
// and `out` suppressed it, so a story string "void" never printed:
// `VAR v = "void"` / `A {v} B` played `A  B`, where inklecate plays
// `A void B`. C# keeps a distinct `Void` object on the evaluation stack
// (Story.cs: a `void` token is pushed like any value, `out` skips only `Void`,
// `->->` pops it, a function body that runs off its end pushes it).
// Fixtures: bug-void-string-prints.ink (a variable and a literal
// holding "void") and bug-void-function-result.ink (functions
// returning nothing — implicitly and by bare `~ return` — printed mid-line,
// stored in a temp and in a global that survives a save/restore). Both
// continue past the construct with prose, a choice and the choice's content.

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

    // MARK: - #44: a story string "void" is printed

    private static let voidStringFixture = "bug-void-string-prints"
    private static let voidFunctionFixture = "bug-void-function-result"

    private static let voidStringPlaythrough = [
        "A void B",
        "C void D",
        "After.",
        "Go",
        "Gone void."
    ]

    private static let voidFunctionPlaythrough = [
        "A 5 B",
        "C 5 D",
        "E 5 F",
        "G 5 H",
        "After.",
        "Go",
        "Gone .",
        "I 5 J"
    ]

    @Test func `a story string void prints as text and play continues past it`() throws {
        for story in try Self.stories(Self.voidStringFixture) {
            let lines = try CompilerOracle.play(story)

            #expect(lines == Self.voidStringPlaythrough)
        }
    }

    @Test func `a function that returns nothing prints nothing mid-line and play continues past it`() throws {
        for story in try Self.stories(Self.voidFunctionFixture) {
            let lines = try CompilerOracle.play(story)

            #expect(lines == Self.voidFunctionPlaythrough)
            #expect(story.currentErrors.isEmpty)
        }
    }

    @Test func `a variable holding a function's void result survives a save and restore`() throws {
        let played = try Self.stories(Self.voidFunctionFixture)
        let fresh = try Self.stories(Self.voidFunctionFixture)
        for (story, restored) in zip(played, fresh) {
            while story.canContinue { _ = story.`continue`() }

            try restored.restoreState(try story.saveState())
            try restored.chooseChoice(at: 0)

            #expect(try CompilerOracle.play(restored) == ["Go", "Gone .", "I 5 J"])
        }
    }

    @Test func `the native compile plays void values as inklecate's JSON does`() throws {
        for fixture in [Self.voidStringFixture, Self.voidFunctionFixture] {
            let result = try CompilerOracle.compileAndPlay(fixture)

            #expect(result.native == result.oracle)
        }
    }
}
