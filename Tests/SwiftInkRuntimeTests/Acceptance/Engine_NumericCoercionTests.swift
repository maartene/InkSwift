// @acceptance @real-io
//
// #37 part 2 / ADR-024 — mixed-type operators and casts follow the C# reference.
//
// Every binary native coerces both operands to the higher of their types first
// (C# NativeFunctionCall.CoerceValuesToSingleType, NativeFunctionCall.cs
// ~231-250; order bool < int < float < string, Value.cs ValueType), so
// `1 == 1.0` compares two floats and `"a" + 1` concatenates. An operator with
// no string form applied to a coerced string raises the reference's runtime
// error, "Cannot perform operation '<op>' on String" (NativeFunctionCall.cs
// Call<T>), reported bare (ADR-017) and ending the flow. FLOOR and CEILING of a
// float return a float (NativeFunctionCall.cs AddFloatUnaryOp(Floor, …)).
//
// Every expected line was probed with `inklecate -p` (1.2.1, invariant locale)
// before the change; the predictions all held.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct Engine_NumericCoercionTests {

    private static let fixture = "numeric-coercion-and-casts"
    private static let errorFixture = "string-operand-error"

    private static let oracleLines = [
        "Eq: true",
        "Neq: false",
        "Min: 1",
        "Max: 2.5",
        "StrInt: a1",
        "StrFloat: a1.5",
        "BoolInt: 2",
        "Floor: 1",
        "Ceiling: 0.6666667",
        "Int: 1",
        "Float: 0.5",
        "FloatTwo: 2",
        "FloorInt: 3",
        "The values are printed.",
        "Carry on",
        "You carried on.",
    ]

    /// Continue until the story cannot, without choosing: trimmed non-empty lines.
    private func playUntilStopped(_ story: Story) -> [String] {
        var lines: [String] = []
        var steps = 0
        while story.canContinue && steps < 100 {
            let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty == false { lines.append(line) }
            steps += 1
        }
        return lines
    }

    // Scenario: played from inklecate's json, every operator and cast line
    // prints what `inklecate -p` prints, and the flow continues past them
    // through the choice.
    @Test func `mixed-type operators and casts follow the C# reference`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON(Self.fixture))

        #expect(try CompilerOracle.play(story) == Self.oracleLines)
    }

    // Scenario: compiled natively, every line matches the oracle: the operator
    // lines (`==`, `!=`, `+` with strings and bools) and the built-in calls
    // (FLOOR, CEILING, INT, FLOAT, MIN, MAX), which compile natively since
    // step 04-02.
    @Test func `natively compiled operator and cast lines match the oracle`() throws {
        let story = Story(blueprint: try InkCompiler.compile(source: try CompilerOracle.source(Self.fixture)))

        #expect(try CompilerOracle.play(story) == Self.oracleLines)
    }

    // Scenario: `"a" - 1` coerces 1 to "1", and `-` has no string form: the
    // reference's error is reported, the prose before it played, nothing after
    // it plays, no choice is offered, and the forced end is a safe exit, so no
    // "ran out of content" error follows.
    @Test func `a non-string operator on a string reports the reference error and ends the flow`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON(Self.errorFixture))

        let lines = playUntilStopped(story)

        #expect(lines == ["Before the error."])
        #expect(story.currentErrors == ["Cannot perform operation '-' on String"])
        #expect(story.canContinue == false)
        #expect(story.currentChoices.isEmpty)
    }

    // Scenario: every operator without a string form raises the same error,
    // named after the operator, on whichever side the string sits. Messages
    // probed with `inklecate -p`.
    @Test(arguments: [
        ("\"a\" - 1", "-"),
        ("\"a\" < 1", "<"),
        ("\"a\" * 2", "*"),
        ("\"a\" >= 1", ">="),
        ("1 / \"a\"", "/"),
        ("\"a\" % 2", "%"),
        ("\"a\" && true", "&&"),
    ])
    func `every operator without a string form reports the reference error`(expression: String, op: String) throws {
        let source = "Before.\n{\(expression)}\nAfter.\n-> END\n"
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        #expect(playUntilStopped(story) == ["Before."])
        #expect(story.currentErrors == ["Cannot perform operation '\(op)' on String"])
    }

    // Scenario: operators that do have a string form coerce the other operand
    // to a string (probed with `inklecate -p`).
    @Test(arguments: [
        ("\"1\" == 1", "true"),
        ("1.5 + \"b\"", "1.5b"),
        ("true == 1", "true"),
    ])
    func `operators with a string form coerce the other operand`(expression: String, expected: String) throws {
        let source = "Value: {\(expression)}\nAfter.\n-> END\n"
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        #expect(try CompilerOracle.play(story) == ["Value: \(expected)", "After."])
        #expect(story.currentErrors.isEmpty)
    }
}
