// Statement rules for the native Ink compiler (DDD-5): a line-oriented
// recursive-descent pass producing a flat stream of positioned
// `InkStatement`s. S1 constructs: knot/stitch headers, divert forms
// (absolute, qualified, relative), `-> END`, glue, and plain text. S2 adds
// variable declarations (VAR/CONST/`~ temp`), assignment (`~ name = expr`),
// and inline-printed expression interpolation `{ <expr> }` in content lines.
// RHS expressions delegate to the Pratt sub-parser.

import Foundation

/// Turns comment-stripped `.ink` source into the typed AST the codegen consumes.
public enum InkParser {

    private static let knotMarker = "==="
    private static let divertMarker = "->"
    private static let glueMarker = "<>"
    private static let endTarget = "END"
    private static let varMarker = "VAR"
    private static let constMarker = "CONST"
    private static let logicMarker = "~"
    private static let tempMarker = "temp"

    /// Parse `.ink` source into a flat, ordered stream of positioned statements.
    public static func parse(_ source: String) throws -> [InkStatement] {
        var statements: [InkStatement] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)

        for (lineIndex, rawLine) in lines.enumerated() {
            let lineNumber = lineIndex + 1
            try appendStatements(from: String(rawLine), lineNumber: lineNumber, into: &statements)
        }
        return statements
    }

    private static func appendStatements(
        from rawLine: String,
        lineNumber: Int,
        into statements: inout [InkStatement]
    ) throws {
        let column = leadingColumn(of: rawLine)
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else {
            return
        }
        let position = SourcePosition(line: lineNumber, column: column)

        if let kind = headerKind(of: trimmed) {
            statements.append(InkStatement(kind: kind, position: position))
            return
        }
        if let kind = try declarationKind(of: trimmed) {
            statements.append(InkStatement(kind: kind, position: position))
            return
        }
        if trimmed.hasPrefix(divertMarker) {
            statements.append(InkStatement(kind: divertKind(of: trimmed), position: position))
            return
        }
        try appendContent(from: trimmed, position: position, into: &statements)
    }

    /// Recognise a variable/constant/logic statement. `VAR`/`CONST` declare
    /// globals/constants; `~ temp x = e` declares a local; `~ x = e` reassigns.
    /// The right-hand side is parsed by the Pratt expression sub-parser.
    private static func declarationKind(of trimmed: String) throws -> InkStatementKind? {
        if let body = keywordBody(trimmed, keyword: varMarker) {
            let (name, value) = try splitAssignment(body)
            return .globalVariable(name: name, value: value)
        }
        if let body = keywordBody(trimmed, keyword: constMarker) {
            let (name, value) = try splitAssignment(body)
            return .constant(name: name, value: value)
        }
        if trimmed.hasPrefix(logicMarker) {
            return try logicKind(of: String(trimmed.dropFirst(logicMarker.count)))
        }
        return nil
    }

    /// Lower a logic line `~ <body>`: `temp x = e` declares a local, otherwise
    /// `x = e` reassigns an existing variable.
    private static func logicKind(of body: String) throws -> InkStatementKind {
        let trimmedBody = body.trimmingCharacters(in: .whitespaces)
        if let tempBody = keywordBody(trimmedBody, keyword: tempMarker) {
            let (name, value) = try splitAssignment(tempBody)
            return .temporaryVariable(name: name, value: value)
        }
        let (name, value) = try splitAssignment(trimmedBody)
        return .assignment(name: name, value: value)
    }

    /// Return the text after `keyword` when `trimmed` begins with that keyword
    /// followed by whitespace; `nil` otherwise (so `VARIANT` is not seen as `VAR`).
    private static func keywordBody(_ trimmed: String, keyword: String) -> String? {
        guard trimmed.hasPrefix(keyword) else { return nil }
        let remainder = trimmed.dropFirst(keyword.count)
        guard let first = remainder.first, first == " " || first == "\t" else {
            return nil
        }
        return remainder.trimmingCharacters(in: .whitespaces)
    }

    /// Split a `name = expression` body into the name and the parsed expression.
    private static func splitAssignment(_ body: String) throws -> (name: String, value: InkExpression) {
        guard let equalsIndex = body.firstIndex(of: "=") else {
            throw InkExpressionParseError.unexpectedToken(body)
        }
        let name = String(body[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
        let rightHandSide = String(body[body.index(after: equalsIndex)...])
            .trimmingCharacters(in: .whitespaces)
        let value = try InkExpressionParser.parse(rightHandSide)
        return (name, value)
    }

    private static func headerKind(of trimmed: String) -> InkStatementKind? {
        if trimmed.hasPrefix(knotMarker) {
            return .knot(stripped(trimmed, of: "="))
        }
        if trimmed.hasPrefix("=") {
            return .stitch(stripped(trimmed, of: "="))
        }
        return nil
    }

    private static func divertKind(of trimmed: String) -> InkStatementKind {
        let target = String(trimmed.dropFirst(divertMarker.count))
            .trimmingCharacters(in: .whitespaces)
        if target == endTarget {
            return .end
        }
        return .divert(target)
    }

    private static func appendContent(
        from trimmed: String,
        position: SourcePosition,
        into statements: inout [InkStatement]
    ) throws {
        if trimmed == glueMarker {
            statements.append(InkStatement(kind: .glue, position: position))
            return
        }
        if trimmed.hasSuffix(glueMarker) {
            let text = String(trimmed.dropLast(glueMarker.count))
                .trimmingCharacters(in: .whitespaces)
            statements.append(InkStatement(kind: .text(text), position: position))
            statements.append(InkStatement(kind: .glue, position: position))
            return
        }
        if trimmed.contains("{") {
            let segments = try parseContentSegments(trimmed)
            statements.append(InkStatement(kind: .content(segments), position: position))
            return
        }
        statements.append(InkStatement(kind: .text(trimmed), position: position))
    }

    /// Split a content line into literal/expression segments. Inline-printed
    /// expressions are delimited by `{` … `}`; everything outside the braces is
    /// literal text. Empty literal runs are dropped.
    private static func parseContentSegments(_ line: String) throws -> [ContentSegment] {
        var segments: [ContentSegment] = []
        var literal = ""
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "{" {
                appendLiteral(literal, into: &segments)
                literal = ""
                let (expression, next) = try scanExpression(in: line, after: index)
                segments.append(.expression(expression))
                index = next
                continue
            }
            literal.append(character)
            index = line.index(after: index)
        }
        appendLiteral(literal, into: &segments)
        return segments
    }

    /// Scan a `{ <expr> }` group beginning at the brace at `openIndex`. Returns
    /// the parsed expression and the index just past the closing brace.
    private static func scanExpression(
        in line: String,
        after openIndex: String.Index
    ) throws -> (expression: InkExpression, next: String.Index) {
        var index = line.index(after: openIndex)
        var body = ""
        while index < line.endIndex, line[index] != "}" {
            body.append(line[index])
            index = line.index(after: index)
        }
        let expression = try InkExpressionParser.parse(body.trimmingCharacters(in: .whitespaces))
        let next = index < line.endIndex ? line.index(after: index) : index
        return (expression, next)
    }

    private static func appendLiteral(_ literal: String, into segments: inout [ContentSegment]) {
        guard literal.isEmpty == false else { return }
        segments.append(.literal(literal))
    }

    private static func leadingColumn(of rawLine: String) -> Int {
        var column = 1
        for character in rawLine {
            if character == " " || character == "\t" {
                column += 1
                continue
            }
            break
        }
        return column
    }

    private static func stripped(_ value: String, of marker: Character) -> String {
        var characters = Array(value)
        while characters.first == marker {
            characters.removeFirst()
        }
        while characters.last == marker {
            characters.removeLast()
        }
        return String(characters).trimmingCharacters(in: .whitespaces)
    }
}
