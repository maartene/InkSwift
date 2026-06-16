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
    /// oracle for at least the first `floor` lines. Step 01-04 resolves the
    /// post-`lift_up_cup` gather (TheIntercept.ink ~148), where native dead-ended
    /// after the `lift_up_cup` choice body. Three root causes, all in `Compiler/`:
    ///   1. FALL-THROUGH — an inline conditional `{took:lift|take}` MID-body (the
    ///      `lift_up_cup` body) routed flow into its `cond{N}-end` rejoin container,
    ///      but the body's loose-end fall-through divert was emitted (unreachable)
    ///      AFTER the dispatch instead of inside the rejoin. The enclosing
    ///      fall-through now threads into the rejoin so flow rejoins the gather.
    ///   2. READ-COUNT — a bare choice-label read-count conditional
    ///      (`{lift_up_cup:he|Harris}`) resolved as a plain variable (always false →
    ///      "Harris"). A bare label that is UNIQUE story-wide is now registered in the
    ///      read-count table so it lowers to `CNT?` of the label's container, matching
    ///      inklecate's local-scope by-name resolution → "he".
    ///   3. WEAVE-IN-CONTINUATION — choices trailing an inline-conditional line
    ///      (`… begins{forceful<=0:,sternly}.` then `[Agree]/[Disagree]/…`) flattened
    ///      into the rejoin as literal prose. The rejoin now routes a weave-bearing
    ///      continuation through the WeaveEmitter (real choicePoints), nesting its
    ///      containers under the rejoin's own scope to avoid sibling collisions.
    /// Native advances 15 → 16 oracle-matching lines. The NEXT blocker is at index 16:
    /// native splits the gather line "…I reply, sipping at my tea…" and emits a literal
    /// "}" — the multi-line block conditional `{ teacup: ~drugged=true <>, sipping… }`
    /// with an embedded assignment + glue (ink ~159) is not yet lowered — next step.
    private static let floor = 16

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
