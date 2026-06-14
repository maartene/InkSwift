import Testing
@testable import SwiftInkRuntime

@Suite("StringParser — stateful cursor")
struct StringParserTests {

    @Test func `starts at line one column one`() {
        let parser = StringParser("abc")
        #expect(parser.line == 1)
        #expect(parser.column == 1)
    }

    @Test func `peek does not advance the cursor`() {
        let parser = StringParser("ab")
        let first = parser.peek()
        let second = parser.peek()
        #expect(first == "a")
        #expect(second == "a")
        #expect(parser.column == 1)
    }

    @Test func `advance consumes a character and moves the column`() {
        var parser = StringParser("ab")
        let first = parser.advance()
        #expect(first == "a")
        #expect(parser.column == 2)
        let second = parser.advance()
        #expect(second == "b")
        #expect(parser.isAtEnd)
    }

    @Test func `advancing past a newline increments line and resets column`() {
        var parser = StringParser("a\nb")
        _ = parser.advance() // a
        _ = parser.advance() // newline
        #expect(parser.line == 2)
        #expect(parser.column == 1)
        #expect(parser.peek() == "b")
    }

    @Test func `match consumes an expected literal and reports success`() {
        var parser = StringParser("-> END")
        let matched = parser.match("->")
        #expect(matched)
        #expect(parser.column == 3)
    }

    @Test func `match leaves the cursor untouched on mismatch`() {
        var parser = StringParser("hello")
        let matched = parser.match("xyz")
        #expect(matched == false)
        #expect(parser.column == 1)
    }

    @Test func `optional consumes a literal when present and ignores it when absent`() {
        var present = StringParser("===abc")
        present.optional("===")
        #expect(present.column == 4)

        var absent = StringParser("abc")
        absent.optional("===")
        #expect(absent.column == 1)
    }

    @Test func `repeatWhile consumes the run satisfying the predicate`() {
        var parser = StringParser("   tail")
        let spaces = parser.repeatWhile { $0 == " " }
        #expect(spaces == "   ")
        #expect(parser.peek() == "t")
    }
}
