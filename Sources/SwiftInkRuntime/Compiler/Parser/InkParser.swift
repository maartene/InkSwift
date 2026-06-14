// Statement rules for the native Ink compiler (DDD-5): a line-oriented
// recursive-descent pass producing a flat stream of positioned
// `InkStatement`s. S1 constructs only: knot/stitch headers, divert forms
// (absolute, qualified, relative), `-> END`, glue, and plain text. Path
// resolution and codegen are deferred to 01-02 — diverts capture raw target
// strings. Expression parsing (Pratt) lands in S2.

import Foundation

/// Turns comment-stripped `.ink` source into the typed AST the codegen consumes.
public enum InkParser {

    private static let knotMarker = "==="
    private static let divertMarker = "->"
    private static let glueMarker = "<>"
    private static let endTarget = "END"

    /// Parse `.ink` source into a flat, ordered stream of positioned statements.
    public static func parse(_ source: String) throws -> [InkStatement] {
        var statements: [InkStatement] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)

        for (lineIndex, rawLine) in lines.enumerated() {
            let lineNumber = lineIndex + 1
            appendStatements(from: String(rawLine), lineNumber: lineNumber, into: &statements)
        }
        return statements
    }

    private static func appendStatements(
        from rawLine: String,
        lineNumber: Int,
        into statements: inout [InkStatement]
    ) {
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
        if trimmed.hasPrefix(divertMarker) {
            statements.append(InkStatement(kind: divertKind(of: trimmed), position: position))
            return
        }
        appendTextAndGlue(from: trimmed, position: position, into: &statements)
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

    private static func appendTextAndGlue(
        from trimmed: String,
        position: SourcePosition,
        into statements: inout [InkStatement]
    ) {
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
        statements.append(InkStatement(kind: .text(trimmed), position: position))
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
