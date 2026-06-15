import Testing
@testable import SwiftInkRuntime

// Step 01-01 — "Parse choice (label) and {condition} guard" (weave-label
// read-count addressing slice, EXTEND #1: parser + AST). Example-based AST-shape
// oracle tests (object-oriented paradigm per CLAUDE.md). They pin all four
// criteria: a leading `(label)` is captured out of choice content; a `{condition}`
// guard is captured as a separate expression; a plain choice is unchanged; and the
// `(label)` reuses `splitBracketedLabel` with `(`/`)` (asserted via behaviour
// symmetry with the gather label).
@Suite("InkParser — choice (label) and {condition} guard")
struct InkParserChoiceLabelConditionTests {

    private func firstChoice(
        _ source: String
    ) throws -> (level: Int, isSticky: Bool, choiceOnlyLabel: String?, body: String, weaveLabel: String?, condition: InkExpression?) {
        let statements = try InkParser.parse(source)
        guard case let .choice(level, isSticky, choiceOnlyLabel, body, weaveLabel, condition) = statements[0].kind else {
            Issue.record("expected a choice, got \(statements[0].kind)")
            throw InkExpressionParseError.unexpectedToken(source)
        }
        return (level, isSticky, choiceOnlyLabel, body, weaveLabel, condition)
    }

    // Criterion 1 — a leading `(label)` is captured and removed from content.
    @Test func `captures a leading (label) out of the choice content`() throws {
        let choice = try firstChoice("* (door) Open the door")
        #expect(choice.weaveLabel == "door")
        #expect(choice.body == "Open the door")
        #expect(choice.choiceOnlyLabel == nil)
        #expect(choice.condition == nil)
    }

    // Criterion 1 — the label is not left in the body, and the choice-only bracket
    // still parses after the leading `(label)`.
    @Test func `captures a (label) before a choice-only bracket span`() throws {
        let choice = try firstChoice("* (greet) [Wave] You wave hello")
        #expect(choice.weaveLabel == "greet")
        #expect(choice.choiceOnlyLabel == "Wave")
        #expect(choice.body == "You wave hello")
        #expect(choice.condition == nil)
    }

    // Criterion 2 — a `{condition}` guard is captured separately from content.
    @Test func `captures a {condition} guard as a separate expression`() throws {
        let choice = try firstChoice("* {visited} Go back")
        #expect(choice.condition == .variableReference("visited"))
        #expect(choice.body == "Go back")
        #expect(choice.weaveLabel == nil)
    }

    // Criterion 2 — a richer guard expression is parsed by the Pratt sub-parser.
    @Test func `captures a comparison {condition} guard expression`() throws {
        let choice = try firstChoice("* {gold > 5} Buy the sword")
        #expect(choice.condition == .binary(op: ">", left: .variableReference("gold"), right: .intLiteral(5)))
        #expect(choice.body == "Buy the sword")
    }

    // Criteria 1 + 2 together — `(label)` then `{condition}` then content.
    @Test func `captures both a (label) and a {condition} guard on one choice`() throws {
        let choice = try firstChoice("* (retry) {attempts < 3} Try again")
        #expect(choice.weaveLabel == "retry")
        #expect(choice.condition == .binary(op: "<", left: .variableReference("attempts"), right: .intLiteral(3)))
        #expect(choice.body == "Try again")
    }

    // Criterion 3 — a plain choice with neither (label) nor {condition} is
    // unchanged: no label, no condition, content intact (regression guard).
    @Test func `parses a plain choice unchanged with no label and no condition`() throws {
        let choice = try firstChoice("* Just a plain choice")
        #expect(choice.weaveLabel == nil)
        #expect(choice.condition == nil)
        #expect(choice.body == "Just a plain choice")
        #expect(choice.choiceOnlyLabel == nil)
        #expect(choice.isSticky == false)
        #expect(choice.level == 1)
    }

    // Criterion 3 — a sticky `+` choice with a choice-only bracket but no label or
    // condition still parses exactly as before.
    @Test func `parses a sticky choice-only-bracket choice unchanged`() throws {
        let choice = try firstChoice("+ [Look around] You scan the room")
        #expect(choice.isSticky == true)
        #expect(choice.choiceOnlyLabel == "Look around")
        #expect(choice.body == "You scan the room")
        #expect(choice.weaveLabel == nil)
        #expect(choice.condition == nil)
    }

    // Step 03-01 (parser bug #2) — a `prefix[]suffix` empty-bracket choice. The
    // `[]` is the suppress-output bracket with no choice-only text: the menu shows
    // the printed `prefix`, and the taken outcome is `prefix` glued to `suffix`.
    // So the menu label is the prefix and the body is `prefix` + `suffix` (the
    // bracket is consumed, never echoed literally). Modelled within the existing
    // fields: `choiceOnlyLabel` carries the menu text (prefix + bracket span),
    // `body` carries the glued outcome (prefix + suffix).
    @Test func `splits a prefix[]suffix empty-bracket choice into menu text and glued outcome`() throws {
        let choice = try firstChoice("* Hut 14[]. The door was locked.")
        #expect(choice.choiceOnlyLabel == "Hut 14")
        #expect(choice.body == "Hut 14. The door was locked.")
        #expect(choice.weaveLabel == nil)
        #expect(choice.condition == nil)
    }

    // Step 03-01 (parser bug #2) — a non-empty `prefix[choiceOnly]suffix`: the menu
    // shows `prefix + choiceOnly`; the taken outcome is `prefix + suffix`.
    @Test func `splits a prefix[choiceOnly]suffix choice into menu text and glued outcome`() throws {
        let choice = try firstChoice("* I say \"hello[\"]\" and wave.")
        #expect(choice.choiceOnlyLabel == "I say \"hello\"")
        #expect(choice.body == "I say \"hello\" and wave.")
    }

    // Criterion 4 — the choice `(label)` is parsed by the SAME generic
    // `splitBracketedLabel` helper that gathers use: a `(label)` on a choice yields
    // the same captured-label / trimmed-rest shape as the identical `(label)` on a
    // gather. (Behavioural proof of helper reuse — no new parsing helper added.)
    @Test func `choice (label) parses with the same shape as a gather (label)`() throws {
        let choice = try firstChoice("* (here) onward")
        let gatherStatements = try InkParser.parse("- (here) onward")
        guard case let .gather(_, gatherLabel, gatherOutcome) = gatherStatements[0].kind else {
            Issue.record("expected a gather, got \(gatherStatements[0].kind)")
            return
        }
        #expect(choice.weaveLabel == gatherLabel)
        #expect(choice.body == gatherOutcome)
    }
}
