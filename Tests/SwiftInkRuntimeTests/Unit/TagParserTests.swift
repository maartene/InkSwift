import Testing
@testable import SwiftInkRuntime

@Suite("TagParser")
struct TagParserTests {

    // Behavior 1: key-value tag with first-colon separator
    @Test(arguments: [
        ("IMAGE: background.png", "IMAGE", "background.png"),
        ("key: value with colon: inside", "key", "value with colon: inside"),
        ("  key  :  value  ", "key", "value"),
    ])
    func `parses key-value tags — first colon is separator`(raw: String, expectedKey: String, expectedValue: String) {
        let result = TagParser.parse(raw)
        #expect(result.key == expectedKey)
        #expect(result.value == expectedValue)
    }

    // Behavior 2: bare tag returns key with nil value
    @Test func `parses bare tag — no colon yields nil value`() {
        let result = TagParser.parse("NOTE")
        #expect(result.key == "NOTE")
        #expect(result.value == nil)
    }

    // Behavior 3: empty string returns empty key with nil value, no crash
    @Test func `parses empty string — returns empty key with nil value`() {
        let result = TagParser.parse("")
        #expect(result.key == "")
        #expect(result.value == nil)
    }
}
