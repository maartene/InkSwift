// Tests for InkJSONReader — the hand-written JSON reader behind InkDecoder
// (ADR-023, issue #37 part 1).
//
// A number is a float if and only if its token contains `.`, `e` or `E`, as in
// the reference reader (ink-engine-runtime/SimpleJson.cs ReadNumber). Strings
// and structure follow RFC 8259. These tests pin JSON syntax, not stories, so
// they use inline JSON literals.

import Testing
@testable import SwiftInkRuntime

@Suite struct InkJSONReaderTests {

    private func read(_ json: String) throws -> InkJSONValue {
        try InkJSONReader.read(Array(json.utf8))
    }

    // Scenario: whole-number floats in inklecate JSON stay floats.
    @Test(arguments: [
        ("42", InkJSONValue.int(42)),
        ("-3", .int(-3)),
        ("0", .int(0)),
        ("2.0", .double(2.0)),
        ("2.5", .double(2.5)),
        ("1e2", .double(100)),
        ("1E2", .double(100)),
        ("-0.5", .double(-0.5)),
        ("1.5e-3", .double(0.0015)),
        ("true", .bool(true)),
        ("false", .bool(false)),
        ("null", .null),
    ])
    func `a scalar is typed by its token text`(json: String, expected: InkJSONValue) throws {
        #expect(try read(json) == expected)
    }

    @Test(arguments: [
        (#""plain""#, "plain"),
        (#""say \"hi\"""#, "say \"hi\""),
        (#""back\\slash""#, "back\\slash"),
        (#""line\nbreak""#, "line\nbreak"),
        (#""\t\r\b\f\/""#, "\t\r\u{08}\u{0C}/"),
        (#""caf\u00e9""#, "caf\u{e9}"),
        (#""café""#, "café"),
        (#""\ud83d\ude00""#, "\u{1F600}"),
        (#""😀""#, "😀"),
    ])
    func `a string decodes its escapes per RFC 8259`(json: String, expected: String) throws {
        #expect(try read(json) == .string(expected))
    }

    @Test func `nested arrays and objects keep their content and array order`() throws {
        let json = ##" { "root" : [ 3, [ "^a", 2.0 , {"#f":5} ], null ], "x":{} , "e":[] } "##

        #expect(try read(json) == .object([
            "root": .array([.int(3), .array([.string("^a"), .double(2.0), .object(["#f": .int(5)])]), .null]),
            "x": .object([:]),
            "e": .array([]),
        ]))
    }

    @Test(arguments: [
        #"{"root":[1,2"#,
        #"{"root":"unterminated"#,
        #"nonsense"#,
        #"{"a":1} trailing"#,
        #"[1,]"#,
        #"{"a" 1}"#,
        #"tru"#,
        #"-"#,
        #""bad \x escape""#,
        "",
    ])
    func `malformed input throws malformedJSON`(json: String) {
        #expect(throws: InkDecodeError.malformedJSON) { try read(json) }
    }
}
