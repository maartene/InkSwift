// @regression @real-io @kpi-1
//
// Inside a multi-line block conditional, EVERY `-` line (other than a `->`
// divert) opens a branch, and the branch's `<expr>:` guard is optional. A branch
// without one is "unconditioned": under a header with no labelled arm the block
// is binary (first branch true, second the else); as the final branch it is the
// else. Text that does not parse as an expression followed by `:` is content,
// its colon included (issue #23).
//
// Ground truth (inklecate 1.2.1, `InkParser_Conditional.cs`):
// `SingleMultilineCondition` parses `-`, then `ElseExpression` or an optional
// `ConditionExpression`, then the branch content. The `initialQueryExpression`
// loop makes expression-less branches binary, and rejects more than two of them
// ("Only final branch can be an 'else'"); the headerless loop rejects any
// expression-less branch that is not last ("Branch doesn't have condition").
// `StatementsAtLevel(InnerBlock)` has no gather rule and rejects gather dashes.
//
// Defect this pins: `InkParser.armParts` only recognised a `-` line as a branch
// when it had a top-level colon. `{ x == 2: - yes - no }` therefore had no arms
// and both lines played as content of the header-guarded block; `- : B` read
// the empty text as a default-arm guard and dropped the `:`.
//
// Correctness gate: hermetic Level-1 execution-equivalence — native compile vs
// the committed inklecate `.ink.json` oracle. Every block in the fixture is
// followed by prose, and the first knot ends in a choice, so an arm that failed
// to rejoin would also show.

import Testing
import Foundation
@testable import SwiftInkRuntime

// name → (source, 1-based line inklecate reports, message fragment)
private let rejectedShapes: [(name: String, source: String, line: Int, message: String)] = [
    ("three colon-less branches under a header", """
        VAR x = 2
        { x == 2:
        - A
        - B
        - C
        }
        After.
        -> END
        """, 3, "Only final branch can be an 'else'. Did you miss a ':'?"),
    ("a colon-less branch before a guarded one in a headerless block", """
        VAR x = 2
        {
        - A
        - x == 2: B
        }
        After.
        -> END
        """, 3, "Branch doesn't have condition. Are you missing a ':'?"),
    ("gather dashes inside a block", """
        VAR x = 2
        { x == 2:
        - A
        - - B
        }
        After.
        -> END
        """, 4, "You can't use a gather (the dashes) within the { curly braces } context."),
]

@Suite("Compiler — a colon-less `-` line in a block is a branch")
struct Compiler_ColonLessArmsTests {

    @Test
    func `colon-less branches play identically to the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-colon-less-arms", choiceScript: [0])

        #expect(result.native == result.oracle)
    }

    // Scenario: the issue #23 shape. Two colon-less branches under a header are
    // true/else, so exactly one plays, whichever way the header goes.
    @Test
    func `two colon-less branches under a header play only the branch the header selects`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-colon-less-arms", choiceScript: [0])

        #expect(result.oracle.prefix(5) == [
            "Binary true arm.", "After the true binary.",
            "Taken false arm.", "After the false binary.",
            "After the lone arm.",
        ])
        #expect(result.native.prefix(5) == result.oracle.prefix(5))
    }

    // Scenario: a colon that does not follow an expression is content, as is the
    // colon of an empty guard (`- : B` prints `: B`).
    @Test
    func `a colon not preceded by an expression stays in the branch content`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-colon-less-arms", choiceScript: [0])

        #expect(result.native.contains("Two words: the colon stays in the true arm."))
        #expect(result.native.contains(": Empty guard is content."))
    }

    @Test(arguments: rejectedShapes)
    func `a block branch shape inklecate rejects is a located syntax error`(
        name: String,
        source: String,
        line: Int,
        message: String
    ) throws {
        do {
            _ = try InkCompiler.compile(source: source)
            Issue.record("\(name): inklecate rejects this but it compiled to a story (SILENT ACCEPTANCE)")
        } catch let error as CompileError {
            #expect(error.kind == .syntaxError, "\(name): expected .syntaxError, got \(error.kind)")
            #expect(error.line == line, "\(name): expected the error on line \(line), got \(error.line)")
            #expect(error.message.contains(message), "\(name): unexpected message \(error.message)")
        }
    }
}
