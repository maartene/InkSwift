// @regression @error @kpi-2
//
// Multi-line block conditionals that inklecate rejects must not compile here
// either (issue #24): an empty `{ :` subject, an `- else:` that is not the
// final branch, more than one `- else:`, and a branch with neither its own
// expression nor any content.
//
// Ground truth (inklecate 1.2.1, `InkParser_Conditional.cs`): the
// `initialQueryExpression` and headerless branch-validation loops after
// `MultilineConditionalBranches`, the "expected content…" check in
// `SingleMultilineCondition`, and `InnerLogic` for the empty subject. Each is a
// deliberate, named error upstream rather than a defect, so we match it.
//
// Defect this pins: the native compiler accepted every one of these, quietly
// letting a story become non-portable. The oracle cannot catch an
// over-acceptance, because no oracle JSON exists for a source inklecate
// refuses. Two shapes from the issue — `- else:` in the middle of a switch and
// a gather-like `-` line between guarded branches — were already rejected once
// `-` lines became branches (#23); they are pinned here too.
//
// The shapes that stay valid — a guarded branch left intentionally blank, and
// an else whose content starts after a blank line — must keep compiling and
// playing like the oracle. Their fixture continues past each block (prose,
// then a choice).

import Testing
import Foundation
@testable import SwiftInkRuntime

// name → (source, 1-based line inklecate reports, message fragment)
private let rejectedShapes: [(name: String, source: String, line: Int, message: String)] = [
    ("an empty subject", """
        VAR x = 2
        { :
        - x == 2: B
        }
        After.
        -> END
        """, 2, "Expected some kind of logic, conditional or sequence within braces: { ... } but saw ':'"),
    ("an else that is not the final branch", """
        VAR x = 2
        {
        - else: A
        - x == 2: B
        }
        After.
        -> END
        """, 3, "'else' case in conditional should always be the final one"),
    ("two else branches", """
        VAR x = 2
        {
        - x == 1: A
        - else: B
        - else: C
        }
        After.
        -> END
        """, 5, "Multiple 'else' cases. Can have a maximum of one, at the end."),
    ("an else in the middle of a switch", """
        VAR x = 2
        { x:
        - 1: One
        - else: Other
        - 2: Two
        }
        After.
        -> END
        """, 4, "Only final branch can be an 'else'. Did you miss a ':'?"),
    ("an else with no content under a header", """
        VAR x = 2
        { x == 2:
        - else:
        }
        After.
        -> END
        """, 3, "expected content for the conditional branch following '-'"),
    ("an else with no content after a binary branch", """
        VAR x = 2
        { x == 2:
        - A
        - else:
        }
        After.
        -> END
        """, 4, "expected content for the conditional branch following '-'"),
    ("an else with no content after header-guarded content", """
        VAR x = 2
        { x == 2:
            A
        - else:
        }
        After.
        -> END
        """, 4, "expected content for the conditional branch following '-'"),
    ("a gather-like line between guarded branches", """
        VAR x = 2
        {
        - x == 2:
            * [Pick] Picked.
        - Gathered.
        - x == 3: C
        }
        After.
        -> END
        """, 5, "Branch doesn't have condition. Are you missing a ':'?"),
]

@Suite("Compiler — block shapes inklecate rejects are located syntax errors")
struct Compiler_RejectedBlockShapesTests {

    @Test(arguments: rejectedShapes)
    func `a block shape inklecate rejects is a located syntax error`(
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

    // Scenario: a guarded branch may be left blank, and an else's content may
    // start after a blank line; both still play line-for-line like the oracle.
    @Test
    func `blank guarded branches and a spaced else play identically to the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-branch-content-forms", choiceScript: [0])

        #expect(result.oracle == [
            "Two.", "After the blank-arm switch.",
            "After the taken blank arm.",
            "Else after a blank line.", "After the spaced else.",
            "After the choice.",
        ])
        #expect(result.native == result.oracle)
    }
}
