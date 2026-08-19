// Regression for CommentEliminator.strip() toggling `insideString` on every raw
// ASCII `"` in the source, with no awareness of Ink grammar context and no reset
// at line boundaries. A single unmatched `"` used as ordinary punctuation in
// content text (never a real Ink string literal — those are single-line only,
// verified against inklecate 1.2.1: an unterminated string literal is a
// compile error, "Expected close quote for string expression but saw end of
// line") leaves `insideString` stuck `true` for the rest of the source. Any
// `//` comment encountered while stuck survives verbatim instead of being
// stripped — and if that comment happens to contain divert-like text (as ours
// did, illustrating `-> END` in backticks), later compiler stages can read it
// as a real divert and skip content.
//
// Found while writing narrative content whose dialogue convention pairs an
// opening German „ quotation mark (U+201E, not ASCII, invisible to the
// toggle) with a closing plain ASCII `"` — every line of dialogue contributes
// exactly one raw `"`, an odd count that flips the parser's internal state for
// an unbounded stretch of subsequent source.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — CommentEliminator quote-state (comment after an unbalanced quote)")
struct Compiler_CommentEliminatorQuoteStateTests {

    @Test func `a comment after a lone unmatched quote is still stripped, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-comment-after-unbalanced-quote")

        #expect(result.native == result.oracle)
        #expect(result.oracle == [
            "He said \"hello and turned away.",
            "Reached the second knot."
        ])
    }

    @Test func `insideString resets at a newline, not just on a matching quote`() {
        // Direct lexer-level regression, isolated from the parser/engine: a
        // line comment on the SECOND line must still be stripped even though
        // the FIRST line ends with an odd number of raw quotes.
        let source = "He said \"hello and turned away.\n// gone\nStill here."
        let result = CommentEliminator.strip(source)
        #expect(result == "He said \"hello and turned away.\n\nStill here.")
    }

    @Test func `a divert-like sequence written inside such a leaked comment is never executed`() throws {
        // The dangerous variant: without the fix, the comment's content
        // (including the literal text `-> next`, unrelated to the backtick
        // example in the doc comment above) would either print as visible
        // text or — worse — be read as a real divert, depending on exactly
        // what the leaked text contains. Either way the real `-> next` divert
        // two lines later must be the one that actually fires.
        let result = try CompilerOracle.compileAndPlay("compile-comment-after-unbalanced-quote")

        #expect(result.native.contains("Reached the second knot."))
    }
}
