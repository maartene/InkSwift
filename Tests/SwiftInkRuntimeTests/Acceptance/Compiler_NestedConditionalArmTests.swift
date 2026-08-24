// @regression @real-io @kpi-1
//
// A block conditional NESTED INSIDE AN ARM of another block conditional must
// rejoin the OUTER conditional's `-end` continuation, so everything written
// after the outer block still plays.
//
// Ground truth (verified against inklecate 1.2.1 — see the committed
// `compile-nested-conditional-arm.ink.json` oracle): the arms of the inner
// conditional rejoin the inner `-end`, which in turn falls through to the outer
// `-end` — the container holding the statements that followed the outer block.
//
// Defect this pins: `RuntimeObjectEmitter.branchLowerer` lowered an arm body
// without threading a fall-through target, so `lowerBody` fell back on its
// `.end` default. A conditional nested in that arm therefore terminated its own
// (empty) rejoin container with `end` — the story reported `isFinished` right
// after the inner arm's text, and EVERYTHING after the outer block was
// unreachable: trailing prose, and choices. There was no compile error and no
// load error, so the failure surfaced far from its cause (a missing choice at
// the top of an unrelated knot).
//
// Correctness gate: hermetic Level-1 execution-equivalence — native compile vs
// the committed inklecate `.ink.json` oracle, both played through the pure-Swift
// `Story`. The fixture nests on BOTH arm kinds (inside `- else:` and inside the
// implicit true arm) and follows each outer block with prose plus, in the first
// knot, a choice — the two things the defect swallowed.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — a conditional nested in an arm rejoins the outer continuation")
struct Compiler_NestedConditionalArmTests {

    // Scenario: the whole fixture plays line-for-line and choice-for-choice like
    // the oracle, across both nesting shapes.
    @Test
    func `a conditional nested in an arm plays identically to the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-nested-conditional-arm", choiceScript: [0])

        #expect(result.native == result.oracle)
    }

    // Scenario: nesting inside `- else:`. The inner arm's text plays AND the
    // prose after the outer block follows — the defect emitted only the former.
    @Test
    func `prose after an outer block whose else arm nests another block still plays`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-nested-conditional-arm", choiceScript: [0])

        #expect(result.oracle.prefix(3) == ["Before nesting.", "Two.", "After nesting."])
        #expect(result.native.prefix(3) == result.oracle.prefix(3))
    }

    // Scenario: the choice that followed the outer block is still offered. This
    // is the shape the defect was found through — the story ended silently
    // instead of presenting the menu.
    @Test
    func `a choice after an outer block whose arm nests another block is still offered`() throws {
        let source = try CompilerOracle.source("compile-nested-conditional-arm")
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        while story.canContinue { _ = story.`continue`() }

        #expect(story.currentChoices.map(\.text) == ["Continue"])
    }

    // Scenario: nesting inside the IMPLICIT TRUE arm (`{ y == 1:` opens the arm
    // directly), the mirror image of the `- else:` case. Guards against a fix
    // that only threads the fall-through on one arm kind.
    @Test
    func `prose after an outer block whose true arm nests another block still plays`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-nested-conditional-arm", choiceScript: [0])

        #expect(result.oracle.suffix(3) == [
            "Before second nesting.", "Nested in the true arm.", "After second nesting.",
        ])
        #expect(result.native.suffix(3) == result.oracle.suffix(3))
    }
}
