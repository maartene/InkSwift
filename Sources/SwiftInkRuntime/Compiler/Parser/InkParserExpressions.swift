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

    /// Binding power of the additive group — the lowest precedence handled here.
    private static let additivePrecedence = 1
    /// Binding power of the multiplicative group — binds tighter than additive.
    private static let multiplicativePrecedence = 2

    /// Parse a single arithmetic expression from `source`.
    public static func parse(_ source: String) throws -> InkExpression {
        var tokens = ExpressionTokenizer(source)
        let expression = try parseExpression(minimumPrecedence: additivePrecedence, from: &tokens)
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
        return try operand(from: token)
    }

    private static func operand(from token: ExpressionToken) throws -> InkExpression {
        if token.isStringLiteral {
            return .stringLiteral(token.text)
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
        case "+", "-": return additivePrecedence
        case "*", "/", "%": return multiplicativePrecedence
        default: return nil
        }
    }

    private static func isIdentifier(_ text: String) -> Bool {
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
            contents.append(characters[index])
            index += 1
        }
        let endIndex = index < characters.count ? index + 1 : index
        return (ExpressionToken(text: contents, isStringLiteral: true), endIndex)
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

    private func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "." || character == "_"
    }
}
