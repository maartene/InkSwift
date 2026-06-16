// DIAGNOSTIC HARNESS (opt-in; not run in the normal suite).
// TheIntercept WORKED EXAMPLE of the structural native-vs-oracle tree diff.
// Thin caller of the reusable OracleDiagnostics core (see OracleDiagnostics.swift);
// for ANY other bundled story use the generic env-driven OracleDivergenceProbe.
//
// Run on demand:  DIAG_INTERCEPT=1 swift test --filter TheInterceptDivergenceDiagnostic
// Evidence for: docs/analysis/theintercept-native-divergence-2026-06-15.md
// Disabled by default so it does not slow or spam the standard suite.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("DIAG TheIntercept divergence")
struct TheInterceptDivergenceDiagnostic {

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIAG_INTERCEPT"] != nil))
    func `dump native-vs-oracle structural divergences for TheIntercept`() throws {
        try OracleDiagnostics.structuralCensus(story: "TheIntercept").printReport()
        #expect(Bool(true))
    }
}
