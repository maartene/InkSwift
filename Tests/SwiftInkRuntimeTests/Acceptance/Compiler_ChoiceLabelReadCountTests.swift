// DISTILL — native-compiler-emission-alignment Phase 1 (#4b): read-count
// references to a NAMED CHOICE LABEL nested in a knot.
//
// The diagnosed TheIntercept blocker (playback probe, 2026-06-15): two dotted
// read-count references survive UNRESOLVED as `.variableReference` (should be
// `.readCount`), because the ADR-011 weave-label resolution does not reach a
// choice-label nested in a knot when that label is referenced from a GUARD or
// an INLINE conditional:
//   * `start.delay`                          — guard:  `* {not start.delay} …`
//   * `harris_demands_component.cant_talk_right` — inline: `{harris…cant_talk_right: helplessly}`
//
// The existing green RED-pin AT (`Compiler_S4_CeilingTests.swift`:
// `a reference to a weave label lowers to a read-count node`) covers only a
// ROOT-LEVEL label `(door)` in a PLAIN inline conditional. These two ATs pin the
// missing shape: a label nested in a knot, referenced via `knot.label` from a
// guard / inline conditional, asserted by EXECUTION-EQUIVALENCE (native compile +
// play == inklecate oracle along the same choice script), NOT structural field
// identity (D1/D5 Level-1 correctness, ADR-012).
//
// Driving port: InkCompiler.compile(source:) → Story(blueprint:) → play.
//
// Authored `.disabled` per the project's DISTILL discipline (CLAUDE.md): the
// suite stays green/skipped until DELIVER native-compiler-emission-alignment
// Phase 1 (#4b) re-enables each AT on green. The `.disabled("…")` string is a
// TRAIT ARGUMENT, not a `@Test` display name — the backtick-name mandate is
// honoured.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — read-count references to a nested choice label (#4b)")
struct Compiler_ChoiceLabelReadCountTests {

    // GUARD shape (`start.delay`): a knot `start` with a labelled choice
    // `(delay)` and another choice GUARDED by `{not start.delay}`. The read-count
    // of the nested choice label must change which choices are available:
    //   script [0,1] →
    //     "You stand at the threshold."            (delay count 0 → guard true → Press on offered: 3 choices)
    //     pick 0 (Wait a moment) → delay count 1
    //     "You hesitate. You stand at the threshold." (guard now false → Press on SUPPRESSED: 2 choices)
    //     pick 1 (Give up) → "You turn back." → END
    // If `start.delay` survives as a `.variableReference`, the guard cannot
    // evaluate and the available-choice set diverges from the oracle.
    @Test
    func `read-count of a nested choice label used in a guard suppresses the guarded choice, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("rc-choicelabel-guard", choiceScript: [0, 1])
        #expect(result.native == result.oracle)
    }

    // INLINE shape (`harris_demands_component.cant_talk_right`): a knot `harris`
    // with a labelled choice `(cant_talk_right)` and later INLINE text
    // `{harris.cant_talk_right: helplessly}`. The read-count of the nested choice
    // label must gate the inline word:
    //   script [0,1] →
    //     "Harris looks up."
    //     pick 0 (Press him for answers) → cant_talk_right count 1
    //     "He shakes his head. Harris looks up."
    //     pick 1 (Step back) → "You speak helplessly." (inline rendered) → END
    // If `harris.cant_talk_right` survives as a `.variableReference`, the inline
    // conditional cannot evaluate and the rendered text diverges from the oracle.
    @Test
    func `read-count of a nested choice label used in an inline conditional renders the gated word, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("rc-choicelabel-inline", choiceScript: [0, 1])
        #expect(result.native == result.oracle)
    }
}
