// @us-06 @error @kpi-2
//
// S6 / US-06 — every unsupported Ink construct (matrix rows 25-28, 36-44) is
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
    ("reject-string-inline-logic", "string with inline logic"),
    ("reject-tag-inline-logic", "tag with inline logic"),
    ("reject-tag-inside-inline-logic", "tag inside inline logic"),
]

// Every place a string literal with inline logic, a tag with inline logic, or a
// tag inside inline logic can sit (issue #31), each checked against inklecate
// 1.2.1, which accepts all of them but the `VAR` one ("Constant strings cannot
// contain any logic"). The native compiler kept the braces, or the tag inside an
// inline `{…}`, as literal text; where a string sits in a `{…}` condition, it
// lost track of the braces and played garbage. Each entry is
// (source, construct, line, column). A `nil` column is not checked: a statement
// inside a block reaches the parser trimmed, so its column counts from the
// trimmed text, an existing location gap for every block body statement.
private let inlineLogicShapes: [(source: String, construct: String, line: Int, column: Int?)] = [
    ("VAR n = 1\n~ temp t = \"a{n}\"\n{t}\n-> END\n", "string with inline logic", 2, 1),
    ("Line {f()}.\n-> END\n=== function f()\n    ~ return \"{3}\"\n", "string with inline logic", 4, 5),
    ("VAR y = 1\nVAR x = \"{y}\"\n{x}\n-> END\n", "string with inline logic", 2, 1),
    ("VAR n = 1\n~ temp t = \"a{&x|y}\"\n{t}\n-> END\n", "string with inline logic", 2, 1),
    ("VAR n = 1\nLine {g(\"a{n}\")}.\n-> END\n=== function g(s)\n~ return s\n", "string with inline logic", 2, 1),
    ("VAR n = 1\n* {\"a{n}\" == \"a1\"} Choice\n-> END\n", "string with inline logic", 2, 1),
    ("VAR n = 1\n{\"a{n}\" == \"a1\": yes|no}\n-> END\n", "string with inline logic", 2, 1),
    ("VAR n = 1\n{ \"a{n}\" == \"a1\":\n    yes\n}\nAfter.\n-> END\n", "string with inline logic", 2, 1),
    ("VAR n = 1\n{ n:\n- \"a{n}\" == \"a1\": yes\n}\nAfter.\n-> END\n", "string with inline logic", 3, 1),
    ("VAR n = 1\nLine # pic{n}.jpg\n-> END\n", "tag with inline logic", 2, 6),
    ("Line # a{x|y}\n-> END\n", "tag with inline logic", 1, 6),
    ("VAR n = 1\n# t{n}\nLine.\n-> END\n", "tag with inline logic", 2, 1),
    ("VAR n = 1\n* [Choice # t{n}]\n    Picked.\n    -> END\n", "tag with inline logic", 2, 11),
    ("VAR n = 1\n* [A] B # t{n}\n    -> END\n", "tag with inline logic", 2, 9),
    ("VAR n = 1\n- Gather # t{n}\n-> END\n", "tag with inline logic", 2, 10),
    ("VAR n = 1\n{ n > 0:\n    Arm. # t{n}\n}\nAfter.\n-> END\n", "tag with inline logic", 3, nil),
    ("VAR n = 1\n{n > 0: A # t{n}}\nNext.\n-> END\n", "tag inside inline logic", 2, 11),
    ("VAR n = 1\n{n > 0: A # t}{n} after.\nNext.\n-> END\n", "tag inside inline logic", 2, 11),
    ("VAR n = 0\n{n > 0: A|B # u} after.\nNext.\n-> END\n", "tag inside inline logic", 2, 13),
    ("{A # t|B} after.\nNext.\n-> END\n", "tag inside inline logic", 1, 4),
    ("{&A # t|B} after.\nNext.\n-> END\n", "tag inside inline logic", 1, 5),
    ("VAR n = 1\n{n > 0: She said \"#1\".} after.\nNext.\n-> END\n", "tag inside inline logic", 2, 19),
    ("VAR n = 1\n* [Pick {n > 0: A # t}]\n    -> END\n", "tag inside inline logic", 2, 19),
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

    @Test(arguments: inlineLogicShapes.indices)
    func `a string or tag with inline logic is rejected wherever it sits`(index: Int) throws {
        let shape = inlineLogicShapes[index]
        let error = #expect(throws: CompileError.self, "\(shape.source) must not compile") {
            try InkCompiler.compile(source: shape.source)
        }
        #expect(error?.kind == .unsupportedConstruct)
        #expect(error?.construct == shape.construct)
        #expect(error?.line == shape.line)
        if let column = shape.column {
            #expect(error?.column == column)
        }
    }

    // Only logic is rejected. Quotes in prose are text, with live interpolation,
    // and an escaped brace or hash is no logic at all; inklecate plays them all.
    // A tag in a block arm sits on a line of its own and compiles. (Only "not
    // rejected" is checked: escaped braces keep their backslash in InkSwift's
    // native compile today, a separate gap.)
    @Test(arguments: [
        "VAR n = 1\nShe said \"hi {n}\".\nAfter.\n-> END\n",
        "VAR n = 1\n{ n > 0: She said \"hi {n}\".}\nAfter.\n-> END\n",
        "Line # a\\{b\\}\nAfter.\n-> END\n",
        "VAR n = 1\n{n > 0: A \\# t} after.\nNext.\n-> END\n",
        "VAR n = 1\n{n > 0: A} after. # t\nNext.\n-> END\n",
        "VAR n = 1\n{ n > 0:\n    Arm. # t\n- else:\n    Other. # u\n}\nAfter.\n-> END\n",
        "~ temp t = \"a\\{b\\}\"\n{t}\nAfter.\n-> END\n",
    ])
    func `prose quotes and escaped braces are not mistaken for inline logic`(source: String) throws {
        _ = try InkCompiler.compile(source: source)
    }

    @Test func `quoted prose with interpolation still plays as inklecate plays it`() throws {
        let source = "VAR n = 1\nShe said \"hi {n}\".\nAfter.\n-> END\n"
        let story = Story(blueprint: try InkCompiler.compile(source: source))

        #expect(try CompilerOracle.play(story) == ["She said \"hi 1\".", "After."])
    }

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
