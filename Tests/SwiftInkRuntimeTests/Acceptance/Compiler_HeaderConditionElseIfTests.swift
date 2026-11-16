// @regression @error @kpi-2
//
// A block conditional whose condition sits in the HEADER (`{ cond:` followed by
// content) has exactly one implicit true arm and AT MOST ONE `- else:` arm. An
// else-if chain in that form is a syntax error — the reference rejects it, and
// so must we (issue #19).
//
// Ground truth (inklecate 1.2.1, `InkParser_Conditional.cs` — the
// `initialQueryExpression` + `soleContent` path): after the header-guarded
// content the parser accepts one `SingleMultilineCondition`, and if that branch
// is not `- else:` it reports "Expected an '- else:' clause here rather than an
// extra condition". A second `- else:` is never consumed at all, so the block
// fails to close ("Expected closing brace '}'").
//
// Defect this pins: `InkParser.switchOrGuardedBlock` turned the header into the
// first arm's guard and then accepted any number of `- guard:` arms, silently
// compiling stories inklecate rejects. A story written against InkSwift could
// quietly become non-portable — the oracle cannot catch an over-acceptance,
// because no oracle JSON exists for a source inklecate refuses.
//
// The portable spellings of the same logic — a headerless `{` block whose every
// condition is an arm, and the header form with a single `- else:` — must keep
// compiling and playing like the oracle. Their fixture continues past each block
// (prose, then a choice) so a rejoin regression would also show.

import Testing
import Foundation
@testable import SwiftInkRuntime

// name → (source, 1-based line of the offending arm)
private let rejectedShapes: [(name: String, source: String, line: Int)] = [
    ("else-if chain after a header condition", """
        VAR x = 2
        { x == 1:
            One.
        - x == 2:
            Two.
        - else:
            Other.
        }
        After the block.
        -> END
        """, 4),
    ("extra condition with no else", """
        VAR x = 2
        { x == 1:
            One.
        - x == 2:
            Two.
        }
        After the block.
        -> END
        """, 4),
    ("second else after a header condition", """
        VAR x = 2
        { x == 1:
            One.
        - else:
            Two.
        - else:
            Three.
        }
        After the block.
        -> END
        """, 6),
    ("else-if chain nested in an arm", """
        VAR x = 2
        { true:
            { x == 1:
                One.
            - x == 2:
                Two.
            }
        }
        After the block.
        -> END
        """, 5),
]

@Suite("Compiler — a header-condition block allows only a single else arm")
struct Compiler_HeaderConditionElseIfTests {

    @Test(arguments: rejectedShapes)
    func `a header-condition block with more than one else arm is a located syntax error`(
        name: String,
        source: String,
        line: Int
    ) throws {
        do {
            _ = try InkCompiler.compile(source: source)
            Issue.record("\(name): inklecate rejects this but it compiled to a story (SILENT ACCEPTANCE)")
        } catch let error as CompileError {
            #expect(error.kind == .syntaxError, "\(name): expected .syntaxError, got \(error.kind)")
            #expect(error.line == line, "\(name): expected the error on line \(line), got \(error.line)")
        }
    }

    @Test
    func `the reference error message names the expected else clause`() throws {
        let error = #expect(throws: CompileError.self) {
            try InkCompiler.compile(source: rejectedShapes[0].source)
        }

        #expect(error?.message.contains("Expected an '- else:' clause here rather than an extra condition") == true)
    }

    // Scenario: the portable spellings inklecate accepts still compile and play
    // line-for-line and choice-for-choice like the oracle.
    @Test
    func `the headerless chain and the single-else header form play identically to the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-else-if-chain-forms", choiceScript: [0])

        #expect(result.oracle == [
            "Before the chain.", "Two.", "After the chain.",
            "Before the if-else.", "Not one.", "After the if-else.",
        ])
        #expect(result.native == result.oracle)
    }
}
