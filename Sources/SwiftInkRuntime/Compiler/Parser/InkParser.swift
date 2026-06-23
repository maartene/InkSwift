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

    private static let knotMarker = "=="
    private static let divertMarker = "->"
    private static let endTarget = "END"
    private static let varMarker = "VAR"
    private static let constMarker = "CONST"
    private static let logicMarker = "~"
    private static let tempMarker = "temp"
    private static let functionMarker = "function"
    private static let refMarker = "ref"
    private static let returnMarker = "return"
    private static let tunnelReturnMarker = "->->"

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
        let rawTrimmed = lines[start].trimmingCharacters(in: .whitespaces)
        // A gather may itself OPEN a multi-line block conditional: `-     { teacup:`
        // (TheIntercept ~159). The gather marker run is consumed and the remaining
        // `{ subject:` is parsed as the block opener; a gather header with an empty
        // outcome is emitted FIRST (only once we have confirmed a real opener), then
        // the block is lowered into the gather's body by `parseGather` (which
        // collects the trailing `.conditionalBlock` statement). Without this, the
        // gather's outcome was `{ teacup:` and the block body lines (assignment,
        // glue+text, the bare `}`) leaked as separate statements — the `}` echoed as
        // literal text.
        let (afterMarkers, pendingGather) = gatherBlockOpener(rawTrimmed, at: start)
        let trimmed = afterMarkers
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
        // Both opener guards passed — emit the gather header (if a gather marker
        // prefixed the opener) so it is never orphaned by an early `nil` return.
        if let pendingGather {
            statements.append(pendingGather)
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
        var depth = 0
        while index < lines.count {
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            if candidate == "}" {
                if depth == 0 {
                    index += 1
                    break
                }
                bodyLines.append((candidate, index + 1))
                depth -= 1
            } else {
                if candidate.hasPrefix("{") && !candidate.contains("}") {
                    depth += 1
                }
                bodyLines.append((candidate, index + 1))
            }
            index += 1
        }
        let statement = try buildConditionalBlock(subjectText: subjectText, bodyLines: bodyLines, position: position)
        statements.append(statement)
        return index
    }

    /// Strip a leading gather-marker run off a line that opens a multi-line block
    /// conditional. Returns the text after the markers and, when a gather prefix was
    /// present, the gather header statement to emit before the block (an empty
    /// outcome — the block becomes the gather's body via `parseGather`). With no
    /// gather prefix the line is returned unchanged and the pending gather is `nil`.
    /// Only a `-` run followed by a `{` (not `->`) is treated as a gather opener.
    private static func gatherBlockOpener(
        _ trimmed: String,
        at start: Int
    ) -> (afterMarkers: String, pendingGather: InkStatement?) {
        guard trimmed.first == "-" else {
            return (trimmed, nil)
        }
        let (level, remainder) = consumeMarkers(trimmed, marker: "-")
        guard level > 0, remainder.first == "{" else {
            return (trimmed, nil)
        }
        let (label, outcome) = splitGatherLabel(remainder)
        // A parenthesised gather label leaves a `{`-prefixed outcome; a labelless
        // gather leaves the whole `{ subject:` remainder. Only treat it as a block
        // opener when what follows the optional label still opens with `{`.
        guard outcome.first == "{" else {
            return (trimmed, nil)
        }
        let position = SourcePosition(line: start + 1, column: leadingColumn(of: trimmed))
        let gather = InkStatement(
            kind: .gather(level: level, label: label, outcome: ""),
            position: position
        )
        return (outcome, gather)
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
        let opensArm = hasArmOpenerAtDepth0(bodyLines)
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
        // A real switch opens DIRECTLY with `- guard:` arms (`{ x: - 1: … - 2: … }`):
        // its first body line is an arm opener, no content precedes it. A guarded
        // if/else carries content right after `{ subject:` as the implicit first arm
        // (`{ not flag: …true… - else: …false… }`) — the subject is that arm's guard,
        // NOT a switch value. Without this structural guard a guarded if/else whose
        // subject lacked a comparison operator (e.g. `not knot.label`) was misread as
        // a switch, dropping the implicit-first-arm content and its condition entirely.
        let opensWithArm = bodyLines.first.map { isArmOpener($0.text) } ?? false
        let isSwitch = hasSubject && opensWithArm && subjectIsSwitchValue(subjectText)
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

        var lineIndex = 0
        while lineIndex < bodyLines.count {
            let line = bodyLines[lineIndex]
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
                lineIndex += 1
                continue
            }
            lineIndex = try appendBodyUnit(bodyLines: bodyLines, from: lineIndex, into: &pendingBody)
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
        var lineIndex = 0
        while lineIndex < bodyLines.count {
            lineIndex = try appendBodyUnit(bodyLines: bodyLines, from: lineIndex, into: &trueBody)
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

    /// True when any body line at brace-nesting depth 0 is an arm opener.
    /// Lines inside nested `{…}` blocks are at depth > 0 and are excluded so
    /// inner block arms are not mistaken for arms of the enclosing block.
    private static func hasArmOpenerAtDepth0(_ bodyLines: [(text: String, number: Int)]) -> Bool {
        var depth = 0
        for line in bodyLines {
            let trimmed = line.text
            if trimmed.hasPrefix("{") && !trimmed.contains("}") {
                depth += 1
            } else if trimmed == "}" {
                if depth > 0 { depth -= 1 }
            } else if depth == 0 && isArmOpener(trimmed) {
                return true
            }
        }
        return false
    }

    /// Process one logical unit from `bodyLines` at `index` into `statements`
    /// and return the next index. A bare `{` opener (starts with `{`, no `}` on
    /// the same line) is a nested multi-line block — it is recursively assembled
    /// via `buildConditionalBlock`. Any other line is dispatched to
    /// `appendStatements` as usual.
    private static func appendBodyUnit(
        bodyLines: [(text: String, number: Int)],
        from index: Int,
        into statements: inout [InkStatement]
    ) throws -> Int {
        let line = bodyLines[index]
        let trimmed = line.text
        guard trimmed.hasPrefix("{"), !trimmed.contains("}") else {
            try appendStatements(from: line.text, lineNumber: line.number, into: &statements)
            return index + 1
        }
        let position = SourcePosition(line: line.number, column: 1)
        let afterBrace = String(trimmed.dropFirst())
        var nestedBodyLines: [(text: String, number: Int)] = []
        let subjectText: String
        if let colonIndex = topLevelColonIndex(in: afterBrace) {
            subjectText = String(afterBrace[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let firstInline = String(afterBrace[afterBrace.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
            if !firstInline.isEmpty {
                nestedBodyLines.append((firstInline, line.number))
            }
        } else {
            subjectText = ""
        }
        var depth = 1
        var nextIndex = index + 1
        while nextIndex < bodyLines.count {
            let nested = bodyLines[nextIndex]
            let nestedTrimmed = nested.text
            if nestedTrimmed == "}" {
                depth -= 1
                if depth == 0 {
                    nextIndex += 1
                    break
                }
                nestedBodyLines.append((nestedTrimmed, nested.number))
            } else {
                if nestedTrimmed.hasPrefix("{") && !nestedTrimmed.contains("}") {
                    depth += 1
                }
                nestedBodyLines.append((nestedTrimmed, nested.number))
            }
            nextIndex += 1
        }
        let statement = try buildConditionalBlock(
            subjectText: subjectText, bodyLines: nestedBodyLines, position: position)
        statements.append(statement)
        return nextIndex
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

        if let kind = try headerKind(of: trimmed) {
            statements.append(InkStatement(kind: kind, position: position))
            return
        }
        if let kind = try declarationKind(of: trimmed) {
            statements.append(InkStatement(kind: kind, position: position))
            return
        }
        if trimmed == tunnelReturnMarker {
            statements.append(InkStatement(kind: .tunnelReturn, position: position))
            return
        }
        if trimmed.hasPrefix(divertMarker) {
            statements.append(contentsOf: divertStatements(of: trimmed, at: position))
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

    /// Lower a logic line `~ <body>`: `return e` returns from a function, `temp x
    /// = e` declares a local, `f(args)` calls a function for its side effects
    /// (result discarded), otherwise `x = e` reassigns an existing variable.
    private static func logicKind(of body: String) throws -> InkStatementKind {
        let trimmedBody = body.trimmingCharacters(in: .whitespaces)
        if let returnBody = keywordBody(trimmedBody, keyword: returnMarker) {
            return .returnStatement(try InkExpressionParser.parse(returnBody))
        }
        if trimmedBody == returnMarker {
            return .returnStatement(nil)
        }
        if let tempBody = keywordBody(trimmedBody, keyword: tempMarker) {
            let (name, value) = try splitAssignment(tempBody)
            return .temporaryVariable(name: name, value: value)
        }
        if trimmedBody.contains("=") == false {
            return .functionCallStatement(try InkExpressionParser.parse(trimmedBody))
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

    /// Parse a choice line `* (label) {condition} [choiceOnly] body` / `+ body`.
    /// The leading run of the same marker is the weave level. A leading `(name)`
    /// is the weave label (read-count addressing, ADR-011), parsed by REUSING the
    /// generic `splitBracketedLabel` helper with `(`/`)` — exactly as gathers do.
    /// A following `{…}` is the guard condition, captured separately from content.
    /// `[…]` (when present) is the choice-only label shown but not echoed into the
    /// outcome body.
    private static func choiceKind(of trimmed: String, marker: Character) -> InkStatementKind {
        let (level, remainder) = consumeMarkers(trimmed, marker: marker)
        let (weaveLabel, afterLabel) = splitWeaveLabel(remainder)
        let (condition, afterCondition) = splitChoiceCondition(afterLabel)
        let (choiceOnlyLabel, body) = splitChoiceOnlyLabel(afterCondition)
        return .choice(
            level: level,
            isSticky: marker == "+",
            choiceOnlyLabel: choiceOnlyLabel,
            body: body,
            weaveLabel: weaveLabel,
            condition: condition
        )
    }

    /// Split a leading `(name)` weave label off a choice remainder, REUSING the
    /// generic `splitBracketedLabel` helper with `(`/`)` (the same helper gathers
    /// use — no new parsing helper is added). With no leading parenthesised label
    /// the whole remainder is returned unchanged and the label is `nil`.
    private static func splitWeaveLabel(_ remainder: String) -> (label: String?, rest: String) {
        splitBracketedLabel(remainder, open: "(", close: ")")
    }

    /// Split a leading `{condition}` guard off a choice remainder into the parsed
    /// guard expression and the trimmed text after it. With no leading `{…}` the
    /// whole remainder is returned unchanged and the condition is `nil`. A `{` that
    /// is not a leading guard (e.g. inline-printed content) is left for the content
    /// pass — only a `{` at the very start of the remainder is treated as a guard.
    private static func splitChoiceCondition(_ remainder: String) -> (condition: InkExpression?, rest: String) {
        guard remainder.first == "{",
              let closeIndex = remainder.firstIndex(of: "}") else {
            return (nil, remainder)
        }
        let conditionText = String(remainder[remainder.index(after: remainder.startIndex)..<closeIndex])
            .trimmingCharacters(in: .whitespaces)
        let rest = String(remainder[remainder.index(after: closeIndex)...])
            .trimmingCharacters(in: .whitespaces)
        guard let condition = try? InkExpressionParser.parse(conditionText) else {
            return (nil, remainder)
        }
        return (condition, rest)
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
                // A `-` immediately followed by `>` opens a `->` divert, not another
                // gather marker — stop so `- -> target` parses as a level-1 gather
                // whose body is the divert (parser bug #1, step 03-01). Choices
                // (`*`/`+`) are unaffected: this guard only fires for `marker == "-"`.
                let next = trimmed.index(after: index)
                if marker == "-", next < trimmed.endIndex, trimmed[next] == ">" {
                    break
                }
                level += 1
                index = next
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

    /// Split a `prefix[choiceOnly]suffix` remainder into the choice menu text and
    /// the taken-outcome body. Ink choice-text semantics: the menu shows
    /// `prefix + choiceOnly`; the taken outcome is `prefix + suffix` (the prefix is
    /// shared, the bracket span is menu-only, the suffix is outcome-only). With no
    /// bracket the whole remainder is the outcome body and the label is `nil`
    /// (the plain-choice case — the body is echoed as the menu text downstream).
    ///
    /// The bracket may be preceded by a non-empty `prefix` (parser bug #2, step
    /// 03-01): the earlier helper only split a bracket at the very start, so
    /// `Hut 14[]. …` was left as literal text including the `[]`. Modelled within
    /// the existing AST fields: `label` carries the menu text (`prefix + choiceOnly`)
    /// and `body` carries the glued outcome (`prefix + suffix`).
    private static func splitChoiceOnlyLabel(_ remainder: String) -> (label: String?, body: String) {
        guard let openIndex = remainder.firstIndex(of: "["),
              let closeIndex = remainder[remainder.index(after: openIndex)...].firstIndex(of: "]") else {
            return (nil, remainder)
        }
        let prefix = String(remainder[..<openIndex])
        let choiceOnly = String(remainder[remainder.index(after: openIndex)..<closeIndex])
        let suffix = String(remainder[remainder.index(after: closeIndex)...])
        let menuText = (prefix + choiceOnly).trimmingCharacters(in: .whitespaces)
        let outcome = (prefix + suffix).trimmingCharacters(in: .whitespaces)
        return (menuText, outcome)
    }

    /// Split a `(name) outcome` remainder into the optional gather label and the
    /// outcome text. With no parenthesised label the whole remainder is outcome.
    private static func splitGatherLabel(_ remainder: String) -> (label: String?, outcome: String) {
        let split = splitBracketedLabel(remainder, open: "(", close: ")")
        return (split.label, split.rest)
    }

    /// Split a `<open>label<close> rest` remainder into the bracketed label and
    /// the trimmed text after it. With no leading `open`…`close` pair the whole
    /// remainder is the trailing text and the label is `nil`.
    private static func splitBracketedLabel(
        _ remainder: String,
        open: Character,
        close: Character
    ) -> (label: String?, rest: String) {
        guard remainder.first == open,
              let closeIndex = remainder.firstIndex(of: close) else {
            return (nil, remainder)
        }
        let label = String(remainder[remainder.index(after: remainder.startIndex)..<closeIndex])
        let rest = String(remainder[remainder.index(after: closeIndex)...])
            .trimmingCharacters(in: .whitespaces)
        return (label, rest)
    }

    private static func headerKind(of trimmed: String) throws -> InkStatementKind? {
        // A knot header opens with two or more `=` (inklecate treats `==` and
        // `===` identically); a single leading `=` is a stitch. A function knot
        // (`== function f() ==` / `=== function f() ===`) is recognised after the
        // marker is stripped.
        if trimmed.hasPrefix(knotMarker) {
            return try knotOrFunctionHeader(stripped(trimmed, of: "="))
        }
        if trimmed.hasPrefix("=") {
            return .stitch(stripped(trimmed, of: "="))
        }
        return nil
    }

    /// Classify a stripped knot header. A header opening with the `function`
    /// keyword is a function definition `=== function name(params) ===`; its
    /// parameter list (with `ref` markers) is parsed here and the body lines are
    /// grouped by the emitter (like a knot). Any other header is a plain knot.
    private static func knotOrFunctionHeader(_ header: String) throws -> InkStatementKind {
        guard let body = keywordBody(header, keyword: functionMarker) else {
            return .knot(header)
        }
        let (name, parameters) = try parseFunctionSignature(body)
        return .functionDefinition(name: name, parameters: parameters, body: [])
    }

    /// Parse a function signature `name(p1, ref p2)` into the name and ordered
    /// parameters. A parameter prefixed `ref ` is a reference parameter. A bare
    /// `name` (no parentheses) declares a zero-parameter function.
    private static func parseFunctionSignature(
        _ signature: String
    ) throws -> (name: String, parameters: [FunctionParameter]) {
        guard let open = signature.firstIndex(of: "(") else {
            return (signature.trimmingCharacters(in: .whitespaces), [])
        }
        let name = String(signature[..<open]).trimmingCharacters(in: .whitespaces)
        guard let close = signature.firstIndex(of: ")") else {
            throw InkExpressionParseError.unexpectedToken(signature)
        }
        let inside = String(signature[signature.index(after: open)..<close])
        let parameters = inside
            .split(separator: ",")
            .map { parseParameter(String($0)) }
            .filter { $0.name.isEmpty == false }
        return (name, parameters)
    }

    /// Parse one parameter declaration into a `FunctionParameter`, recognising a
    /// leading `ref ` keyword as a reference parameter.
    private static func parseParameter(_ declaration: String) -> FunctionParameter {
        let trimmed = declaration.trimmingCharacters(in: .whitespaces)
        if let name = keywordBody(trimmed, keyword: refMarker) {
            return FunctionParameter(name: name, isReference: true)
        }
        return FunctionParameter(name: trimmed, isReference: false)
    }

    private static func divertKind(of trimmed: String) -> InkStatementKind {
        let target = String(trimmed.dropFirst(divertMarker.count))
            .trimmingCharacters(in: .whitespaces)
        if target == endTarget {
            return .end
        }
        // A target ending in `->` is a tunnel divert `-> k ->`: run knot `k` then
        // return to the call site via the runtime's `->->` convention.
        if target.hasSuffix(divertMarker) {
            let tunnelTarget = String(target.dropLast(divertMarker.count))
                .trimmingCharacters(in: .whitespaces)
            return .tunnelDivert(tunnelTarget)
        }
        return .divert(target)
    }

    /// Lower a leading-`->` divert line into one OR MORE statements, recognising a
    /// TUNNEL CHAIN `-> A -> B [-> C …]`: each non-final hop tunnel-calls its knot
    /// (`tunnelDivert`, runtime `->t->`) and, on the knot's `->->` return, flow
    /// falls through to the next hop; the final hop is a plain divert (`->`),
    /// matching inklecate's adjacent `{"->t->":A},{"->":B}` emission. A bare single
    /// divert / `-> END` / single tunnel (`-> k ->`) is unchanged (one statement).
    static func divertStatements(
        of trimmed: String,
        at position: SourcePosition
    ) -> [InkStatement] {
        let body = String(trimmed.dropFirst(divertMarker.count))
            .trimmingCharacters(in: .whitespaces)
        let endsAsTunnel = body.hasSuffix(divertMarker)
        let hops = body
            .components(separatedBy: divertMarker)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
        // A real chain has ≥2 named hops with a plain final divert. Anything else
        // (single divert, `-> END`, single tunnel `-> k ->`) keeps the one-statement
        // path so existing behaviour is untouched.
        guard hops.count >= 2, endsAsTunnel == false else {
            return [InkStatement(kind: divertKind(of: trimmed), position: position)]
        }
        var statements: [InkStatement] = []
        for tunnelTarget in hops.dropLast() {
            statements.append(InkStatement(kind: .tunnelDivert(tunnelTarget), position: position))
        }
        let finalTarget = hops[hops.count - 1]
        let finalKind: InkStatementKind = finalTarget == endTarget ? .end : .divert(finalTarget)
        statements.append(InkStatement(kind: finalKind, position: position))
        return statements
    }

    /// Parse a weave-outcome string (a gather's `- outcome`) into a single
    /// `InkStatement`, applying the SAME line recognisers the main statement pass
    /// uses so a gather outcome behaves like the body line it stands in for:
    /// a `~` logic line executes (not echoed), a `{…}` group lowers to `.content`
    /// (variable-text / inline-conditional gather lead recognised by `lowerBody`,
    /// #3b layer 1), and plain prose is `.text`. (`->` diverts are handled by the
    /// caller's arrow split, which also supports a leading prose prefix.) An empty
    /// outcome yields `nil`. No new parsing logic is added — the existing
    /// declaration / content recognisers are reused.
    public static func outcomeStatement(
        _ outcome: String,
        at position: SourcePosition
    ) throws -> InkStatement? {
        let trimmed = outcome.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else { return nil }
        if let kind = try declarationKind(of: trimmed) {
            return InkStatement(kind: kind, position: position)
        }
        guard trimmed.contains("{") else {
            return InkStatement(kind: .text(trimmed), position: position)
        }
        try UnsupportedConstructDetector.check(line: trimmed, lineNumber: position.line)
        let segments = try parseContentSegments(trimmed)
        return InkStatement(kind: .content(segments), position: position)
    }

    private static func appendContent(
        from trimmed: String,
        position: SourcePosition,
        into statements: inout [InkStatement]
    ) throws {
        // A line carrying a glue marker `<>` on either edge: emit a glue statement
        // in the marker's place (see `GlueMarker`, the shared edge splitter).
        //
        // LEADING `<>` glues to the preceding output (the block conditional body
        // `<>, sipping…` and the post-block `<>.` in TheIntercept ~161/163): emit
        // glue first, then lower the remainder so its prose joins the previous
        // output line instead of echoing `<>` as literal text. The source
        // whitespace AFTER `<>` is literal content inklecate preserves (the
        // post-block `<> You scientists."` at TheIntercept.ink ~1685 lowers to the
        // oracle text node `^ You scientists.`, a LEADING space). Trimming it would
        // yield `affairs.You` instead of the oracle's `affairs. You`. So for a
        // plain-prose remainder, keep the rest VERBATIM; a brace-/divert-/glue-
        // bearing remainder still re-dispatches through `appendContent` (which
        // trims) so those constructs are still recognised — symmetric with
        // `WeaveEmitter.inlineBodyStatements`' leading-`<>` branch.
        switch GlueMarker.edge(of: trimmed) {
        case .leading(let remainder):
            statements.append(InkStatement(kind: .glue, position: position))
            if remainder.contains("{") || remainder.contains("#")
                || remainder.contains(divertMarker) || remainder.hasSuffix(GlueMarker.marker) {
                let dispatchable = remainder.trimmingCharacters(in: .whitespaces)
                if dispatchable.isEmpty == false {
                    try appendContent(from: dispatchable, position: position, into: &statements)
                }
            } else if remainder.trimmingCharacters(in: .whitespaces).isEmpty == false {
                statements.append(InkStatement(kind: .text(remainder), position: position))
            }
            return
        case .trailing(let prose):
            let text = prose.trimmingCharacters(in: .whitespaces)
            statements.append(InkStatement(kind: .text(text), position: position))
            statements.append(InkStatement(kind: .glue, position: position))
            return
        case .none:
            break
        }
        if trimmed.contains("{") || trimmed.contains("#") {
            if trimmed.contains("{") {
                try UnsupportedConstructDetector.check(line: trimmed, lineNumber: position.line)
            }
            let segments = try parseContentSegments(trimmed)
            statements.append(InkStatement(kind: .content(segments), position: position))
            return
        }
        // A plain prose line carrying a MID-line divert (`Harris looks disapproving.
        // -> pushes_cup`) splits into the prose text, default divert glue (ink glues
        // prose to its divert target), and the divert — so the arrow is a real
        // control-flow divert, not echoed as literal text. A leading-`->` divert is
        // already handled by the caller before reaching `appendContent`; here the
        // prefix is non-empty (`range(of:)` finds the arrow past the start).
        if let arrowRange = trimmed.range(of: divertMarker),
           arrowRange.lowerBound != trimmed.startIndex {
            let prose = String(trimmed[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let target = String(trimmed[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if prose.isEmpty == false, target.isEmpty == false, target.contains("->") == false {
                statements.append(InkStatement(kind: .text(prose), position: position))
                if target != "END" {
                    statements.append(InkStatement(kind: .glue, position: position))
                    statements.append(InkStatement(kind: .divert(target), position: position))
                } else {
                    statements.append(InkStatement(kind: .end, position: position))
                }
                return
            }
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
        if topLevelBarIndex(in: body) != nil {
            return (variableTextSegment(body), next)
        }
        let expression = try InkExpressionParser.parse(body.trimmingCharacters(in: .whitespaces))
        return (.expression(expression), next)
    }

    /// Build a variable-text segment from a `{a|b|c}` / `{&a|b}` / `{!a|b}` body
    /// (it has a top-level `|` but no top-level `:`). The leading marker selects
    /// the mode — `&` cycle, `!` once, none sequence — and is stripped before the
    /// body is top-level-`|`-split into raw stage texts. A leading `\` escape means
    /// the first character is literal, so the form is a plain sequence. Shuffle
    /// `{~a|b}` never reaches here: `UnsupportedConstructDetector` rejects it first.
    private static func variableTextSegment(_ body: String) -> ContentSegment {
        let (mode, content) = modeAndContent(of: body)
        let stages = topLevelBarSplit(content)
        return .variableText(mode: mode, stages: stages)
    }

    /// Read the leading mode marker of a variable-text body and return the mode
    /// plus the body with that marker stripped. A leading `\` escape yields a
    /// sequence over the body minus the escape character.
    private static func modeAndContent(of body: String) -> (VariableTextMode, String) {
        if body.first == "\\" {
            return (.sequence, String(body.dropFirst()))
        }
        switch body.first {
        case "&": return (.cycle, String(body.dropFirst()))
        case "!": return (.once, String(body.dropFirst()))
        default: return (.sequence, body)
        }
    }

    /// Split a variable-text body at every top-level `|` into stage texts,
    /// ignoring `|` nested inside `{…}` groups.
    private static func topLevelBarSplit(_ body: String) -> [String] {
        var stages: [String] = []
        var current = ""
        var depth = 0
        for character in body {
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1 }
            if character == "|" && depth == 0 {
                stages.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        stages.append(current)
        return stages
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
