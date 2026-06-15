// DELIVER — native-compiler-emission-alignment, step 01-01 (PROBE-DRIVEN).
//
// Ratchet suite for the REAL TheIntercept playthrough. Synthetic minimal fixtures
// kept FALSE-GREENING (passing while the real story stayed broken — feature-delta.md
// `#4b … RE-DIAGNOSIS`), so this suite drives against the REAL TheIntercept along the
// canonical choice script, pinning the achieved oracle-matching line FLOOR (N).
//
// Each step ratchets N upward: native[0..<N] must equal oracle[0..<N], with N > 4
// (before this step native dead-ended at 4 lines entering the real `opts` gather).
// The floor only goes UP — a regression that drops below N reds the suite.
//
// Driving port: InkCompiler.compile(source:) → Story(blueprint:) → play along the
// canonical script. Execution-equivalence (D5 Level-1, ADR-012), example-based
// oracle per CLAUDE.md (OOP paradigm; PBT N/A; mutation disabled).

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — TheIntercept native playthrough progress ratchet")
struct Compiler_TheInterceptProgressTests {

    /// The canonical choice script the playback probe drives TheIntercept along.
    private static let script = [0, 2, 1, 0, 0, 1, 2, 0, 1, 0]

    /// The achieved oracle-matching line floor for this step. Native must match the
    /// oracle for at least the first `floor` lines. Step 01-02 resolves the real
    /// deeply-nested `start.delay` read-count guard: `(delay)` is a choice label
    /// nested 3 levels deep (`start` knot → `opts` gather → `plan` choice → `delay`
    /// choice) but referenced FLAT as `start.delay` (line 113). The discovery
    /// pre-pass now walks variable-text-FOLDED bodies and registers a deeply-nested
    /// label under the knot's flat namespace (`start.delay` → real path
    /// `start.plan.delay`), so `{not start.delay}` evaluates correctly and native
    /// picks "Tell me what this is about." (oracle index 6) instead of "I say
    /// nothing.". `harris_demands_component.cant_talk_right` resolves likewise.
    /// Surviving-dotted count dropped 2 → 0; native advances 6 → 11 oracle-matching
    /// lines. The NEXT blocker is at index 11: after the `(tellme)`/`[Deny]` path
    /// native runs out where the oracle continues "Harris looks disapproving. He
    /// pushes one mug halfway towards me…" (the `-> pushes_cup` divert) — next step.
    private static let floor = 11

    @Test
    func `native TheIntercept plays past the opts gather, matching the oracle prefix`() throws {
        let result = try CompilerOracle.compileAndPlay("TheIntercept", choiceScript: Self.script)
        #expect(
            result.native.count >= Self.floor,
            "native played only \(result.native.count) lines; expected at least \(Self.floor)"
        )
        #expect(
            Array(result.oracle.prefix(Self.floor)) == Array(result.native.prefix(Self.floor)),
            "native diverged from the oracle within the first \(Self.floor) lines"
        )
    }
}
