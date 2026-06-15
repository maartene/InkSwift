// @us-06 @error @kpi-2
//
// S6 / US-06 — every unsupported Ink construct (matrix rows 25-28, 36-39) is
// rejected with a CLEAR, LOCATED, construct-NAMED error and NO story produced.
// This is the feature's defining safety property: 0% silent wrong output (D2 /
// KPI #2 hard guardrail). One fixture per construct; sad paths are enumerated,
// never generated.
//
// Driving port: InkCompiler.compile(source:). RED until DELIVER S6 — the scaffold
// throws `.scaffold`, so the kind/construct/location assertions below fail until
// the real reject-list detection lands.

import Testing
import Foundation
@testable import SwiftInkRuntime

// fixture name → the construct word the located error must name (case-insensitive).
// Variable-text rejection is now shuffle-ONLY (slice-01, DDD-5 / DISTILL U-2):
// the deterministic sequence/cycle/once forms COMPILE via VariableTextEmitter, so
// `reject-seq`/`reject-cycle`/`reject-once` left this corpus. Shuffle stays
// unsupported (no deterministic lowering), as do the statement-level constructs.
private let rejectCorpus: [(fixture: String, construct: String)] = [
    ("reject-shuffle", "shuffle"),
    ("reject-thread", "thread"),
    ("reject-list", "list"),
    ("reject-random", "random"),
    ("reject-external", "external"),
]

@Suite("Compiler S6 — Unsupported-Construct Rejection (fail loud, never silent)")
struct Compiler_S6_UnsupportedRejectionTests {

    @Test(arguments: rejectCorpus)
    func `an unsupported construct is rejected with a named, located error and no story`(
        fixture: String,
        construct: String
    ) throws {
        let source = try CompilerOracle.source(fixture)

        do {
            _ = try InkCompiler.compile(source: source)
            Issue.record("\(fixture).ink uses an unsupported construct but compiled to a story (SILENT ACCEPTANCE — KPI #2 violation)")
        } catch let error as CompileError {
            #expect(error.kind == .unsupportedConstruct,
                    "\(fixture): expected .unsupportedConstruct, got \(error.kind)")
            #expect(error.construct?.range(of: construct, options: .caseInsensitive) != nil,
                    "\(fixture): error should NAME the construct '\(construct)'; got \(String(describing: error.construct))")
            #expect(error.line > 0,
                    "\(fixture): error should report a source LOCATION (line > 0); got line \(error.line)")
        }
    }
}
