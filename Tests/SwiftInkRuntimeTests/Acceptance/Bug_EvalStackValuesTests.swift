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
//
// #41 — unary natives took their operand as it came and could not fail, and
// division by zero gave 0: `{-b}` on a bool printed `true`, `{not s}` on a
// string printed `false`, `{1.0 / z}` printed `0`. The reference
// (NativeFunctionCall.cs `Call`, ~90-120) first refuses a void operand, then
// lifts every operand to at least an int (`CoerceValuesToSingleType`, ~231),
// so a bool negates as 1, and refuses a type with no registered form
// ("Cannot perform operation '<op>' on String"). Float `/` and `%` follow
// IEEE. Fixtures: bug-operator-values.ink (bool operands and float division by
// zero, continuing past them with prose and a choice; INT of an infinite or
// NaN quotient saturates to C#'s 32-bit int, as .NET's conversion does) and
// bug-operator-errors.ink (a choice per refused operation, each in a knot
// whose following prose must not play), messages from `inklecate -p`.
// Integer division by zero crashes inklecate (inkle/ink#843); InkSwift reports
// "Attempted to divide by zero." instead, a maintainer decision.

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

    // Before 2.2.2 a function's void result was the string "void", and a
    // variable holding it was saved as one. Such a save now restores the
    // string itself, which prints: the old sentinel can't be told apart from
    // a story string "void" (see docs/reference/differences-from-inklecate.md).
    @Test func `a legacy save holding the string void restores it as text that prints`() throws {
        let played = try Self.stories(Self.voidFunctionFixture)
        let fresh = try Self.stories(Self.voidFunctionFixture)
        for (story, restored) in zip(played, fresh) {
            while story.canContinue { _ = story.`continue`() }
            let save = String(decoding: try story.saveState(), as: UTF8.self)
            let legacySave = save.replacingOccurrences(
                of: #"{"type":"void"}"#, with: #"{"type":"string","stringValue":"void"}"#)
            #expect(legacySave != save)

            try restored.restoreState(Data(legacySave.utf8))
            try restored.chooseChoice(at: 0)

            #expect(try CompilerOracle.play(restored) == ["Go", "Gone void.", "I 5void J"])
        }
    }

    @Test func `the native compile plays void values as inklecate's JSON does`() throws {
        for fixture in [Self.voidStringFixture, Self.voidFunctionFixture] {
            let result = try CompilerOracle.compileAndPlay(fixture)

            #expect(result.native == result.oracle)
        }
    }

    // MARK: - #41: operators with one operand and division by zero

    private static let operatorValuesFixture = "bug-operator-values"
    private static let operatorErrorsFixture = "bug-operator-errors"

    private static let operatorValuesPlaythrough = [
        "H: -1 1 false 1 1",
        "I: 1",
        "C: Infinity -Infinity NaN NaN",
        "J: 2147483647 -2147483648 0",
        "After.",
        "Go",
        "Gone."
    ]

    @Test func `operators coerce a bool operand to an int and float division by zero follows IEEE`() throws {
        for story in try Self.stories(Self.operatorValuesFixture) {
            let lines = try CompilerOracle.play(story)

            #expect(lines == Self.operatorValuesPlaythrough)
            #expect(story.currentErrors.isEmpty)
        }
    }

    @Test func `the native compile plays operator values as inklecate's JSON does`() throws {
        let result = try CompilerOracle.compileAndPlay(Self.operatorValuesFixture)

        #expect(result.native == result.oracle)
    }

    private static let voidOperandHint = "on a void value. Did you forget to 'return' a value from a function you called here?"

    // The choice index picks the knot that applies one refused operation.
    // Messages are `inklecate -p`'s, except integer division by zero, where
    // inklecate crashes (inkle/ink#843) and InkSwift reports C#'s exception text.
    @Test(arguments: [
        (0, "Cannot perform operation '!' on String"),
        (1, "Cannot perform operation '_' on String"),
        (2, "Cannot perform operation 'FLOOR' on String"),
        (3, "Cannot perform operation 'CEILING' on String"),
        (4, "Cannot perform operation 'INT' on String"),
        (5, "Cannot perform operation 'FLOAT' on String"),
        (6, "Attempted to divide by zero."),
        (7, "Attempted to divide by zero."),
        (8, "Attempting to perform + \(voidOperandHint)"),
        (9, "Attempting to perform _ \(voidOperandHint)"),
    ])
    func `a refused operation reports the reference error and the prose after it does not play`(
        choice: Int, message: String
    ) throws {
        for story in try Self.stories(Self.operatorErrorsFixture) {
            #expect(Self.playUntilStopped(story) == ["Before."])

            try story.chooseChoice(at: choice)

            #expect(Self.playUntilStopped(story) == [])
            #expect(story.currentErrors == [message])
            #expect(story.currentChoices.isEmpty)
        }
    }

    private static func playUntilStopped(_ story: Story) -> [String] {
        var lines: [String] = []
        while story.canContinue {
            let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty == false { lines.append(line) }
        }
        return lines
    }

    // No ink source leaves the evaluation stack short — every instruction
    // inklecate emits that pops has its value pushed first — so these stories
    // are hand-written JSON, kept to one line each: a unary operator, a binary
    // operator with one operand, a temp assignment with nothing to assign, a
    // tunnel return (`->->` pops before it returns, so the empty return stack
    // is never reached), a `pop`, a SEED_RANDOM with no seed, an `out` with
    // nothing to print, a conditional divert and a conditional choice with no
    // condition. Malformed JSON must report an error, not crash the host.
    @Test(arguments: [
        #""_""#, #"1,"+""#, #"{"temp=":"x"}"#, #""->->""#, #""pop""#, #""srnd""#, #""out""#,
        #"{"->":"0","c":true}"#, #"{"*":"0","flg":1}"#,
    ])
    func `an operation on a short evaluation stack reports an error and the prose after it does not play`(
        evaluation: String
    ) throws {
        let json = #"{"inkVersion":21,"root":[["^Before.","\n","ev",\#(evaluation),"/ev","^After.","\n","done",null],"done",null],"listDefs":{}}"#
        let story = try Story(json: json)

        let lines = Self.playUntilStopped(story)

        #expect(lines.contains("After.") == false)
        #expect(story.currentErrors == ["Evaluation stack is empty"])
        #expect(story.currentChoices.isEmpty)
    }
}
