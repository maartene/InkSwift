// @regression @real-io @kpi-1
//
// A choice written INSIDE AN ARM of a block conditional must be offered when
// that arm is taken.
//
// Ground truth (verified against inklecate 1.2.1 — see the committed
// `compile-choice-in-conditional-arm.ink.json` oracle): the arm's choice belongs
// to the enclosing knot's weave, so taking the arm presents the choice exactly
// as if it had been written outside the block.
//
// Defect this pins: the native compiler lowered an arm body as plain content,
// so a choice point inside it never reached the enclosing knot's choice
// container. At runtime the arm's text played, no choice was offered, and the
// flow ran on past the end of the knot into the next one. There was no compile
// error and no load error, so the failure surfaced as a missing choice — easily
// misread as a typo in the choice's id.
//
// Correctness gate: hermetic Level-1 execution-equivalence — native compile vs
// the committed inklecate `.ink.json` oracle, both played through the pure-Swift
// `Story`. The fixture covers every arm kind a choice can sit in: the `- else:`
// arm, the implicit true arm (`{ x == 1:`), and a middle arm of a headerless
// multi-condition block.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — a choice inside a conditional arm is offered")
struct Compiler_ChoiceInConditionalArmTests {

    /// Play out the current block, then take `index` and play out what the choice
    /// leads to, so the caller sees the NEXT menu. Fails with a clear message when
    /// the defect leaves nothing to take.
    private func advance(_ story: Story, takingChoice index: Int) throws {
        while story.canContinue { _ = story.`continue`() }
        try #require(
            story.currentChoices.count > index,
            "No choice to take — the arm's choice was swallowed"
        )
        try story.chooseChoice(at: index)
        while story.canContinue { _ = story.`continue`() }
    }

    // Scenario: the whole fixture plays line-for-line and choice-for-choice like
    // the oracle, across all three arm kinds.
    @Test
    func `a choice inside a conditional arm plays identically to the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay(
            "compile-choice-in-conditional-arm", choiceScript: [0, 0, 0]
        )

        #expect(result.native == result.oracle)
    }

    // Scenario: a choice in the `- else:` arm. The defect played the arm's text
    // and then ran straight on, offering nothing.
    @Test
    func `a choice in the else arm is offered`() throws {
        let source = try CompilerOracle.source("compile-choice-in-conditional-arm")
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        while story.canContinue { _ = story.`continue`() }

        #expect(story.currentChoices.map(\.text) == ["From the else arm"])
    }

    // Scenario: a choice in the IMPLICIT TRUE arm (`{ x == 1:` opens the arm
    // directly), reached by taking the previous knot's choice.
    @Test
    func `a choice in the implicit true arm is offered`() throws {
        let source = try CompilerOracle.source("compile-choice-in-conditional-arm")
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        try advance(story, takingChoice: 0)

        #expect(story.currentChoices.map(\.text) == ["From the true arm"])
    }

    // Scenario: a choice in a MIDDLE arm of a headerless multi-condition block —
    // guards against a fix that only threads the first and last arm.
    @Test
    func `a choice in a middle arm is offered`() throws {
        let source = try CompilerOracle.source("compile-choice-in-conditional-arm")
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        try advance(story, takingChoice: 0)
        try advance(story, takingChoice: 0)

        #expect(story.currentChoices.map(\.text) == ["From the middle arm"])
    }

    // Scenario: the content written AFTER a block whose arm bears a choice still
    // plays, and plays BEFORE the choice is presented — a choice inside a
    // conditional generates its choicePoint without halting the flow
    // (inkle/ink#978), so the arm rejoins and picks up the rest of the knot.
    //
    // This is the assertion the original fixture could not make: every conditional
    // in it ended its knot, leaving the `-end` rejoin empty, so an arm that halted
    // the flow was indistinguishable from one that rejoined. Each knot now
    // continues past its block (CLAUDE.md — "a fixture must continue past the
    // construct it pins").
    @Test
    func `content after a block whose arm bears a choice plays before the choice`() throws {
        let source = try CompilerOracle.source("compile-choice-in-conditional-arm")
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        var lines: [String] = []
        while story.canContinue {
            lines.append(story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines))
        }

        #expect(lines.filter { !$0.isEmpty } == ["Before the else arm.", "Other.", "After the else block."])
        #expect(story.currentChoices.map(\.text) == ["From the else arm"])
    }

    // Scenario: the same rejoin on every arm kind. A fix that threads only the
    // `- else:` arm would leave the implicit-true and middle arms halting, and
    // their trailing lines missing from the playthrough.
    @Test
    func `every arm kind rejoins so all three trailing lines play`() throws {
        let result = try CompilerOracle.compileAndPlay(
            "compile-choice-in-conditional-arm", choiceScript: [0, 0, 0]
        )

        let trailing = ["After the else block.", "After the true block.", "After the middle block."]
        #expect(trailing.allSatisfy(result.native.contains))
        #expect(result.native == result.oracle)
    }
}
