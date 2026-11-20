// @acceptance @real-io
//
// Issue #36, step 04-04 — POW and the string contains operators play as
// inklecate plays them (ADR-025 §5), compiled natively and from inklecate's JSON.
//
// - POW of two ints is a float (C# `AddIntBinaryOp(Pow, (x, y) => (float)Math.Pow(x, y))`).
// - `?` / `has` and `!?` / `hasnt` are `String.Contains` and its negation for
//   strings (NativeFunctionCall.cs `AddStringBinaryOp(Has, …)`); the word forms
//   lower to the same natives (ParsedHierarchy/Expression.cs `NativeNameForOp`).
// - They bind at precedence 3 (InkParser_Expressions.cs): tighter than
//   comparison, looser than addition, left to right.
// - The reference defines them for strings and lists only. Two ints or floats
//   raise "Cannot perform operation '?' on Int" at runtime; a string on either
//   side casts the other operand to a string.
//
// Expected texts recorded from inklecate 1.2.1 (`-p`, invariant culture) on
// 2026-11-20. The fixture continues past the operators with prose and a choice.
//
// Driving ports: InkCompiler.compile(source:) and Story(json:).

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — POW and string contains play as inklecate (#36)")
struct Compiler_PowAndContainsTests {

    static let fixture = "pow-and-contains"

    static let expected = [
        "POW: 8 and 1.4142135.",
        "Contains: no yes yes.",
        "Words: yes no.",
        "Precedence: true true true.",
        "Coerced: true.",
        "After the operators.",
        "Keep going",
        "The choice played.",
    ]

    @Test func `POW and string contains from inklecate's JSON play as inklecate`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON(Self.fixture))

        #expect(try CompilerOracle.play(story) == Self.expected)
    }

    @Test func `POW and string contains compile natively and play as inklecate`() throws {
        let result = try CompilerOracle.compileAndPlay(Self.fixture)

        #expect(result.native == Self.expected)
        #expect(result.native == result.oracle)
    }

    // Each case tells the two candidate bindings apart; inklecate's output is
    // the left-hand reading.
    @Test(arguments: [
        ("\"ab\" + \"c\" ? \"bc\"", "true"),   // ("ab" + "c") ? "bc"; tighter would print "abfalse"
        ("\"ab\" ? \"b\" == true", "true"),     // ("ab" ? "b") == true; looser would be "ab" ? false
        ("\"true\" == \"x\" ? \"x\"", "true"),  // "true" == ("x" ? "x"); at == level, false ? "x" is false
        ("\"a\" ? \"a\" ? \"true\"", "true"),   // left to right; right-first would be "a" ? "false"
        ("\"abc\" ? \"c\" + \"x\"", "false"),   // "abc" ? ("c" + "x")
        ("\"ab\" ? \"b\" && \"x\" ? \"y\"", "false"),
    ])
    func `contains binds between comparison and addition, left to right`(expression: String, printed: String) throws {
        let story = Story(blueprint: try InkCompiler.compile(source: "{\(expression)}\nAfter.\n-> END\n"))

        #expect(try CompilerOracle.play(story) == [printed, "After."])
    }

    // C# `String.Contains` is ordinal (UTF-16 code units): case-sensitive, the
    // empty string is in every string, and a decomposed "é" contains "e" while a
    // precomposed one does not match the decomposed spelling. Probed with inklecate.
    @Test(arguments: [
        ("\"abc\" ? \"\"", "true"),
        ("\"\" ? \"\"", "true"),
        ("\"\" ? \"a\"", "false"),
        ("\"Abc\" ? \"a\"", "false"),
        ("\"cafe\u{0301}\" ? \"cafe\"", "true"),
        ("\"caf\u{00E9}\" ? \"cafe\u{0301}\"", "false"),
    ])
    func `contains compares strings ordinally, as the reference does`(expression: String, printed: String) throws {
        let story = Story(blueprint: try InkCompiler.compile(source: "{\(expression)}\nAfter.\n-> END\n"))

        #expect(try CompilerOracle.play(story) == [printed, "After."])
    }

    // Probed with inklecate: the reference has no int or float form of `?`/`!?`.
    @Test(arguments: [
        ("5 ? 5", "Cannot perform operation '?' on Int"),
        ("1.5 !? 1", "Cannot perform operation '!?' on Float"),
        ("2 > 1 ? 1", "Cannot perform operation '?' on Int"),
    ])
    func `contains on numbers reports the reference error`(expression: String, error: String) throws {
        let story = Story(blueprint: try InkCompiler.compile(source: "Before.\n{\(expression)}\nAfter.\n-> END\n"))

        var lines: [String] = []
        while story.canContinue {
            let line = story.continue().trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { lines.append(line) }
        }

        #expect(lines == ["Before."])
        #expect(story.currentErrors == [error])
    }

    @Test func `POW of two ints is a float and POW of floats follows Math.Pow`() throws {
        let story = Story(blueprint: try InkCompiler.compile(
            source: "{POW(2, -1)} {POW(2.5, 2)} {POW(2, 3) / 3}\nAfter.\n-> END\n"))

        #expect(try CompilerOracle.play(story) == ["0.5 6.25 2.6666667", "After."])
    }
}
