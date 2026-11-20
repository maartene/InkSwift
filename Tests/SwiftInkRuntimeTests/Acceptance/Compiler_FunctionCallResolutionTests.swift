// Issue #36 — the native compiler resolves function calls at compile time, as
// inklecate does (ADR-025 §4; C# `FunctionCall.cs`).
//
// Before: every call compiled to an unresolved `.functionCall`. At runtime that
// pushed a frame that never popped and printed the last argument, so
// `{nosuchfunction(1.5)}` played `1.5`, `{FLOOR(1.5)}` printed `1.5` and
// `{MIN(1, 2)}` only looked right because its last argument was the answer.
//
// Now: a supported built-in is arity-checked and compiles to its native; a
// story function compiles to a call; any other name is rejected with
// inklecate's "Function call target not found" message, at the call's line.
// Expected texts and values were recorded from inklecate (`-p`, invariant
// culture) on 2026-11-20.
//
// Every rejected story continues past the call (prose, then a choice), so a
// compiler that skipped the call and played on would not pass.
//
// Driving port: InkCompiler.compile(source:) + Story.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — function call resolution (#36)")
struct Compiler_FunctionCallResolutionTests {

    struct Rejection: CustomTestStringConvertible, Sendable {
        let source: String
        let kind: CompileErrorKind
        let message: String
        let line: Int
        var testDescription: String { message }
    }

    static let undefinedCalls: [Rejection] = [
        Rejection(
            source: "Before.\nValue: {nosuchfunction(1.5)}.\nAfter.\n* Go\n    -> END\n",
            kind: .unresolvedReference,
            message: "Function call target not found: '-> nosuchfunction'",
            line: 2
        ),
        Rejection(
            source: "Before.\n~ nosuchfunction(2)\nAfter.\n* Go\n    -> END\n",
            kind: .unresolvedReference,
            message: "Function call target not found: '-> nosuchfunction'",
            line: 2
        ),
        Rejection(
            source: "Before.\n\n~ gret()\nAfter.\n* Go\n    -> END\n\n=== function greet()\n~ return 1\n",
            kind: .unresolvedReference,
            message: "Function call target not found: '-> gret'",
            line: 3
        ),
        Rejection(
            source: "Before.\n\n* {nosuchfunction()} Go\n    After.\n    -> END\n* Stay\n    -> END\n",
            kind: .unresolvedReference,
            message: "Function call target not found: '-> nosuchfunction'",
            line: 3
        ),
    ]

    static let arityMismatches: [Rejection] = [
        Rejection(
            source: "Before.\n{FLOOR(1, 2)}\nAfter.\n* Go\n    -> END\n",
            kind: .syntaxError,
            message: "FLOOR should take 1 parameter",
            line: 2
        ),
        Rejection(
            source: "Before.\n{MIN(1)}\nAfter.\n* Go\n    -> END\n",
            kind: .syntaxError,
            message: "MIN should take 2 parameters",
            line: 2
        ),
    ]

    @Test(arguments: undefinedCalls + arityMismatches)
    func `a call inklecate rejects does not compile, located at the call with inklecate's message`(
        _ rejection: Rejection
    ) {
        let error = #expect(throws: CompileError.self) {
            _ = try InkCompiler.compile(source: rejection.source)
        }
        #expect(error?.kind == rejection.kind)
        #expect(error?.message == rejection.message)
        #expect(error?.line == rejection.line)
    }

    @Test func `supported built-ins compile to natives and play exactly as inklecate prints them`() throws {
        let result = try CompilerOracle.compileAndPlay("issue36-builtin-casts")

        let expected = ["1", "1", "2", "0.5", "2", "1", "2", "0.6666667", "After the built-ins.", "Keep going", "The choice played."]
        #expect(result.oracle == expected)
        #expect(result.native == expected)
    }

    @Test func `a built-in call leaves no function frame behind`() throws {
        let story = Story(blueprint: try InkCompiler.compile(source: "{MIN(1, 2)}\nAfter.\n* Go\n    -> END\n"))

        #expect(story.continue() == "1\n")
        #expect(story.continue() == "After.\n")
        #expect(story.engine.state.returnStack.isEmpty)
    }
}
