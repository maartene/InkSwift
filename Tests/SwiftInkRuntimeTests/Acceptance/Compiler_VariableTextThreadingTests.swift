// DISTILL — native-compiler-emission-alignment Phase 3 (#3b): variable-text
// gather-lead / inline continuation threading + loose-end fall-through.
//
// Each AT pins one construct from the SPIKE-tuned fixture table
// (feature-delta.md `## Wave: SPIKE / [REF] Phase-3 feasibility` → DISTILL tuning).
// They assert execution-equivalence (native compile + play == inklecate oracle
// played through the same runtime along the same choice script), NOT structural
// field identity (D1/D5 Level-1 correctness, ADR-012).
//
// Driving port: InkCompiler.compile(source:) → Story(blueprint:) → play.
//
// Authored `.disabled` per the project's DISTILL discipline (CLAUDE.md): the
// suite stays green/skipped until DELIVER native-compiler-emission-alignment
// Phase 3 re-enables each AT on green. The `.disabled("…")` string is a TRAIT
// ARGUMENT, not a `@Test` display name — the backtick-name mandate is honoured.
//
// Two-layer bug (SPIKE finding):
//   layer 1 — gather-lead variable-text threading: the gather's nested choices
//             must become the continuation (`seq*-end`) of the variable-text
//             lead line, not orphaned siblings (today: dead-end, native play []).
//   layer 2 — loose-end propagation: `continuationLowerer` passes a hardcoded
//             `fallThrough: .end`, mis-compiling the fall-through target whenever
//             a variable-text line precedes choices that then gather. This also
//             mis-compiles the INLINE variable-text path (not just gather-lead),
//             which is why `vt-inline-choices-gather` belongs to the same DELIVER
//             step even though it is not a gather-lead shape.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — variable-text gather-lead / inline continuation threading (#3b)")
struct Compiler_VariableTextThreadingTests {

    // LAYER 1 (threading), loose-end = END. The gather's nested choices must
    // thread off the `{|…|}` lead line; selecting a choice reaches its body and
    // falls through to END. Script [0] picks the left door.
    @Test(.disabled("pending DELIVER native-compiler-emission-alignment Phase 3 (#3b): gather-lead/inline variable-text continuation threading + loose-end fall-through fix"))
    func `gather-lead variable-text threads its nested choices then ends, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-gather-lead-end", choiceScript: [0])
        #expect(result.native == result.oracle)
    }

    // LAYER 2 (discriminating): identical to the -end shape but the loose-end is
    // a trailing gather `- The hall falls quiet.`. The choice body must fall
    // through to the enclosing gather, not to END — exactly the hardcoded
    // `fallThrough: .end` bug. Script [0] → left door, "They wait.", "The hall
    // falls quiet.".
    @Test(.disabled("pending DELIVER native-compiler-emission-alignment Phase 3 (#3b): gather-lead/inline variable-text continuation threading + loose-end fall-through fix"))
    func `gather-lead variable-text falls through to the enclosing gather, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-gather-lead-gather", choiceScript: [0])
        #expect(result.native == result.oracle)
    }

    // LAYER 2, INLINE form (pre-existing latent bug, orthogonal to gather-lead):
    // a knot-lead inline `{|…|}` then choices then a trailing gather. Pins that
    // the loose-end fix also repairs the inline variable-text continuation.
    // Script [0] → "You step forward.", "The room settles.".
    @Test(.disabled("pending DELIVER native-compiler-emission-alignment Phase 3 (#3b): gather-lead/inline variable-text continuation threading + loose-end fall-through fix"))
    func `inline variable-text choices fall through to the trailing gather, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-inline-choices-gather", choiceScript: [0])
        #expect(result.native == result.oracle)
    }

    // Both layers, exact TheIntercept `opts`/`waited` miniature: gather lead
    // `{|…|}` + a single `* [Wait]` empty-body choice + a loose-end diverting to
    // `waited`. The empty bracket choice produces no body text but must thread to
    // `waited`. Script [0] → "Time passes.".
    @Test(.disabled("pending DELIVER native-compiler-emission-alignment Phase 3 (#3b): gather-lead/inline variable-text continuation threading + loose-end fall-through fix"))
    func `gather-lead variable-text with an empty-body choice threads to the continuation, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-gather-lead-empty-choice", choiceScript: [0])
        #expect(result.native == result.oracle)
    }

    // Mode-independence: the threading must hold for cycle `{&…}` and once
    // `{!…}` variable-text lead lines, not just the empty-first `{|…|}` form.
    // Sticky choices loop the gather twice (turns < 2), so visit 1 shows the
    // first cells and visit 2 the second cells. Script [0,0] picks the left door
    // both visits, exercising both alternatives of each mode.
    @Test(.disabled("pending DELIVER native-compiler-emission-alignment Phase 3 (#3b): gather-lead/inline variable-text continuation threading + loose-end fall-through fix"))
    func `gather-lead cycle and once variable-text thread identically across two visits, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-gather-lead-cycle-once", choiceScript: [0, 0])
        #expect(result.native == result.oracle)
    }

    // Boundary: exactly ONE nested choice under the variable-text gather lead
    // (single vs multi). Pins that threading does not depend on having ≥2
    // choices. Script [0] → only door, "The hall falls quiet.".
    @Test(.disabled("pending DELIVER native-compiler-emission-alignment Phase 3 (#3b): gather-lead/inline variable-text continuation threading + loose-end fall-through fix"))
    func `gather-lead variable-text with a single nested choice threads correctly, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("vt-gather-lead-single-choice", choiceScript: [0])
        #expect(result.native == result.oracle)
    }
}
