import Testing
@testable import SwiftInkRuntime

// Line extraction from the typed output stream (ADR-020 §2): one pure function
// splits the stream at its first newline into the line's text, the line's tags
// and the remainder.
@Suite("OutputLine extraction")
struct OutputLineExtractionTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let stream: [OutputItem]
        let text: String
        let tags: [String]
        let remainder: [OutputItem]
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "a tag before the first newline belongs to the line",
            stream: [.text("Hello"), .tag("greeting"), .newline, .text("Next")],
            text: "Hello", tags: ["greeting"], remainder: [.text("Next")]
        ),
        Case(
            name: "a tag after the first newline stays in the remainder",
            stream: [.text("Hello"), .newline, .tag("next"), .text("World"), .newline],
            text: "Hello", tags: [], remainder: [.tag("next"), .text("World"), .newline]
        ),
        Case(
            name: "several tags keep their order",
            stream: [.tag("first"), .text("Line"), .tag("second"), .tag("third"), .newline],
            text: "Line", tags: ["first", "second", "third"], remainder: []
        ),
        Case(
            name: "glue next to a tag removes the newline but not the tag",
            stream: [.text("Joined "), .tag("kept"), .text("together"), .newline],
            text: "Joined together", tags: ["kept"], remainder: []
        ),
        Case(
            name: "an empty stream yields an empty line",
            stream: [],
            text: "", tags: [], remainder: []
        ),
    ]

    @Test(arguments: cases)
    func `extracting a line splits text, tags and remainder at the first newline`(example: Case) {
        let line = OutputLine(splitting: example.stream)
        #expect(line.text == example.text)
        #expect(line.tags == example.tags)
        #expect(line.remainder == example.remainder)
    }
}
