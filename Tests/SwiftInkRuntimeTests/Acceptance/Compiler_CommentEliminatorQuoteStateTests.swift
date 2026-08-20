// Execution-equivalence regression for comment elimination around raw quotes in
// content text.
//
// `CommentEliminator.strip()` used to toggle an `insideString` flag on every raw
// ASCII `"`. A single unmatched quote used as ordinary punctuation left the flag
// stuck `true` for the rest of the source, so every later `//` comment survived
// verbatim into the compiled output — and when such a comment contained
// divert-like text, later stages could read it as real Ink syntax and skip
// content. Comment recognition therefore depended on the cumulative quote parity
// of unrelated earlier text, which is why it reproduced only in a large
// multi-chapter story and not in small fixtures.
//
// Reported and diagnosed by @Arandour (issues #14/#15) against a story whose
// dialogue convention pairs an opening German „ (U+201E, invisible to the
// toggle) with a closing ASCII `"`, contributing exactly one raw quote per line
// of dialogue. The fixture and oracle JSON below are theirs.
//
// The reference eliminator tracks no quote state at all — Ink eliminates
// comments before it has any concept of a string literal — so the flag could be
// dropped outright rather than reset at line boundaries. Direct `strip()`
// coverage lives in `CommentEliminatorTests`; this suite pins the end-to-end
// result against the inklecate oracle.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — comment elimination around raw quotes in content text")
struct Compiler_CommentEliminatorQuoteStateTests {

    @Test func `a comment after a lone unmatched quote is still stripped, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-comment-after-unbalanced-quote")

        #expect(result.native == result.oracle)
        // Pins the fixture itself: the comment contributes no output, and the
        // `-> next` divert that fires is the real one on line 8 — not the
        // `-> END` written inside the comment as an example.
        #expect(result.oracle == [
            "He said \"hello and turned away.",
            "Reached the second knot."
        ])
    }
}
