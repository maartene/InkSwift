// Pratt precedence-climbing sub-parser for Ink arithmetic expressions (DDD-5).
// It is a hand-rolled, dependency-free token-level pass (DDD-5: no new
// dependency) producing the typed `InkExpression` AST. Multiplicative operators
// (`*` `/` `%`) bind tighter than additive ones (`+` `-`); both groups are
// left-associative. Operands are int/float/string literals, variable references,
// and parenthesis-free binary combinations of those.
//
// This is a SEPARATE sub-parser from `InkParser` by DESIGN:
//   WHY-NEW-FILE: Compiler/Parser/InkParserExpressions.swift
//     CLOSEST-EXISTING: Compiler/Parser/InkParser.swift
//     EXTENSION-COST: InkParser is a line-oriented statement pass; folding a
//       character/token-level Pratt parser into it mixes two parsing
//       granularities (whole lines vs in-expression tokens) in one type.
//     PARALLEL-RATIONALE: DDD-5 names the Pratt sub-parser as an explicitly
//       separate component with an incompatible interface (in-expression token
//       stream, not source lines); StringParser/TagParser already establish the
//       one-sub-parser-per-file boundary in this directory.

import Foundation

/// Errors surfaced while parsing an inline expression.
public enum InkExpressionParseError: Error, Equatable {
    case unexpectedEndOfInput
    case unexpectedToken(String)
}

/// Parses Ink arithmetic expressions into the typed `InkExpression` AST using
/// precedence climbing.
public enum InkExpressionParser {

    /// Binding power of the logical-or group (`||`) — the lowest precedence
    /// handled here (binds looser than everything else, matching Ink/C order).
    private static let logicalOrPrecedence = 1
    /// Binding power of the logical-and group (`&&`) — binds tighter than `||`
    /// but looser than comparison.
    private static let logicalAndPrecedence = 2
    /// Binding power of the comparison group (`> < >= <= == !=`) — binds tighter
    /// than the logical operators but looser than arithmetic.
    private static let comparisonPrecedence = 3
    /// Binding power of the additive group.
    private static let additivePrecedence = 4
    /// Binding power of the multiplicative group — binds tighter than additive.
    private static let multiplicativePrecedence = 5

    /// Parse a single arithmetic/comparison expression from `source`.
    public static func parse(_ source: String) throws -> InkExpression {
        var tokens = ExpressionTokenizer(source)
        let expression = try parseExpression(minimumPrecedence: logicalOrPrecedence, from: &tokens)
        if let leftover = tokens.peek() {
            throw InkExpressionParseError.unexpectedToken(leftover.text)
        }
        return expression
    }

    // MARK: - Precedence climbing

    private static func parseExpression(
        minimumPrecedence: Int,
        from tokens: inout ExpressionTokenizer
    ) throws -> InkExpression {
        var left = try parseOperand(from: &tokens)
        while let precedence = bindingPower(of: tokens.peek()), precedence >= minimumPrecedence {
            let oper = tokens.next()!.text
            let right = try parseExpression(minimumPrecedence: precedence + 1, from: &tokens)
            left = .binary(op: oper, left: left, right: right)
        }
        return left
    }

    private static func parseOperand(from tokens: inout ExpressionTokenizer) throws -> InkExpression {
        guard let token = tokens.next() else {
            throw InkExpressionParseError.unexpectedEndOfInput
        }
        // `not <operand>` is the logical-not unary prefix; it lowers to the
        // runtime native function `!` (postfix). Recurse so `not not x` and
        // `not (a == b)` lower correctly. The operand is itself a full operand
        // (covering parenthesised expressions and nested prefixes).
        if token.text == notKeyword {
            return .unary(op: notNativeSymbol, operand: try parseOperand(from: &tokens))
        }
        // A bare `(` opens a parenthesised sub-expression (grouping) — parse a
        // full expression up to the matching `)`. Needed so `not (a == b)` binds
        // the whole comparison under the prefix `!`.
        if token.text == "(" {
            let grouped = try parseExpression(minimumPrecedence: logicalOrPrecedence, from: &tokens)
            guard let closing = tokens.next(), closing.text == ")" else {
                throw InkExpressionParseError.unexpectedToken(")")
            }
            return grouped
        }
        // An identifier directly followed by `(` is a function call `f(args)`;
        // its arguments are themselves expressions parsed up to the matching `)`.
        if isIdentifier(token.text), let next = tokens.peek(), next.text == "(" {
            return try parseFunctionCall(name: token.text, from: &tokens)
        }
        return try operand(from: token)
    }

    /// The source keyword for logical not, and the runtime native-function symbol
    /// it lowers to (matching inklecate's postfix `!`).
    private static let notKeyword = "not"
    private static let notNativeSymbol = "!"

    /// Parse a function-call operand `f(arg, …)` — the opening `(` is the next
    /// token. Arguments are comma-separated expressions; a bare `f()` has none.
    private static func parseFunctionCall(
        name: String,
        from tokens: inout ExpressionTokenizer
    ) throws -> InkExpression {
        _ = tokens.next() // consume "("
        var arguments: [InkExpression] = []
        if tokens.peek()?.text == ")" {
            _ = tokens.next()
            return .functionCall(name: name, arguments: arguments)
        }
        while true {
            arguments.append(try parseExpression(minimumPrecedence: logicalOrPrecedence, from: &tokens))
            guard let separator = tokens.next() else {
                throw InkExpressionParseError.unexpectedEndOfInput
            }
            if separator.text == ")" { break }
            guard separator.text == "," else {
                throw InkExpressionParseError.unexpectedToken(separator.text)
            }
        }
        return .functionCall(name: name, arguments: arguments)
    }

    private static func operand(from token: ExpressionToken) throws -> InkExpression {
        if token.isStringLiteral {
            return .stringLiteral(token.text)
        }
        if token.text == "true" {
            return .boolLiteral(true)
        }
        if token.text == "false" {
            return .boolLiteral(false)
        }
        if let intValue = Int(token.text) {
            return .intLiteral(intValue)
        }
        if let floatValue = Double(token.text) {
            return .floatLiteral(floatValue)
        }
        if isIdentifier(token.text) {
            return .variableReference(token.text)
        }
        throw InkExpressionParseError.unexpectedToken(token.text)
    }

    /// Left binding power for an operator token; nil for non-operators.
    private static func bindingPower(of token: ExpressionToken?) -> Int? {
        switch token?.text {
        case "||": return logicalOrPrecedence
        case "&&": return logicalAndPrecedence
        case ">", "<", ">=", "<=", "==", "!=": return comparisonPrecedence
        case "+", "-": return additivePrecedence
        case "*", "/", "%": return multiplicativePrecedence
        default: return nil
        }
    }

    /// True for a bare identifier OR a dotted qualified identifier (`a.b`,
    /// `knot.stitch`). Each dot-separated segment must itself be a plain
    /// identifier (leading letter/underscore, then letters/digits/underscores), so
    /// a leading/trailing/double dot is rejected. A dotted name lowers to a
    /// `.variableReference` atom; the emitter later resolves it to a read-count
    /// when it names a known weave label or knot/stitch (ADR-011 EXTEND #1).
    private static func isIdentifier(_ text: String) -> Bool {
        let segments = text.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 1 else { return false }
        return segments.allSatisfy(isPlainIdentifierSegment)
    }

    private static func isPlainIdentifierSegment<S: StringProtocol>(_ text: S) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" else {
            return false
        }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

/// One lexed expression token (a number, identifier, operator symbol, or a
/// string literal — `isStringLiteral` distinguishes the last from an identifier
/// so an unquoted bareword like `Ada` is not mistaken for the string `"Ada"`).
private struct ExpressionToken {
    let text: String
    let isStringLiteral: Bool

    init(text: String, isStringLiteral: Bool = false) {
        self.text = text
        self.isStringLiteral = isStringLiteral
    }
}

/// A minimal forward-only tokenizer over an expression string. Splits on
/// whitespace and single-character operators, keeping numbers and identifiers
/// whole.
private struct ExpressionTokenizer {
    private let characters: [Character]
    private var position = 0

    init(_ source: String) {
        self.characters = Array(source)
    }

    mutating func next() -> ExpressionToken? {
        guard let scanned = scanTokenFromCurrentPosition() else {
            return nil
        }
        position = scanned.endIndex
        return scanned.token
    }

    func peek() -> ExpressionToken? {
        scanTokenFromCurrentPosition()?.token
    }

    /// Scan the next token without mutating state, returning it together with
    /// the index just past it. Shared by `peek` (discards `endIndex`) and
    /// `next` (advances `position` to `endIndex`).
    private func scanTokenFromCurrentPosition() -> (token: ExpressionToken, endIndex: Int)? {
        var index = skippingWhitespace(from: position)
        guard index < characters.count else {
            return nil
        }
        if characters[index] == "\"" {
            return scanStringLiteral(from: index)
        }
        if let comparison = scanComparisonOperator(from: index) {
            return comparison
        }
        if let logical = scanLogicalOperator(from: index) {
            return logical
        }
        if isPunctuation(characters[index]) {
            return (ExpressionToken(text: String(characters[index])), index + 1)
        }
        if isOperator(characters[index]) {
            return (ExpressionToken(text: String(characters[index])), index + 1)
        }
        var word = ""
        while index < characters.count, isWordCharacter(characters[index]) {
            word.append(characters[index])
            index += 1
        }
        return word.isEmpty ? nil : (ExpressionToken(text: word), index)
    }

    /// Scan a double-quoted string literal beginning at the opening quote at
    /// `start`. Returns the unquoted contents and the index just past the
    /// closing quote.
    private func scanStringLiteral(from start: Int) -> (token: ExpressionToken, endIndex: Int) {
        var index = start + 1
        var contents = ""
        while index < characters.count, characters[index] != "\"" {
            if characters[index] == "\\", index + 1 < characters.count {
                // A backslash escapes the next character (an escaped quote or
                // escaped backslash): copy the pair verbatim so the escaped
                // quote does not terminate the literal early.
                contents.append(characters[index])
                contents.append(characters[index + 1])
                index += 2
                continue
            }
            contents.append(characters[index])
            index += 1
        }
        let endIndex = index < characters.count ? index + 1 : index
        return (ExpressionToken(text: contents, isStringLiteral: true), endIndex)
    }

    /// Scan a comparison operator (`>= <= == != > <`) beginning at `index`.
    /// Two-character forms are recognised before their single-character prefixes
    /// so `>=` is one token rather than `>` followed by `=`. Returns `nil` when
    /// the character at `index` is not a comparison operator.
    private func scanComparisonOperator(from index: Int) -> (token: ExpressionToken, endIndex: Int)? {
        let character = characters[index]
        guard "><=!".contains(character) else { return nil }
        if index + 1 < characters.count, characters[index + 1] == "=" {
            let symbol = String(character) + "="
            return (ExpressionToken(text: symbol), index + 2)
        }
        guard character == ">" || character == "<" else { return nil }
        return (ExpressionToken(text: String(character)), index + 1)
    }

    /// Scan a logical operator (`&&` / `||`) beginning at `index`. The doubled
    /// forms are recognised as a single two-character token. A LONE `&` or `|`
    /// is not a valid Ink operator: it is emitted as a single-character token so
    /// the parser raises `unexpectedToken` for it, rather than the character
    /// being silently dropped (which previously truncated the whole expression).
    /// Returns `nil` when the character at `index` is neither `&` nor `|`.
    private func scanLogicalOperator(from index: Int) -> (token: ExpressionToken, endIndex: Int)? {
        let character = characters[index]
        guard character == "&" || character == "|" else { return nil }
        if index + 1 < characters.count, characters[index + 1] == character {
            let symbol = String(character) + String(character)
            return (ExpressionToken(text: symbol), index + 2)
        }
        return (ExpressionToken(text: String(character)), index + 1)
    }

    private func skippingWhitespace(from start: Int) -> Int {
        var index = start
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
        return index
    }

    private func isOperator(_ character: Character) -> Bool {
        "+-*/%".contains(character)
    }

    /// Call-syntax punctuation tokens — kept whole so the expression parser can
    /// recognise `f(`, argument separators, and the closing `)`.
    private func isPunctuation(_ character: Character) -> Bool {
        "(),".contains(character)
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "." || character == "_"
    }
}
