// Issue #36, part 2 — one vocabulary for unsupported built-ins (ADR-025 §4-6).
//
// A built-in the runtime cannot play is refused under the same name whether the
// story is compiled natively (`CompileError.construct`) or loaded from
// inklecate's JSON (`UnsupportedFeature.name`). Before, the native compiler
// compiled TURNS(), CHOICE_COUNT() and READ_COUNT() to a call of an undefined
// function that played wrong, called RANDOM "random", and rejected SEED_RANDOM,
// which the runtime accepts.
//
// SEED_RANDOM: the reference's `srnd` pops the seed and pushes void
// (Story.cs, SeedRandom), so the `pop` compiled for the discarded call removes
// that void. InkSwift's `srnd` pushed nothing, so the `pop` removed whatever sat
// below it: in `{1 + seeded()}` the 1 waiting for the sum, which played 2.
//
// Expected texts were recorded from inklecate 1.2.1 (`-p`, invariant culture)
// on 2026-11-20. Every rejected story continues past the call, so a compiler
// that skipped the call and played on would not pass.
//
// Driving port: InkCompiler.compile(source:) and Story(json:).

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — unsupported built-ins under the runtime's names (#36)")
struct Compiler_UnsupportedBuiltinRejectionTests {

    struct Rejection: CustomTestStringConvertible, Sendable {
        let source: String
        let construct: String
        let line: Int
        var column: Int? = nil
        var testDescription: String { construct }
    }

    static let continuation = "After.\n* Go\n    -> k\n\n=== k\nIn k.\n-> END\n"

    static let rejections: [Rejection] = [
        Rejection(source: "Before.\n{TURNS()}\n" + continuation, construct: "TURNS()", line: 2),
        Rejection(source: "Before.\n~ temp c = CHOICE_COUNT()\n" + continuation, construct: "CHOICE_COUNT()", line: 2),
        Rejection(source: "Before.\n{RANDOM(1, 6)}\n" + continuation, construct: "RANDOM()", line: 2),
        Rejection(source: "Before.\n{READ_COUNT(-> k)}\n" + continuation,
                  construct: "READ_COUNT() of a divert-target variable", line: 2, column: 2),
        Rejection(source: "Before.\nCount: {TURNS_SINCE(-> k)}.\n" + continuation,
                  construct: "TURNS_SINCE()", line: 2, column: 9),
        Rejection(source: "Before.\n~ temp n = TURNS_SINCE(-> k) + 1\n" + continuation,
                  construct: "TURNS_SINCE()", line: 2, column: 12),
    ]

    @Test(arguments: rejections)
    func `an unsupported built-in is rejected, located, under the runtime's name`(_ rejection: Rejection) {
        let error = #expect(throws: CompileError.self) {
            _ = try InkCompiler.compile(source: rejection.source)
        }
        #expect(error?.kind == .unsupportedConstruct)
        #expect(error?.construct == rejection.construct)
        #expect(error?.line == rejection.line)
        if let column = rejection.column {
            #expect(error?.column == column)
        }
    }

    @Test func `SEED_RANDOM from inklecate's JSON plays as inklecate does, with the evaluation stack balanced`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON("issue36-seed-random"))

        #expect(try CompilerOracle.play(story) == ["3", "After the seed.", "Keep going", "The choice played."])
        #expect(story.engine.state.evalStack.isEmpty)
    }

    @Test func `SEED_RANDOM compiles natively and plays as inklecate's JSON does`() throws {
        let result = try CompilerOracle.compileAndPlay("issue36-seed-random")

        #expect(result.native == ["3", "After the seed.", "Keep going", "The choice played."])
        #expect(result.native == result.oracle)
    }

    @Test(arguments: [
        ("Before.\n~ k()\n" + continuation, 2),
        ("Before.\nValue: {k()}.\n" + continuation, 2),
    ])
    func `calling a knot as a function is rejected with inklecate's message`(source: String, line: Int) {
        let error = #expect(throws: CompileError.self) {
            _ = try InkCompiler.compile(source: source)
        }
        #expect(error?.message == "k hasn't been marked as a function, but it's being called as one. Do you need to delcare the knot as '== function k =='?")
        #expect(error?.line == line)
    }
}
