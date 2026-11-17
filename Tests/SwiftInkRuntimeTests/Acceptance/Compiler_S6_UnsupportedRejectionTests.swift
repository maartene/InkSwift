// @us-06 @error @kpi-2
//
// S6 / US-06 — every unsupported Ink construct (matrix rows 25-28, 36-41) is
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
    ("reject-multiline-sequence", "multi-line sequence"),
    ("reject-include", "include"),
]

// Every multi-line sequence opener the reference grammar accepts
// (InkParser_Sequences.cs): word annotations followed by `:`, alone or combined
// with `shuffle`, and the symbol annotations, which take no colon. The reference
// tries an explicit sequence annotation before any conditional
// (InkParser_Logic.cs, InnerLogic), so `{once:` is a sequence even when a variable
// is named `once`.
private let multilineSequenceOpeners: [String] = [
    "{stopping:", "{cycle:", "{once:", "{shuffle:", "{shuffle once:", "{shuffle stopping:",
    "{&", "{!", "{~", "{$",
]

@Suite("Compiler S6 — Unsupported-Construct Rejection (fail loud, never silent)")
struct Compiler_S6_UnsupportedRejectionTests {

    @Test(arguments: multilineSequenceOpeners)
    func `a multi-line sequence is rejected wherever it opens, top level or nested`(opener: String) throws {
        let topLevel = "Before.\n\(opener)\n    - one\n    - two\n}\nAfter.\n-> END\n"
        let nested = "VAR x = 1\n{ x == 1:\n    \(opener)\n        - one\n        - two\n    }\n}\nAfter.\n-> END\n"
        for (shape, source) in [("top level", topLevel), ("nested in a conditional", nested)] {
            let error = #expect(throws: CompileError.self, "\(opener) (\(shape)) must not compile") {
                try InkCompiler.compile(source: source)
            }
            #expect(error?.kind == .unsupportedConstruct, "\(opener) (\(shape)): got \(String(describing: error?.kind))")
            #expect(error?.construct == "multi-line sequence", "\(opener) (\(shape)): got \(String(describing: error?.construct))")
            #expect(error?.line == (shape == "top level" ? 2 : 3), "\(opener) (\(shape)): got line \(String(describing: error?.line))")
        }
    }

    // Only a subject made entirely of annotation words is a sequence: the reference
    // reads `{ once and ready:` as a conditional (inklecate plays its true branch).
    @Test func `a conditional whose subject only mentions an annotation word still compiles`() throws {
        let source = "VAR once = true\nVAR ready = true\n{ once and ready:\n    Both hold.\n}\nAfter the conditional.\n-> END\n"
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        #expect(story.continueMaximally() == "Both hold.\nAfter the conditional.\n")
    }

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
