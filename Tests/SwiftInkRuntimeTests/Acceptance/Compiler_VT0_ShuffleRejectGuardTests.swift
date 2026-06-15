// @us-01 @us-02 @us-03 @us-04 @error @kpi-3 @guardrail
//
// compiler-variable-text — shuffle-reject REGRESSION GUARD (matrix row 28).
//
// This feature narrows `UnsupportedConstructDetector` so sequence/cycle/once
// (rows 25-27) pass through to lowering, while shuffle `{~a|b}` (row 28) STAYS
// rejected — it additionally needs RANDOM, a genuine runtime gap (D-A / DDD-5 /
// KPI #3 guardrail). The risk is that widening the variable-text parser path
// accidentally swallows shuffle into the new lowering ("silent acceptance").
//
// This guard is ENABLED and GREEN today (shuffle already rejects) and MUST stay
// green through every DELIVER slice. It is the always-on tripwire the per-slice
// work commits against — if any slice's gate change lets shuffle through, this
// reds immediately.
//
// Driving port: InkCompiler.compile(source:).

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler VT0 — Shuffle stays rejected (regression guard for rows 25-27 work)")
struct Compiler_VT0_ShuffleRejectGuardTests {

    @Test func `a shuffle form is rejected with a named, located error and no story is produced`() throws {
        let source = try CompilerOracle.source("reject-shuffle")

        do {
            _ = try InkCompiler.compile(source: source)
            Issue.record("shuffle '{~a|b}' compiled to a story — SILENT ACCEPTANCE (KPI #3 / row 28 must stay rejected)")
        } catch let error as CompileError {
            #expect(error.kind == .unsupportedConstruct,
                    "shuffle must reject with .unsupportedConstruct; got \(error.kind)")
            #expect(error.construct?.range(of: "shuffle", options: .caseInsensitive) != nil,
                    "the located error must NAME 'shuffle'; got \(String(describing: error.construct))")
            #expect(error.line > 0,
                    "the error must report a source LOCATION (line > 0); got line \(error.line)")
        }
    }
}
