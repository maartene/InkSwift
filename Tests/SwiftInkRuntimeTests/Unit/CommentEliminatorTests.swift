import Testing
@testable import SwiftInkRuntime

@Suite("CommentEliminator")
struct CommentEliminatorTests {

    @Test func `strips a line comment but keeps the code before it`() {
        let result = CommentEliminator.strip("Hello world // a greeting")
        #expect(result == "Hello world ")
    }

    @Test func `strips a block comment on a single line`() {
        let result = CommentEliminator.strip("before /* middle */ after")
        #expect(result == "before  after")
    }

    @Test func `preserves line numbering across a multi-line block comment`() {
        // A block comment spanning two lines must leave the newline count intact
        // so downstream source positions stay accurate.
        let source = "line one /* open\nstill comment */ tail\nline three"
        let result = CommentEliminator.strip(source)
        let lineCount = result.split(separator: "\n", omittingEmptySubsequences: false).count
        #expect(lineCount == 3)
        #expect(result.split(separator: "\n", omittingEmptySubsequences: false)[2] == "line three")
    }

    @Test func `strips a comment-like sequence even inside double quotes`() {
        // Comment elimination runs before Ink has any concept of a string
        // literal, so quoting confers no protection. inklecate 1.2.1 compiles
        // this source to the single text `say "http:` — matched here.
        let result = CommentEliminator.strip("say \"http://example.com\" now")
        #expect(result == "say \"http:")
    }

    @Test func `strips a comment after an escaped quote, which confers no protection`() {
        // `\"` is not special to this stage — the reference eliminator has no
        // escape handling. inklecate compiles this to `say "a "`, i.e. it strips
        // from `//` and resolves `\"` later in the parser; the stage output here
        // is that same text before escape resolution.
        let source = #"say "a \" // end" now"#
        #expect(CommentEliminator.strip(source) == #"say "a \" "#)
    }

    @Test func `strips a line comment following a trailing escaped backslash`() {
        let source = #"path "C:\\" // drive"#
        #expect(CommentEliminator.strip(source) == #"path "C:\\" "#)
    }

    @Test func `leaves escaped slashes alone because they are not adjacent`() {
        // `\/\/` is how Ink writes a literal `//`; the slashes are separated by
        // backslashes so no comment start exists for this stage to find, and the
        // parser resolves the escapes afterwards. inklecate prints `a // b`.
        let source = #"a \/\/ b"#
        #expect(CommentEliminator.strip(source) == source)
    }

    @Test func `a stray quote in content text does not hide a later comment`() {
        // Regression for the unscoped `insideString` toggle: one unmatched `"`
        // used as ordinary punctuation (e.g. closing a typographic `„`) left the
        // flag stuck for the rest of the source, so every later comment survived
        // verbatim — and comment recognition became a function of the cumulative
        // quote parity of unrelated earlier text.
        let source = "He said \"hello and turned away.\n// gone\nStill here."
        #expect(CommentEliminator.strip(source) == "He said \"hello and turned away.\n\nStill here.")
    }

    @Test func `a stray quote does not hide a comment later on the same line`() {
        // The same-line variant, which a newline-boundary reset cannot reach.
        let source = "He said \"hello. // gone"
        #expect(CommentEliminator.strip(source) == "He said \"hello. ")
    }
}
