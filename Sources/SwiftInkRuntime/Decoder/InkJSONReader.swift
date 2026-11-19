/// Reads ink JSON bytes into an `InkJSONValue` (ADR-023).
///
/// A number is a float if and only if its token contains `.`, `e` or `E`, as
/// in the reference reader (`SimpleJson.cs` `ReadNumber`). inklecate writes
/// float literals as `1.0`, `2.0`, so the token text, not the value, must
/// decide: `JSONDecoder` typed `2.0` as `Int` 2 and turned `1.0 / 3` into
/// integer division (issue #37). Strings and structure follow RFC 8259.
///
/// Pure Swift over `[UInt8]`: no Foundation JSON, `NSNumber` or CoreFoundation,
/// so typing is identical on every platform (ADR-013's goal). Malformed input
/// throws `InkDecodeError.malformedJSON`.
struct InkJSONReader {
    private let bytes: [UInt8]
    private var offset = 0

    private init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    static func read(_ bytes: [UInt8]) throws -> InkJSONValue {
        var reader = InkJSONReader(bytes)
        let value = try reader.readValue()
        reader.skipWhitespace()
        guard reader.offset == bytes.count else { throw InkDecodeError.malformedJSON }
        return value
    }

    // MARK: - Values

    private mutating func readValue() throws -> InkJSONValue {
        skipWhitespace()
        switch peek() {
        case Byte.openBrace: return .object(try readObject())
        case Byte.openBracket: return .array(try readArray())
        case Byte.quote: return .string(try readString())
        case Byte.t: return try readLiteral("true", as: .bool(true))
        case Byte.f: return try readLiteral("false", as: .bool(false))
        case Byte.n: return try readLiteral("null", as: .null)
        default: return try readNumber()
        }
    }

    private mutating func readLiteral(_ word: String, as value: InkJSONValue) throws -> InkJSONValue {
        for byte in word.utf8 {
            try expect(byte)
        }
        return value
    }

    private mutating func readArray() throws -> [InkJSONValue] {
        try expect(Byte.openBracket)
        var items: [InkJSONValue] = []
        if consumeIfNext(Byte.closeBracket) { return items }
        repeat {
            items.append(try readValue())
        } while try continuesAfterItem(closedBy: Byte.closeBracket)
        return items
    }

    private mutating func readObject() throws -> [String: InkJSONValue] {
        try expect(Byte.openBrace)
        var object: [String: InkJSONValue] = [:]
        if consumeIfNext(Byte.closeBrace) { return object }
        repeat {
            skipWhitespace()
            let key = try readString()
            skipWhitespace()
            try expect(Byte.colon)
            object[key] = try readValue()
        } while try continuesAfterItem(closedBy: Byte.closeBrace)
        return object
    }

    /// After an array element or object member: `true` past a `,`, `false`
    /// past the closing bracket, and malformed for anything else.
    private mutating func continuesAfterItem(closedBy closing: UInt8) throws -> Bool {
        if consumeIfNext(Byte.comma) { return true }
        try expect(closing)
        return false
    }

    // MARK: - Numbers

    /// The reference's number rule: the token's text decides float or int.
    private mutating func readNumber() throws -> InkJSONValue {
        let start = offset
        while let byte = peek(), Byte.numberCharacters.contains(byte) {
            offset += 1
        }
        let token = String(decoding: bytes[start..<offset], as: UTF8.self)
        if token.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }) {
            guard let value = Double(token) else { throw InkDecodeError.malformedJSON }
            return .double(value)
        }
        guard let value = Int(token) else { throw InkDecodeError.malformedJSON }
        return .int(value)
    }

    // MARK: - Strings

    private mutating func readString() throws -> String {
        try expect(Byte.quote)
        var utf8: [UInt8] = []
        while let byte = next() {
            switch byte {
            case Byte.quote:
                return String(decoding: utf8, as: UTF8.self)
            case Byte.backslash:
                try readEscape(into: &utf8)
            default:
                utf8.append(byte)
            }
        }
        throw InkDecodeError.malformedJSON
    }

    private static let simpleEscapes: [UInt8: UInt8] = [
        UInt8(ascii: "\""): UInt8(ascii: "\""),
        UInt8(ascii: "\\"): UInt8(ascii: "\\"),
        UInt8(ascii: "/"): UInt8(ascii: "/"),
        UInt8(ascii: "b"): 0x08,
        UInt8(ascii: "f"): 0x0C,
        UInt8(ascii: "n"): UInt8(ascii: "\n"),
        UInt8(ascii: "r"): UInt8(ascii: "\r"),
        UInt8(ascii: "t"): UInt8(ascii: "\t"),
    ]

    private mutating func readEscape(into utf8: inout [UInt8]) throws {
        guard let byte = next() else { throw InkDecodeError.malformedJSON }
        if let unescaped = Self.simpleEscapes[byte] {
            utf8.append(unescaped)
            return
        }
        guard byte == Byte.u else { throw InkDecodeError.malformedJSON }
        utf8.append(contentsOf: String(try readUnicodeEscape()).utf8)
    }

    /// The scalar after `\u`: four hex digits, or a UTF-16 surrogate pair
    /// written as two escapes. A lone surrogate becomes U+FFFD.
    private mutating func readUnicodeEscape() throws -> Character {
        let unit = try readHexQuad()
        guard (0xD800...0xDBFF).contains(unit), lowSurrogateEscapeFollows() else {
            return Character(Unicode.Scalar(unit) ?? Self.replacement)
        }
        offset += 2
        let low = try readHexQuad()
        guard (0xDC00...0xDFFF).contains(low) else { return Character(Self.replacement) }
        let scalar = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
        return Character(Unicode.Scalar(scalar) ?? Self.replacement)
    }

    private static let replacement: Unicode.Scalar = "\u{FFFD}"

    private func lowSurrogateEscapeFollows() -> Bool {
        offset + 1 < bytes.count && bytes[offset] == Byte.backslash && bytes[offset + 1] == Byte.u
    }

    private mutating func readHexQuad() throws -> UInt32 {
        guard offset + 4 <= bytes.count,
              let value = UInt32(String(decoding: bytes[offset..<offset + 4], as: UTF8.self), radix: 16) else {
            throw InkDecodeError.malformedJSON
        }
        offset += 4
        return value
    }

    // MARK: - Cursor

    private func peek() -> UInt8? {
        offset < bytes.count ? bytes[offset] : nil
    }

    private mutating func next() -> UInt8? {
        defer { offset += 1 }
        return peek()
    }

    private mutating func expect(_ byte: UInt8) throws {
        guard peek() == byte else { throw InkDecodeError.malformedJSON }
        offset += 1
    }

    private mutating func consumeIfNext(_ byte: UInt8) -> Bool {
        skipWhitespace()
        guard peek() == byte else { return false }
        offset += 1
        return true
    }

    private mutating func skipWhitespace() {
        while let byte = peek(), Byte.whitespace.contains(byte) {
            offset += 1
        }
    }

    private enum Byte {
        static let openBrace = UInt8(ascii: "{")
        static let closeBrace = UInt8(ascii: "}")
        static let openBracket = UInt8(ascii: "[")
        static let closeBracket = UInt8(ascii: "]")
        static let quote = UInt8(ascii: "\"")
        static let backslash = UInt8(ascii: "\\")
        static let colon = UInt8(ascii: ":")
        static let comma = UInt8(ascii: ",")
        static let t = UInt8(ascii: "t")
        static let f = UInt8(ascii: "f")
        static let n = UInt8(ascii: "n")
        static let u = UInt8(ascii: "u")
        static let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        static let numberCharacters = Set("0123456789-+.eE".utf8)
    }
}
