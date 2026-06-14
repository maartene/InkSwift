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
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var lineIndex = 0
        while lineIndex < lines.count {
            let lineNumber = lineIndex + 1
            let rawLine = lines[lineIndex]
            if let consumed = try appendBlockConditional(lines, from: lineIndex, into: &statements) {
                lineIndex = consumed
                continue
            }
            try appendStatements(from: rawLine, lineNumber: lineNumber, into: &statements)
            lineIndex += 1
        }
        return statements
    }

    /// When the line at `start` opens a multi-line block/switch conditional,
    /// consume every line through the matching `}`, append the parsed
    /// `.conditionalBlock`, and return the index just past the block. Two opener
    /// shapes are recognised: `{ <subject>:` (subject/switch value before the
    /// colon) and a bare `{` (a subject-less guarded block whose arms carry their
    /// own `- guard:` conditions). Returns `nil` when the line is not such an
    /// opener (so the normal single-line path handles it).
    private static func appendBlockConditional(
        _ lines: [String],
        from start: Int,
        into statements: inout [InkStatement]
    ) throws -> Int? {
        let trimmed = lines[start].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"), trimmed.contains("}") == false else {
            return nil
        }
        let afterBrace = String(trimmed.dropFirst())
        let colonIndex = topLevelColonIndex(in: afterBrace)
        // A bare `{` opener must have nothing meaningful before the (absent) colon;
        // otherwise this is a single-line `{expr}` that merely lacks a close brace.
        guard colonIndex != nil || afterBrace.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        let position = SourcePosition(line: start + 1, column: leadingColumn(of: lines[start]))
        let subjectText: String
        var bodyLines: [(text: String, number: Int)] = []
        if let colonIndex {
            subjectText = String(afterBrace[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let firstInline = String(afterBrace[afterBrace.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
            if firstInline.isEmpty == false {
                bodyLines.append((firstInline, start + 1))
            }
        } else {
            // Bare `{` — subject-less guarded block; arms carry their own guards.
            subjectText = ""
        }
        var index = start + 1
        while index < lines.count {
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            if candidate == "}" {
                index += 1
                break
            }
            bodyLines.append((candidate, index + 1))
            index += 1
        }
        let statement = try buildConditionalBlock(subjectText: subjectText, bodyLines: bodyLines, position: position)
        statements.append(statement)
        return index
    }

    /// Assemble a `.conditionalBlock` from the subject expression and the block's
    /// body lines. Lines beginning `- <guard>:` open arms; lines without that
    /// shape are arm content. A block with no `- guard:` arms is a single-guard
    /// block (`{ cond: ...true... - else: ...false... }` collapsed), so its first
    /// implicit arm is guarded by the subject and a switch compares each arm's
    /// label to the subject.
    private static func buildConditionalBlock(
        subjectText: String,
        bodyLines: [(text: String, number: Int)],
        position: SourcePosition
    ) throws -> InkStatement {
        let opensArm = bodyLines.contains { isArmOpener($0.text) }
        if opensArm {
            return try switchOrGuardedBlock(subjectText: subjectText, bodyLines: bodyLines, position: position)
        }
        return try plainGuardedBlock(subjectText: subjectText, bodyLines: bodyLines, position: position)
    }

    /// A block whose body has explicit `- guard:` arms. The subject is a switch
    /// value when any arm's guard is a bare value compared with `==`; a `- else:`
    /// arm (or an arm with empty guard) is the default. Whether the block is a
    /// switch (subject compared to each label) or a guarded block (each arm's
    /// guard is its own condition) is decided by whether the subject is itself a
    /// boolean expression — here we treat a subject that is a lone identifier or
    /// value as a switch, and a subject containing a comparison operator as a
    /// guarded block whose first arm reuses the subject.
    private static func switchOrGuardedBlock(
        subjectText: String,
        bodyLines: [(text: String, number: Int)],
        position: SourcePosition
    ) throws -> InkStatement {
        // A bare `{`-opener block has no subject: every arm carries its own guard,
        // so it is always a guarded (non-switch) block with no pre-arm content.
        let hasSubject = subjectText.isEmpty == false
        let isSwitch = hasSubject && subjectIsSwitchValue(subjectText)
        // A switch compares the subject value against each arm's label; a guarded
        // block treats the subject as the first arm's guard and any content before
        // the first explicit `- guard:` arm as that arm's body.
        let subject: InkExpression = isSwitch
            ? try InkExpressionParser.parse(subjectText)
            : .boolLiteral(true)
        var branches: [ConditionalBranch] = []
        var pendingMatch: InkExpression? = (isSwitch || hasSubject == false)
            ? nil
            : try InkExpressionParser.parse(subjectText)
        var pendingBody: [InkStatement] = []
        var armStarted = isSwitch == false && hasSubject

        for line in bodyLines {
            if let guardText = armGuard(of: line.text) {
                if armStarted {
                    branches.append(ConditionalBranch(match: pendingMatch, body: pendingBody))
                }
                armStarted = true
                pendingMatch = try armMatch(guardText)
                pendingBody = []
                let inline = armInlineBody(of: line.text)
                if inline.isEmpty == false {
                    try appendStatements(from: inline, lineNumber: line.number, into: &pendingBody)
                }
                continue
            }
            try appendStatements(from: line.text, lineNumber: line.number, into: &pendingBody)
        }
        if armStarted {
            branches.append(ConditionalBranch(match: pendingMatch, body: pendingBody))
        }
        return InkStatement(
            kind: .conditionalBlock(subject: subject, isSwitch: isSwitch, branches: branches),
            position: position
        )
    }

    /// A `{ cond: ...true... }` block with no explicit arms: a single guarded
    /// true-arm and an empty implicit else. Modeled as a guarded block.
    private static func plainGuardedBlock(
        subjectText: String,
        bodyLines: [(text: String, number: Int)],
        position: SourcePosition
    ) throws -> InkStatement {
        let condition = try InkExpressionParser.parse(subjectText)
        var trueBody: [InkStatement] = []
        for line in bodyLines {
            try appendStatements(from: line.text, lineNumber: line.number, into: &trueBody)
        }
        let branches = [ConditionalBranch(match: condition, body: trueBody)]
        return InkStatement(
            kind: .conditionalBlock(subject: .boolLiteral(true), isSwitch: false, branches: branches),
            position: position
        )
    }

    /// True when the subject reads as a switch value (a bare identifier/number)
    /// rather than a boolean guard (containing a comparison operator).
    private static func subjectIsSwitchValue(_ subjectText: String) -> Bool {
        let comparisonOperators = [">", "<", "==", "!=", ">=", "<="]
        return comparisonOperators.contains { subjectText.contains($0) } == false
    }

    /// True when a body line opens an arm: `- <guard>:`.
    private static func isArmOpener(_ text: String) -> Bool {
        armGuard(of: text) != nil
    }

    /// The guard text of an arm-opening line `- <guard>: …`, or `nil` when the
    /// line does not open an arm. The guard is the text between the leading `-`
    /// and the top-level `:`.
    private static func armGuard(of text: String) -> String? {
        guard text.hasPrefix("-") else { return nil }
        let afterMarker = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard let colonIndex = topLevelColonIndex(in: afterMarker) else { return nil }
        return String(afterMarker[..<colonIndex]).trimmingCharacters(in: .whitespaces)
    }

    /// The inline body following an arm guard on the same line: `- 1: Arrested.`
    /// yields `Arrested.`. Empty when the arm body is on subsequent lines.
    private static func armInlineBody(of text: String) -> String {
        let afterMarker = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard let colonIndex = topLevelColonIndex(in: afterMarker) else { return "" }
        return String(afterMarker[afterMarker.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
    }

    /// Parse an arm guard into its match expression. The `else` guard (or an empty
    /// guard) is the default arm (`nil`).
    private static func armMatch(_ guardText: String) throws -> InkExpression? {
        if guardText == "else" || guardText.isEmpty {
            return nil
        }
        return try InkExpressionParser.parse(guardText)
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

        try UnsupportedConstructDetector.checkStatement(
            line: trimmed,
            lineNumber: position.line,
            column: position.column
        )

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
        if let kind = weaveKind(of: trimmed) {
            statements.append(InkStatement(kind: kind, position: position))
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

    /// Recognise a weave line: a choice (`*`/`+`, once-only/sticky) or a gather
    /// (`-`). The leading marker run gives the weave level; the remainder is the
    /// choice/gather text. `->` is NOT a gather — it is consumed as a divert
    /// before this is reached. Returns `nil` for any non-weave line.
    private static func weaveKind(of trimmed: String) -> InkStatementKind? {
        guard let marker = trimmed.first else { return nil }
        if marker == "*" || marker == "+" {
            return choiceKind(of: trimmed, marker: marker)
        }
        if marker == "-" {
            return gatherKind(of: trimmed)
        }
        return nil
    }

    /// Parse a choice line `* [label] body` / `+ body`. The leading run of the
    /// same marker is the weave level; `[…]` (when present) is the choice-only
    /// label that is shown but not echoed into the outcome body.
    private static func choiceKind(of trimmed: String, marker: Character) -> InkStatementKind {
        let (level, remainder) = consumeMarkers(trimmed, marker: marker)
        let (choiceOnlyLabel, body) = splitChoiceOnlyLabel(remainder)
        return .choice(
            level: level,
            isSticky: marker == "+",
            choiceOnlyLabel: choiceOnlyLabel,
            body: body
        )
    }

    /// Parse a gather line `- outcome` / `- - outcome` / `- (name) outcome`.
    private static func gatherKind(of trimmed: String) -> InkStatementKind {
        let (level, remainder) = consumeMarkers(trimmed, marker: "-")
        let (label, outcome) = splitGatherLabel(remainder)
        return .gather(level: level, label: label, outcome: outcome)
    }

    /// Consume the leading run of `marker` characters (separated by optional
    /// whitespace, e.g. `* * `), returning the count (weave level) and the
    /// trimmed text after the run.
    private static func consumeMarkers(_ trimmed: String, marker: Character) -> (level: Int, rest: String) {
        var level = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character == marker {
                level += 1
                index = trimmed.index(after: index)
                continue
            }
            if character == " " || character == "\t" {
                index = trimmed.index(after: index)
                continue
            }
            break
        }
        let rest = String(trimmed[index...]).trimmingCharacters(in: .whitespaces)
        return (level, rest)
    }

    /// Split a `[choice-only] body` remainder into the bracketed choice-only
    /// label and the outcome body. With no brackets the whole remainder is body.
    private static func splitChoiceOnlyLabel(_ remainder: String) -> (label: String?, body: String) {
        guard remainder.hasPrefix("["),
              let close = remainder.firstIndex(of: "]") else {
            return (nil, remainder)
        }
        let label = String(remainder[remainder.index(after: remainder.startIndex)..<close])
        let body = String(remainder[remainder.index(after: close)...])
            .trimmingCharacters(in: .whitespaces)
        return (label, body)
    }

    /// Split a `(name) outcome` remainder into the optional gather label and the
    /// outcome text. With no parenthesised label the whole remainder is outcome.
    private static func splitGatherLabel(_ remainder: String) -> (label: String?, outcome: String) {
        guard remainder.hasPrefix("("),
              let close = remainder.firstIndex(of: ")") else {
            return (nil, remainder)
        }
        let label = String(remainder[remainder.index(after: remainder.startIndex)..<close])
        let outcome = String(remainder[remainder.index(after: close)...])
            .trimmingCharacters(in: .whitespaces)
        return (label, outcome)
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
        if trimmed.contains("{") || trimmed.contains("#") {
            if trimmed.contains("{") {
                try UnsupportedConstructDetector.check(line: trimmed, lineNumber: position.line)
            }
            let segments = try parseContentSegments(trimmed)
            statements.append(InkStatement(kind: .content(segments), position: position))
            return
        }
        statements.append(InkStatement(kind: .text(trimmed), position: position))
    }

    /// Split a content line into literal/expression/conditional/tag segments.
    /// Inline groups are delimited by `{` … `}` (an inline-printed expression, or
    /// an inline conditional when the body carries a top-level `:`); a `#` starts
    /// a tag running to the end of the line; everything else is literal text.
    /// Empty literal runs are dropped.
    private static func parseContentSegments(_ line: String) throws -> [ContentSegment] {
        var segments: [ContentSegment] = []
        var literal = ""
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "{" {
                appendLiteral(literal, into: &segments)
                literal = ""
                let (segment, next) = try scanBraceSegment(in: line, after: index)
                segments.append(segment)
                index = next
                continue
            }
            if character == "#" {
                appendLiteral(literal.trimmingCharacters(in: .whitespaces), into: &segments)
                literal = ""
                let tag = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespaces)
                segments.append(.tag(tag))
                break
            }
            literal.append(character)
            index = line.index(after: index)
        }
        appendLiteral(literal, into: &segments)
        return segments
    }

    /// Scan a `{ … }` group beginning at the brace at `openIndex`. A body with a
    /// top-level `:` is an inline conditional `{ cond: a|b }`; otherwise it is an
    /// inline-printed expression. Returns the resulting segment and the index just
    /// past the closing brace.
    private static func scanBraceSegment(
        in line: String,
        after openIndex: String.Index
    ) throws -> (segment: ContentSegment, next: String.Index) {
        var index = line.index(after: openIndex)
        var body = ""
        while index < line.endIndex, line[index] != "}" {
            body.append(line[index])
            index = line.index(after: index)
        }
        let next = index < line.endIndex ? line.index(after: index) : index
        if let colonIndex = topLevelColonIndex(in: body) {
            return (try inlineConditionalSegment(body, colonIndex: colonIndex), next)
        }
        let expression = try InkExpressionParser.parse(body.trimmingCharacters(in: .whitespaces))
        return (.expression(expression), next)
    }

    /// Build an inline-conditional segment from a `{ cond: a|b }` body, split at
    /// the top-level `:`. The branches are the `a|b` alternatives (a missing `|`
    /// yields an empty false branch).
    private static func inlineConditionalSegment(
        _ body: String,
        colonIndex: String.Index
    ) throws -> ContentSegment {
        let conditionText = String(body[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let branchesText = String(body[body.index(after: colonIndex)...])
        let condition = try InkExpressionParser.parse(conditionText)
        let (ifTrue, ifFalse) = splitInlineBranches(branchesText)
        return .conditional(condition: condition, ifTrue: ifTrue, ifFalse: ifFalse)
    }

    /// Split `a|b` branch text at the first top-level `|`. With no `|` the whole
    /// text is the true branch and the false branch is empty.
    private static func splitInlineBranches(_ text: String) -> (ifTrue: String, ifFalse: String) {
        guard let barIndex = topLevelBarIndex(in: text) else {
            return (text, "")
        }
        let ifTrue = String(text[..<barIndex])
        let ifFalse = String(text[text.index(after: barIndex)...])
        return (ifTrue, ifFalse)
    }

    /// Index of the first `:` at brace-nesting depth 0, or `nil` when none — used
    /// to discriminate an inline conditional from a plain interpolation.
    private static func topLevelColonIndex(in body: String) -> String.Index? {
        topLevelIndex(of: ":", in: body)
    }

    /// Index of the first `|` at brace-nesting depth 0, or `nil` when none.
    private static func topLevelBarIndex(in body: String) -> String.Index? {
        topLevelIndex(of: "|", in: body)
    }

    private static func topLevelIndex(of target: Character, in body: String) -> String.Index? {
        var depth = 0
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1 }
            if character == target && depth == 0 { return index }
            index = body.index(after: index)
        }
        return nil
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
