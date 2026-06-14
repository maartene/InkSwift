// @us-07 @kpi-3
//
// S5 / US-07 — the supported/unsupported feature reference must match ACTUAL
// compiler behaviour: every construct the reference marks "supported" compiles,
// and every construct it marks "unsupported" is rejected. This is the executable
// half of the doc-vs-compiler consistency check (KPI #3). The prose reference
// document (a DELIVER S5 deliverable) is held truthful against this canonical
// status list; this suite is the machine-checkable contract the prose mirrors.
//
// Driving port: InkCompiler.compile(source:). RED until DELIVER (supported
// fixtures throw `.scaffold`; rejected fixtures throw `.scaffold` not
// `.unsupportedConstruct`).

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler S5 — Feature Reference ↔ Compiler Consistency")
struct Compiler_S5_FeatureReferenceConsistencyTests {

    // The reference's MUST-COMPILE half (matrix rows 1-35): each fixture is a
    // representative of a documented-supported construct group.
    private static let documentedSupported: [String] = [
        "compile-skeleton-hello",       // text
        "compile-linear-flow",          // knots/stitches/diverts/glue
        "compile-variables",            // VAR/CONST/temp/operators/interpolation
        "compile-weave-flat",           // choices + gather
        "compile-ceiling",              // conditionals/functions/tunnels/ref/tags
    ]

    // The reference's MUST-REJECT half (matrix rows 25-28, 36-39).
    private static let documentedUnsupported: [String] = [
        "reject-seq", "reject-cycle", "reject-once", "reject-shuffle",
        "reject-thread", "reject-list", "reject-random", "reject-external",
    ]

    @Test(arguments: documentedSupported)
    func `a construct documented as supported actually compiles`(fixture: String) throws {
        // Must NOT throw: the reference promises this compiles.
        let blueprint = try InkCompiler.compile(source: try CompilerOracle.source(fixture))
        _ = Story(blueprint: blueprint)
    }

    @Test(arguments: documentedUnsupported)
    func `a construct documented as unsupported is actually rejected`(fixture: String) throws {
        let source = try CompilerOracle.source(fixture)
        do {
            _ = try InkCompiler.compile(source: source)
            Issue.record("\(fixture) is documented unsupported but the compiler accepted it (doc/compiler disagreement)")
        } catch let error as CompileError {
            #expect(error.kind == .unsupportedConstruct,
                    "\(fixture): documented-unsupported must reject with .unsupportedConstruct; got \(error.kind)")
        }
    }
}
