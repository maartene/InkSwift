// Unit-level classification pins for `InkParser.scanBraceSegment`'s dispatch
// order. The played-output equivalence lives in the VT4 acceptance suite; these
// assert the AST classification directly, so a regression points at the parser
// rather than at a diverging playthrough.

import Testing
@testable import SwiftInkRuntime

@Suite("InkParser — leading brace marker precedence")
struct InkParserBraceMarkerTests {

    /// Parse a single content line and return its segments.
    private func segments(of line: String) throws -> [ContentSegment] {
        let statements = try InkParser.parse(line + "\n")
        for statement in statements {
            if case .content(let segments) = statement.kind { return segments }
        }
        Issue.record("no content statement parsed from \(line)")
        return []
    }

    // M1 — a `!` marker followed by a top-level `:` is a once-only alternative
    // over the whole body, NOT an inline conditional on `!a`. This is the
    // silently-wrong case: it previously parsed as `.conditional` and emitted the
    // true-branch text.
    @Test func `a once marker beats a top-level colon`() throws {
        #expect(try segments(of: "{!a: x}") == [.variableText(mode: .once, stages: ["a: x"])])
    }

    // M2 — leading whitespace is skipped before reading the marker, so the spaced
    // spelling classifies identically (inklecate plays `{ !a: q }` as `a: q`).
    @Test func `whitespace before the marker is skipped`() throws {
        #expect(try segments(of: "{ !a: q }") == [.variableText(mode: .once, stages: ["a: q "])])
    }

    // M3 — a marker with neither `:` nor `|` is still an alternative, not an
    // expression: `{!a}` prints the literal stage "a", not the boolean `!a`.
    @Test func `a bare marker body is an alternative, not an expression`() throws {
        #expect(try segments(of: "{!a}") == [.variableText(mode: .once, stages: ["a"])])
    }

    // M4 — the `&` cycle marker takes the same precedence. Before the fix this
    // reached the expression parser and threw `unexpectedToken("&")`.
    @Test func `a cycle marker beats a top-level colon`() throws {
        #expect(try segments(of: "{&a: y}") == [.variableText(mode: .cycle, stages: ["a: y"])])
    }

    // M5 — a leading `\` escapes the marker: the body is a plain sequence whose
    // first stage begins with the literal `!`. Must also be claimed ahead of the
    // `:` test, or the escaped body would fall through to the conditional path.
    @Test func `an escaped marker yields a plain sequence with the marker literal`() throws {
        #expect(try segments(of: "{\\!a: NotEscaped|Other}")
            == [.variableText(mode: .sequence, stages: ["!a: NotEscaped", "Other"])])
    }

    // M6 — an UNMARKED body with a top-level `:` is still an inline conditional.
    // Guards against the hoisted marker test swallowing ordinary conditionals.
    @Test func `an unmarked body with a colon is still an inline conditional`() throws {
        let parsed = try segments(of: "{a: yes|no}")
        guard case .conditional(_, let ifTrue, let ifFalse) = parsed.first else {
            Issue.record("expected an inline conditional, got \(parsed)")
            return
        }
        // The branch text keeps the space after `:` verbatim — existing
        // behaviour, pinned here so the hoisted marker test cannot change it.
        #expect(ifTrue == " yes")
        #expect(ifFalse == "no")
    }

    // M7 — a parenthesised logical-not is an expression, not a marker: the `!`
    // is not in leading position. Pins that this fix does not undo PR #12's
    // symbol-form `!` support.
    @Test func `a parenthesised logical-not is still an expression`() throws {
        let parsed = try segments(of: "{(!a): yes|no}")
        guard case .conditional(let condition, _, _) = parsed.first else {
            Issue.record("expected an inline conditional, got \(parsed)")
            return
        }
        #expect(condition == .unary(op: "!", operand: .variableReference("a")))
    }

    // M8 — shuffle stays rejected. The `~` marker is deliberately NOT claimed by
    // the hoisted test; `UnsupportedConstructDetector` must still reject it, so a
    // future change to the marker set cannot silently downgrade shuffle to a
    // plain sequence.
    @Test func `a shuffle marker is still rejected as unsupported`() throws {
        #expect(throws: CompileError.self) {
            _ = try InkParser.parse("{~a: x}\n")
        }
    }
}
