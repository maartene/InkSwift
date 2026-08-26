// @regression @real-io @kpi-1
//
// A choice written inside a conditional arm must become a real choicePoint at ANY
// weave depth — including an arm nested inside a choice body, where the arm's
// choices are written `* *`.
//
// Ground truth (verified against inklecate 1.2.1 — see the committed
// `compile-choice-in-nested-conditional-arm.ink.json` oracle): taking `First`
// plays its prose, plays the line after the block, and only then presents the
// arm's choice. A choice inside a conditional generates its choicePoint WITHOUT
// halting the flow (inkle/ink#978), so the arm rejoins and the rest of the choice
// body still runs.
//
// Defect this pins (issue #21): `WeaveEmitter.lowerWithLabelPaths` parsed every
// weave at a hardcoded level 1. An arm inside a level-1 choice body holds level-2
// choices, and `parseBlock` matches items only AT its level — a `* *` choice
// matched neither `== 1` nor `< 1`, fell through to `default:` and was swallowed
// as ordinary content. No choicePoint was emitted at all; only the choice body's
// divert survived, inlined into the arm container. The level is now derived from
// the body itself (`WeaveParser.topLevel(of:)`), so a sub-weave is parsed at the
// level it actually starts at.
//
// Correctness gate: hermetic Level-1 execution-equivalence — native compile vs the
// committed inklecate oracle, both played through the pure-Swift `Story`. The
// fixture covers BOTH arm kinds at depth (the implicit true arm and `- else:`) and
// continues past each block, per CLAUDE.md — "a fixture must continue past the
// construct it pins".

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — a choice inside a conditional arm is offered at any weave depth")
struct Compiler_ChoiceInNestedConditionalArmTests {

    private static let fixture = "compile-choice-in-nested-conditional-arm"

    // Scenario: the whole fixture plays line-for-line and choice-for-choice like the
    // oracle, across both arm kinds at depth.
    @Test
    func `a choice in an arm nested in a choice body plays identically to the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay(Self.fixture, choiceScript: [0, 0, 0, 0])

        #expect(result.native == result.oracle)
    }

    // Scenario: the `* *` choice inside the IMPLICIT TRUE arm is offered after the
    // choice body finishes. The defect emitted no choicePoint at all here, so the
    // story ran on with nothing to take.
    @Test
    func `a doubled-star choice in a nested true arm is offered`() throws {
        let source = try CompilerOracle.source(Self.fixture)
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 0)
        while story.canContinue { _ = story.`continue`() }

        #expect(story.currentChoices.map(\.text) == ["From the nested true arm"])
    }

    // Scenario: the same at depth in an `- else:` arm — guards against a fix that
    // only reaches the implicit true arm.
    @Test
    func `a doubled-star choice in a nested else arm is offered`() throws {
        let result = try CompilerOracle.compileAndPlay(Self.fixture, choiceScript: [0, 0, 0, 0])

        #expect(result.native.contains("From the nested else arm"))
        #expect(result.native == result.oracle)
    }

    // Scenario: the line after the block still plays, and plays BEFORE the arm's
    // choice is presented — the arm rejoins rather than halting the flow.
    @Test
    func `content after a nested block plays before the arm choice`() throws {
        let result = try CompilerOracle.compileAndPlay(Self.fixture, choiceScript: [0, 0, 0, 0])

        let afterBlock = try #require(result.native.firstIndex(of: "After the block in first."))
        let armChoice = try #require(result.native.firstIndex(of: "From the nested true arm"))
        #expect(afterBlock < armChoice)
        #expect(result.native.contains("After the block in outer."))
    }
}
