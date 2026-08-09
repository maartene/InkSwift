// Unit-level pin for `InkParser.outcomeStatement`'s tag handling — the choice
// outcome (a choice line's post-bracket remainder) must reach the tag-aware
// segment parser, not be shortcut to a raw `.text` statement.
//
// The shortcut was gated on the outcome containing `{`, so a tag-only outcome
// stayed literal. See `Compiler_S4_ChoiceContinuationTagTests` for the
// oracle-backed behaviour this produces.

import Testing
@testable import SwiftInkRuntime

@Suite("InkParser — choice outcome tag segments")
struct InkParserOutcomeTagTests {

    private let position = SourcePosition(line: 1, column: 1)

    private func segments(of outcome: String) throws -> [ContentSegment] {
        guard case .content(let segments)? = try InkParser.outcomeStatement(outcome, at: position)?.kind else {
            Issue.record("expected a content statement for outcome '\(outcome)'")
            return []
        }
        return segments
    }

    // T1 — a tag-only outcome is a tag segment, not literal text. This is the
    // regression: it previously yielded `.text("# sidequest")`.
    @Test func `a tag-only outcome parses as a tag segment`() throws {
        #expect(try segments(of: "# sidequest") == [.tag("sidequest")])
    }

    // T2 — prose followed by a tag splits into literal + tag. The exact
    // whitespace kept on the literal is deliberately NOT pinned here: inklecate
    // emits the space before `#` as text (`"^ "`) while this parser folds it into
    // the tag scan. Played output trims line edges, so the two agree on output;
    // pinning the difference here would freeze an unverified detail.
    @Test func `prose followed by a tag splits into literal and tag segments`() throws {
        let parsed = try segments(of: "Body. # sidequest")

        #expect(parsed.count == 2)
        #expect(parsed.last == .tag("sidequest"))
        guard case .literal(let text)? = parsed.first else {
            Issue.record("expected a leading literal, got \(parsed)")
            return
        }
        #expect(text.trimmingCharacters(in: .whitespaces) == "Body.")
    }

    // T3 — an outcome containing a `{…}` already took the segment path before the
    // fix; kept as a guard that routing more outcomes there changed nothing here.
    @Test func `an outcome with an expression and a tag still splits`() throws {
        #expect(try segments(of: "{n} # sidequest")
            == [.expression(.variableReference("n")), .tag("sidequest")])
    }

    // T4 — an outcome with neither `{` nor `#` stays a plain text statement, so
    // the common case keeps its existing node shape.
    @Test func `a plain prose outcome remains a text statement`() throws {
        guard case .text(let text)? = try InkParser.outcomeStatement("Just prose.", at: position)?.kind else {
            Issue.record("expected a text statement")
            return
        }
        #expect(text == "Just prose.")
    }
}
