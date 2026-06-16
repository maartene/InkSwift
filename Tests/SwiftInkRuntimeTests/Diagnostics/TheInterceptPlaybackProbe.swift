// DIAGNOSTIC HARNESS (opt-in; not run in the normal suite).
// TheIntercept WORKED EXAMPLE of the playback first-divergence probe.
// Thin caller of the reusable OracleDiagnostics core (see OracleDiagnostics.swift);
// for ANY other bundled story use the generic env-driven OracleDivergenceProbe.
//
// Run on demand:  DIAG_INTERCEPT2=1 swift test --filter TheInterceptPlaybackProbe
// Evidence for: docs/feature/native-compiler-emission-alignment/ (ADR-012 phases)
// Disabled by default so it does not slow or spam the standard suite.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("DIAG TheIntercept playback")
struct TheInterceptPlaybackProbe {

    /// The canonical choice script the playback probe drives TheIntercept along.
    private static let script = [0, 2, 1, 0, 0, 1, 2, 0, 1, 0]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIAG_INTERCEPT2"] != nil))
    func `play native vs oracle and report first divergence`() throws {
        try OracleDiagnostics.firstDivergence(story: "TheIntercept", script: Self.script)
            .printReport()
        #expect(Bool(true))
    }
}
