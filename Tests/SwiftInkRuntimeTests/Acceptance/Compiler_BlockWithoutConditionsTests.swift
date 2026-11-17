// @regression @error
//
// A bare `{` block whose body has no `- condition:` arm has no condition to
// test. inklecate 1.2.1 rejects it ("Branch doesn't have condition. Are you
// missing a ':'?" for colon-less `- A` lines; "Condition block with no
// conditions" in `InkParser_Conditional.cs` otherwise), and so do we.
//
// We already rejected it, but only by accident: the empty subject was fed to
// the expression parser, which failed with an unlocated `unexpectedEndOfInput`.
// Typing the block header (`BlockHeader.none`) made the missing condition an
// explicit case, so the rejection is now a located `CompileError`.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — a bare block without conditions is a located syntax error")
struct Compiler_BlockWithoutConditionsTests {

    @Test
    func `a bare block whose lines carry no condition is rejected at the opener`() throws {
        let source = """
            VAR x = 2
            {
            - A
            - B
            }
            After.
            -> END
            """

        let error = #expect(throws: CompileError.self) {
            try InkCompiler.compile(source: source)
        }

        #expect(error?.kind == .syntaxError)
        #expect(error?.line == 2)
    }
}
