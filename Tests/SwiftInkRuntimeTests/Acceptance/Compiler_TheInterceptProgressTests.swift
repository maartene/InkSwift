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
    /// oracle for at least the first `floor` lines. Step 01-03 resolves the
    /// `-> pushes_cup` divert from the `[Deny]` choice body (TheIntercept.ink ~121).
    /// Four root causes, all in `Compiler/`:
    ///   1. PARSE — a deeper gather (`- - (pushes_cup)`) inside a level-1 `*` choice
    ///      now opens a NESTED weave inside that choice body (was swallowed as raw
    ///      body text, so `pushes_cup` was never emitted as a container).
    ///   2. KEYING — sibling choice/gather bodies' anonymous `cond{N}`/`seq{N}`
    ///      containers shared one ordinal counter per body and collided when promoted
    ///      to the enclosing scope; the `[Deny]` body's `{cooperate:…}` continuation
    ///      (holding `-> pushes_cup`) was clobbered. The ordinal counter now spans
    ///      sibling bodies (seeded from the shared collector), so each is unique.
    ///   3. DIVERT — a bare weave-label divert (`-> pushes_cup`) now qualifies to the
    ///      label's absolute physical path via the knot-namespace `weaveLabelPaths`
    ///      key, mirroring inklecate's by-name weave-point resolution.
    ///   4. PARSE — a plain prose line with a MID-line divert (`Harris looks
    ///      disapproving. -> pushes_cup`) and a gather outcome ending in trailing glue
    ///      (`… : <>`) now lower to text + glue + real divert instead of literal text.
    /// Native advances 11 → 15 oracle-matching lines. The NEXT blocker is at index 15:
    /// the oracle continues "Quite a difficult situation," he begins, sternly. …"
    /// (the post-`lift_up_cup` gather `g-... "Quite a difficult situation"`, ink ~148)
    /// where native runs out — next step.
    private static let floor = 15

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
