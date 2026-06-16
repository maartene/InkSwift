// GENERIC ENV-DRIVEN ORACLE PROBE (opt-in; not run in the normal suite).
//
// Diagnose ANY bundled Ink story (native-vs-oracle) with ZERO new code:
//
//   DIAG_STORY=TheIntercept DIAG_SCRIPT=0,2,1,0,0,1,2,0,1,0 \
//     swift test --filter OracleDivergenceProbe
//
// Reads:
//   DIAG_STORY    — fixture base name (the `.ink` / `.ink.json` pair, REQUIRED;
//                   the probe is disabled unless it is set).
//   DIAG_SCRIPT   — comma-separated choice indices (default `0`).
//   DIAG_MAXLINES — optional playback ceiling (default 200).
//   DIAG_STRICT   — when set to any non-empty value the probe ASSERTS that
//                   native compilation succeeded (nativeError == nil). Without
//                   it the probe is purely diagnostic: it always passes even
//                   when the native compile throws, so that partial-support
//                   stories can be diagnosed incrementally. Set DIAG_STRICT=1
//                   to turn the probe into a hard compile-success gate.
//
// Prints BOTH the playback first-divergence report AND the structural census,
// delegating all logic to the reusable OracleDiagnostics core.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("DIAG generic oracle divergence")
struct OracleDivergenceProbe {

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIAG_STORY"] != nil))
    func `play and structurally diff any DIAG_STORY against its oracle`() throws {
        let env = ProcessInfo.processInfo.environment
        let story = try #require(env["DIAG_STORY"], "DIAG_STORY must name a bundled fixture")
        let script = Self.parseScript(env["DIAG_SCRIPT"])
        let maxLines = env["DIAG_MAXLINES"].flatMap { Int($0) } ?? 200
        let strict = env["DIAG_STRICT"].map { !$0.isEmpty } ?? false

        let divergence = try OracleDiagnostics.firstDivergence(story: story, script: script, maxLines: maxLines)
        divergence.printReport()
        try OracleDiagnostics.structuralCensus(story: story)
            .printReport()

        if strict {
            #expect(divergence.nativeError == nil, "DIAG_STRICT: native compile threw — \(divergence.nativeError ?? "")")
        }
        // Without DIAG_STRICT the probe is diagnostic-only: it always passes so
        // partially-supported stories can be diagnosed without blocking the run.
    }

    /// Parse a comma-separated `DIAG_SCRIPT` into choice indices; default `[0]`.
    private static func parseScript(_ raw: String?) -> [Int] {
        guard let raw, !raw.isEmpty else { return [0] }
        let parsed = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return parsed.isEmpty ? [0] : parsed
    }
}
