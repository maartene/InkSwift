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

    @Test func `leaves comment-like sequences inside string literals intact`() {
        let result = CommentEliminator.strip("say \"http://example.com\" now")
        #expect(result == "say \"http://example.com\" now")
    }
}
