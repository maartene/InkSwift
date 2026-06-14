// @us-04 @real-io @kpi-1 @weave-spike
//
// S3 / US-04 — compile an interactive story: plain/bracketed/sticky choices,
// gathers (incl. labeled) and nested weaves, plus the COMPILE-TIME choice-flag /
// invisible-default encoding the runtime assumes was done (D6, matrix rows 6-14).
//
// Weave resolution is the research-flagged HIGHEST-RISK algorithm; S3 sizing is
// spike-gated (ADR-008 / DDD-6). This four-fixture corpus (flat / nested /
// labeled-gather / sealed) is exactly the weave-spike gate: native compile must
// play line-for-line / choice-for-choice identical to the inklecate oracle along
// fixed choice paths before S3 is committed.
//
// Driving port: InkCompiler.compile(source:). RED until DELIVER S3.

import Testing
import Foundation
@testable import SwiftInkRuntime

// The weave corpus + a deterministic choice script per fixture. Both the native
// and oracle stories follow the SAME script, so equivalence is path-stable.
private let weaveFixtures: [String] = [
    "compile-weave-flat",
    "compile-weave-nested",
    "compile-weave-labeled-gather",
    "compile-weave-sealed",
]
private let weaveScripts: [[Int]] = [
    [0],        // flat: take first choice, fall to gather
    [0, 0],     // nested: Open it → Step through
    [0, 0],     // labeled-gather: Left → middle → Forward
    [0],        // sealed: Fight past → END (all options divert away)
]

@Suite("Compiler S3 — Choices & Gathers (weave-spike corpus)")
struct Compiler_S3_ChoicesGathersTests {

    @Test(arguments: Array(zip(weaveFixtures, weaveScripts)))
    func `a weave fixture compiles and plays choice-for-choice identical to the oracle`(
        fixture: String,
        script: [Int]
    ) throws {
        let result = try CompilerOracle.compileAndPlay(fixture, choiceScript: script)

        #expect(result.native == result.oracle, "weave fixture \(fixture) diverged from the oracle")
    }
}
