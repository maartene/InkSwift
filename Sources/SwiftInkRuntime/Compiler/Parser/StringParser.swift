// Stateful cursor + combinator primitives for the native compile pipeline
// (DDD-5, the C# `StringParser` analog — hand-rolled, no new dependency). Tracks
// 1-based line/column as it consumes source and exposes the combinators the
// statement rules build on (peek, advance, match, optional, repeatWhile).

import Foundation

/// A hand-rolled stateful cursor over `.ink` source. Position is 1-based: a
/// fresh cursor sits at line 1, column 1. Advancing past a newline bumps the
/// line and resets the column.
public struct StringParser {

    private let characters: [Character]
    private var offset: Int
    public private(set) var line: Int
    public private(set) var column: Int

    public init(_ source: String) {
        self.characters = Array(source)
        self.offset = 0
        self.line = 1
        self.column = 1
    }

    /// True once every character has been consumed.
    public var isAtEnd: Bool {
        offset >= characters.count
    }

    /// The character under the cursor without consuming it (`nil` at end).
    public func peek() -> Character? {
        guard offset < characters.count else {
            return nil
        }
        return characters[offset]
    }

    /// Consume and return the character under the cursor, updating line/column.
    public mutating func advance() -> Character? {
        guard offset < characters.count else {
            return nil
        }
        let character = characters[offset]
        offset += 1
        moveAfter(character)
        return character
    }

    /// Consume `literal` and report success only when the cursor matches it in
    /// full; on mismatch the cursor is left exactly where it started.
    public mutating func match(_ literal: String) -> Bool {
        let expected = Array(literal)
        guard offset + expected.count <= characters.count else {
            return false
        }
        for index in 0..<expected.count where characters[offset + index] != expected[index] {
            return false
        }
        for _ in 0..<expected.count {
            _ = advance()
        }
        return true
    }

    /// Consume `literal` when present; otherwise do nothing.
    public mutating func optional(_ literal: String) {
        _ = match(literal)
    }

    /// Consume the maximal run of characters satisfying `predicate`, returning it.
    public mutating func repeatWhile(_ predicate: (Character) -> Bool) -> String {
        var consumed = ""
        while let next = peek(), predicate(next) {
            consumed.append(next)
            _ = advance()
        }
        return consumed
    }

    private mutating func moveAfter(_ character: Character) {
        if character == "\n" {
            line += 1
            column = 1
            return
        }
        column += 1
    }

    /// Back-compat helper consumed by `InkCompiler` since S0: split sanitized
    /// source into plain-text lines. Retained while codegen migrates to the AST.
    static func parseLines(_ source: String) -> [String] {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return []
        }
        return trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
