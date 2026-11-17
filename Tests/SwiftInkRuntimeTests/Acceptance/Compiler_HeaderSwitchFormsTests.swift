// @regression @real-io @kpi-1
//
// A block conditional with a header expression whose body opens DIRECTLY with
// `- guard:` arms is a SWITCH: each arm's expression is compared for equality
// with the header's value — whatever the header's type, a boolean comparison
// included (issue #22). A header block whose only arm is `- else:` is instead a
// plain if/else with an empty true branch.
//
// Ground truth (inklecate 1.2.1, `InkParser_Conditional.cs` — the
// `initialQueryExpression` loop over `alternatives`): a branch with its own
// expression gets `matchingEquality`; a final branch without one is the else;
// when no branch has its own expression the block is binary (true / else). The
// decision is structural — it never looks at the header's operators.
//
// Defect this pins: `InkParser.switchOrGuardedBlock` decided "switch or not"
// from the header TEXT: a header containing a comparison operator was never a
// switch, so `{ x == 1: - true: A - false: B }` tested each arm on its own and
// `- true:` always won. Conversely a bare header (`{ flag: - else: B }`) was
// always a switch, so an else-only block took the else arm even when the
// header held. Both compiled without error and played differently from the
// oracle.
//
// Correctness gate: hermetic Level-1 execution-equivalence — native compile vs
// the committed inklecate `.ink.json` oracle. Every block in the fixture is
// followed by prose, and the first knot ends in a choice, so an arm that failed
// to rejoin would also show.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — a header block opening with arms switches on the header value")
struct Compiler_HeaderSwitchFormsTests {

    @Test
    func `header switches play identically to the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-header-switch-forms", choiceScript: [0])

        #expect(result.native == result.oracle)
    }

    // Scenario: the issue #22 shape. `x == 1` is false, so the arm matching
    // `false` is taken — not the `- true:` arm read as its own guard.
    @Test
    func `a switch on a boolean comparison takes the arm equal to its value`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-header-switch-forms", choiceScript: [0])

        #expect(result.oracle.prefix(8) == [
            "Bool false arm.", "After the boolean switch.",
            "Bool else arm.", "After the boolean switch with else.",
            "Not-equal true arm.", "After the not-equal switch.",
            "Compound true arm.", "After the compound switch.",
        ])
        #expect(result.native.prefix(8) == result.oracle.prefix(8))
    }

    // Scenario: an else-only block with a bare header is an if/else with an
    // empty true branch, not a switch whose only arm is the default.
    @Test
    func `an else-only block under a true header plays nothing from the else arm`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-header-switch-forms", choiceScript: [0])

        #expect(result.native.contains("Flag else arm.") == false)
        #expect(result.native.contains("After the else-only block."))
    }

    // Scenario: value and arithmetic switches — the shapes that already worked —
    // still switch, and the choice after the last first-knot block is offered.
    @Test
    func `value switches still match and the following choice is offered`() throws {
        let source = try CompilerOracle.source("compile-header-switch-forms")
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        let text = story.continueMaximally()

        #expect(text.hasSuffix("Value two.\nAfter the value switch.\n"))
        #expect(story.currentChoices.map(\.text) == ["Continue"])
    }
}
