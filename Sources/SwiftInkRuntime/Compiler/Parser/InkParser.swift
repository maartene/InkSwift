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
    private static let divertMarker = ContentTextScanner.Marker.divert.text
    private static let endTarget = "END"
    private static let varMarker = "VAR"
    private static let constMarker = "CONST"
    private static let logicMarker = "~"
    private static let tempMarker = "temp"
    private static let functionMarker = "function"
    private static let refMarker = "ref"
    private static let returnMarker = "return"
    private static let tunnelReturnMarker = "->->"

    /// One trimmed line of a block conditional's body, with its 1-based source
    /// line and its shape, classified once from the text.
    private struct BodyLine {
        let text: String
        let number: Int
        let shape: LineShape

        init(text: String, number: Int) throws {
            self.text = text
            self.number = number
            self.shape = try CompileError.locating(line: number, column: 1) { try InkParser.lineShape(of: text) }
        }
    }

    /// What a block body line is. Each case stands in for the reference grammar
    /// rule noted on it (`InkParser_Conditional.cs`); everything downstream
    /// switches over the shape instead of re-scanning the text.
    private enum LineShape {
        /// `{ subject:` or a bare `{`, with no `}` on the line: opens a nested
        /// multi-line block (`InnerConditionalContent`). `inline` is any content
        /// after the colon on the same line.
        case opener(BlockHeader, inline: String)
        /// A lone `}` closing the innermost open block.
        case close
        /// `- <guard>: <inline>`: one branch of the block (`SingleMultilineCondition`).
        case arm(ArmGuard, inline: String)
        /// Anything else: branch content (`StatementsAtLevel(InnerBlock)`).
        case content

        /// How the line moves brace nesting.
        var depthChange: Int {
            switch self {
            case .opener:
                return 1
            case .close:
                return -1
            case .arm, .content:
                return 0
            }
        }

        var isArm: Bool {
            if case .arm = self {
                return true
            }
            return false
        }
    }

    /// The header of a multi-line block — the reference's `initialQueryExpression`.
    private enum BlockHeader {
        /// A bare `{`: no subject, so every arm carries its own guard.
        case none
        /// `{ <subject>:`, as the subject's source text.
        case subject(String)
        /// `{ :` — a colon with nothing before it. inklecate rejects this opener
        /// (`InnerLogic`: "Expected some kind of logic…"), so it is an error
        /// rather than a bare `{` (issue #24).
        case emptySubject
        /// `{stopping:`, `{shuffle once:`, `{&` …: a multi-line sequence, which the
        /// runtime does not support. The reference parses an explicit sequence
        /// annotation before any conditional (`InkParser_Logic.cs`, `InnerLogic`), so
        /// `{once:` is a sequence even when a variable is named `once`.
        case sequence

        var isSequence: Bool {
            if case .sequence = self {
                return true
            }
            return false
        }

        /// The parsed subject, or `nil` for a bare `{`.
        func expression() throws -> InkExpression? {
            guard case .subject(let text) = self else {
                return nil
            }
            return try InkExpressionParser.parse(text)
        }
    }

    /// An arm opener line of a block body, with its guard, and whether the
    /// branch has any content (inline after the guard, or on following lines).
    private typealias ArmLine = (armGuard: ArmGuard, line: BodyLine, hasContent: Bool)

    /// An arm's guard, shaped like the reference's `ConditionalSingleBranch`:
    /// `isElse`, an `ownExpression`, or neither.
    private enum ArmGuard {
        /// `- else:` (`ElseExpression`, `isElse`).
        case otherwise
        /// `- <expr>:` (`ConditionExpression`, `ownExpression`), as source text.
        case condition(String)
        /// A branch with neither: a `-` line whose content is not preceded by
        /// `<expr>:` — `- B`, and also `- : B` or `- Two words: B`, whose colon
        /// is content (issue #23). Under a header with no labelled arm it is the
        /// binary true/else branch; as the final branch, the else.
        case unconditioned

        /// True when the arm is a switch label: it carries its own expression.
        var isLabel: Bool {
            if case .condition = self {
                return true
            }
            return false
        }

        /// True for `- else:`.
        var isElse: Bool {
            if case .otherwise = self {
                return true
            }
            return false
        }

        /// The arm's match expression; `nil` for a default arm.
        func match() throws -> InkExpression? {
            guard case .condition(let text) = self else {
                return nil
            }
            return try InkExpressionParser.parse(text)
        }
    }

    /// Parse `.ink` source into a flat, ordered stream of positioned statements.
    public static func parse(_ source: String) throws -> [InkStatement] {
        var statements: [InkStatement] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var lineIndex = 0
        while lineIndex < lines.count {
            let lineNumber = lineIndex + 1
            let rawLine = lines[lineIndex]
            if let consumed = try CompileError.locating(line: lineNumber, column: leadingColumn(of: rawLine), {
                try appendBlockConditional(lines, from: lineIndex, into: &statements)
            }) {
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
        guard isBlockOpener(afterMarkers) else {
            return nil
        }
        let afterBrace = String(afterMarkers.dropFirst())
        let colonIndex = topLevelColonIndex(in: afterBrace)
        let (header, inline) = blockHeader(afterBrace, colonIndex: colonIndex)
        // A bare `{` opener must have nothing meaningful before the (absent) colon;
        // otherwise this is a single-line `{expr}` that merely lacks a close brace.
        // A symbol-annotated sequence opener (`{&`) also has no colon.
        guard colonIndex != nil || afterBrace.trimmingCharacters(in: .whitespaces).isEmpty
                || header.isSequence else {
            return nil
        }
        // Both opener guards passed — emit the gather header (if a gather marker
        // prefixed the opener) so it is never orphaned by an early `nil` return.
        if let pendingGather {
            statements.append(pendingGather)
        }
        let position = SourcePosition(line: start + 1, column: leadingColumn(of: lines[start]))
        let (body, next) = try collectBlockBody(from: start + 1, count: lines.count) {
            try BodyLine(text: lines[$0].trimmingCharacters(in: .whitespaces), number: $0 + 1)
        }
        let statement = try buildConditionalBlock(
            header: header, bodyLines: try inlineBodyLines(inline, number: start + 1) + body, position: position)
        statements.append(statement)
        return next
    }

    /// True when a trimmed line opens a multi-line block: a `{` with no `}` on
    /// the same line.
    private static func isBlockOpener(_ text: String) -> Bool {
        text.hasPrefix("{") && !text.contains("}")
    }

    /// Classify one trimmed block body line (see `LineShape`).
    private static func lineShape(of text: String) throws -> LineShape {
        if text == "}" {
            return .close
        }
        if isBlockOpener(text) {
            let afterBrace = String(text.dropFirst())
            let (header, inline) = blockHeader(afterBrace, colonIndex: topLevelColonIndex(in: afterBrace))
            return .opener(header, inline: inline)
        }
        if let (armGuard, inline) = try armParts(of: text) {
            return .arm(armGuard, inline: inline)
        }
        return .content
    }

    /// Split the text after a block opener's `{` at its top-level colon: the
    /// header (the subject before the colon), and any content following the
    /// colon inline. With no colon the block is a bare `{`; with nothing before
    /// the colon (`{ :`), an empty subject.
    private static func blockHeader(
        _ afterBrace: String,
        colonIndex: String.Index?
    ) -> (header: BlockHeader, inline: String) {
        guard let colonIndex else {
            return (isSequenceSymbolAnnotation(afterBrace) ? .sequence : .none, "")
        }
        let subject = String(afterBrace[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let inline = String(afterBrace[afterBrace.index(after: colonIndex)...])
            .trimmingCharacters(in: .whitespaces)
        if subject.isEmpty {
            return (.emptySubject, inline)
        }
        return (isSequenceWordAnnotation(subject) ? .sequence : .subject(subject), inline)
    }

    /// The words of a multi-line sequence annotation (`InkParser_Sequences.cs`,
    /// `SequenceTypeSingleWord`), written before the colon: `{stopping:`,
    /// `{shuffle once:`.
    private static let sequenceAnnotationWords: Set<Substring> = ["stopping", "cycle", "shuffle", "once"]

    private static func isSequenceWordAnnotation(_ subject: String) -> Bool {
        let words = subject.split(whereSeparator: { $0 == " " || $0 == "\t" })
        return words.isEmpty == false && words.allSatisfy(sequenceAnnotationWords.contains)
    }

    /// A symbol annotation (`SequenceTypeSymbolAnnotation`: `&` cycle, `!` once,
    /// `~` shuffle, `$` stopping) alone on the opener line, which takes no colon.
    private static func isSequenceSymbolAnnotation(_ afterBrace: String) -> Bool {
        let symbols = afterBrace.filter { $0 != " " && $0 != "\t" }
        return symbols.isEmpty == false && symbols.allSatisfy { "&!~$".contains($0) }
    }

    /// The guard and inline content of a branch line, or `nil` when the line
    /// does not start with `-` (or is a `->` divert). As in the reference
    /// (`SingleMultilineCondition`, with no gather rule at `InnerBlock` level),
    /// every other `-` line opens a branch; its `<expr>:` guard is optional.
    /// Text before the colon that does not parse as an expression is content,
    /// colon included — the reference's `ConditionExpression` fails and the
    /// branch content starts right after the `-` (issue #23).
    private static func armParts(of text: String) throws -> (ArmGuard, inline: String)? {
        guard text.hasPrefix("-"), text.hasPrefix(divertMarker) == false else {
            return nil
        }
        let afterMarker = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard let colonIndex = topLevelColonIndex(in: afterMarker) else {
            return (.unconditioned, afterMarker)
        }
        let guardText = String(afterMarker[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let inline = String(afterMarker[afterMarker.index(after: colonIndex)...])
            .trimmingCharacters(in: .whitespaces)
        if guardText == "else" {
            return (.otherwise, inline)
        }
        guard guardText.isEmpty == false, try InkExpressionParser.parseIfExpression(guardText) != nil else {
            return (.unconditioned, afterMarker)
        }
        return (.condition(guardText), inline)
    }

    /// Content written inline after an opener's colon, as the block's first body line.
    private static func inlineBodyLines(_ inline: String, number: Int) throws -> [BodyLine] {
        inline.isEmpty ? [] : [try BodyLine(text: inline, number: number)]
    }

    /// Collect a block's body lines, starting at `start` (the line after the
    /// opener), up to the `}` that closes it. Nested blocks' lines — their own
    /// `}` included — stay in the body for recursive assembly. Returns the body
    /// and the index just past the closing `}` (or `count` when it is missing).
    private static func collectBlockBody(
        from start: Int,
        count: Int,
        line: (Int) throws -> BodyLine
    ) rethrows -> (body: [BodyLine], next: Int) {
        var body: [BodyLine] = []
        var depth = 0
        var index = start
        while index < count {
            let candidate = try line(index)
            index += 1
            if case .close = candidate.shape, depth == 0 {
                return (body, index)
            }
            depth += candidate.shape.depthChange
            body.append(candidate)
        }
        return (body, index)
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

    /// Assemble a `.conditionalBlock` from the block's header and body lines.
    /// Lines beginning `-` (not `->`) open arms, with or without a `<guard>:`;
    /// other lines are arm content. A block with no arms is a single-guard block
    /// (`{ cond: ...true... }`), so its only arm is guarded by the subject.
    private static func buildConditionalBlock(
        header: BlockHeader,
        bodyLines: [BodyLine],
        position: SourcePosition
    ) throws -> InkStatement {
        if case .emptySubject = header {
            throw syntaxError(
                "Expected some kind of logic, conditional or sequence within braces: { ... } but saw ':'",
                line: position.line
            )
        }
        if header.isSequence {
            throw CompileError(
                kind: .unsupportedConstruct,
                construct: "multi-line sequence",
                message: "Ink multi-line sequence is not supported by the runtime.",
                line: position.line,
                column: position.column
            )
        }
        if hasArmOpenerAtDepth0(bodyLines) {
            return try switchOrGuardedBlock(header: header, bodyLines: bodyLines, position: position)
        }
        return try plainGuardedBlock(header: header, bodyLines: bodyLines, position: position)
    }

    /// How a block's subject relates to its arms: the cases of the reference's
    /// `InnerConditionalContent` (`InkParser_Conditional.cs`).
    private enum BlockForm {
        /// A bare `{`: every arm carries its own guard.
        case headerless
        /// `{ subject: - label: … }`: each label is compared by equality with the
        /// subject; an expression-less final branch is the default.
        case switchOn(InkExpression)
        /// `{ cond: - when true - when false }`: the subject guards the first
        /// branch and the second is the else.
        case binary(InkExpression)
        /// `{ cond: - else: … }`: an empty true branch guarded by the subject,
        /// then the else.
        case elseOnly(InkExpression)
        /// `{ cond: …content… - else: … }`: the subject guards the content before
        /// the first arm, and only a single `- else:` may follow.
        case guardsContent(InkExpression)

        /// The guard of the arm opened before any explicit one, if the form has it.
        var implicitFirstArmMatch: InkExpression? {
            switch self {
            case .elseOnly(let subject), .guardsContent(let subject):
                return subject
            case .headerless, .switchOn, .binary:
                return nil
            }
        }

        /// The match of the explicit arm at `index` with the given guard.
        func match(ofArm armGuard: ArmGuard, at index: Int) throws -> InkExpression? {
            if case .binary(let subject) = self, index == 0 {
                return subject
            }
            return try armGuard.match()
        }
    }

    /// A block whose body has explicit `-` arms, lowered according to its
    /// `BlockForm`: a switch compares the subject with each arm's label; every
    /// other form is a guarded block, each arm tested on its own.
    private static func switchOrGuardedBlock(
        header: BlockHeader,
        bodyLines: [BodyLine],
        position: SourcePosition
    ) throws -> InkStatement {
        let armLines = armLinesAtDepth0(bodyLines)
        let form = try blockForm(header: header, bodyLines: bodyLines, armLines: armLines)
        try checkBranches(armLines, form: form)
        var arms = ArmAccumulator()
        if let implicitMatch = form.implicitFirstArmMatch {
            arms.open(match: implicitMatch)
        }
        var explicitArmCount = 0

        var lineIndex = 0
        while lineIndex < bodyLines.count {
            let line = bodyLines[lineIndex]
            guard case .arm(let armGuard, let inline) = line.shape else {
                lineIndex = try appendBodyUnit(bodyLines: bodyLines, from: lineIndex, into: &arms.pendingBody)
                continue
            }
            if case .guardsContent = form {
                try checkArmAfterHeaderGuardedContent(armGuard, priorArmCount: explicitArmCount, line: line)
            }
            try checkNoGatherDashes(inline, line: line)
            let match = try form.match(ofArm: armGuard, at: explicitArmCount)
            explicitArmCount += 1
            try openExplicitArm(match: match, inline: inline, number: line.number, into: &arms)
            lineIndex += 1
        }
        if case .switchOn(let subject) = form {
            return InkStatement(
                kind: .conditionalBlock(subject: subject, isSwitch: true, branches: arms.finish()),
                position: position
            )
        }
        return InkStatement(
            kind: .conditionalBlock(subject: .boolLiteral(true), isSwitch: false, branches: arms.finish()),
            position: position
        )
    }

    /// Classify a block that has explicit arms. A real switch opens DIRECTLY
    /// with arms (`{ x: - 1: … - 2: … }`): no content precedes the first one. A
    /// guarded if/else carries content right after `{ subject:` (`{ not flag:
    /// …true… - else: …false… }`): the subject is that content's guard, NOT a
    /// switch value. Without this structural test a guarded if/else whose
    /// subject lacked a comparison operator (e.g. `not knot.label`) was misread
    /// as a switch, dropping the content and its condition entirely.
    private static func blockForm(
        header: BlockHeader,
        bodyLines: [BodyLine],
        armLines: [ArmLine]
    ) throws -> BlockForm {
        guard let subject = try header.expression() else {
            return .headerless
        }
        guard bodyLines.first?.shape.isArm ?? false else {
            return .guardsContent(subject)
        }
        if hasLabelledArm(armLines) {
            return .switchOn(subject)
        }
        return armLines.first?.armGuard.isElse == true ? .elseOnly(subject) : .binary(subject)
    }

    /// Whether a block that opens with arms is a switch is STRUCTURAL, as in the
    /// reference (`InkParser_Conditional.cs`, the `initialQueryExpression` loop):
    /// an arm with its own expression matches by equality with the subject,
    /// whatever the subject's type — `{ x == 1: - true: … - false: … }` compares
    /// the boolean `x == 1` to each label (issue #22). A block whose only arm is
    /// `- else:` has no labels to compare: it is binary, an empty true branch
    /// guarded by the subject plus the else. The subject's operators never
    /// decide it; doing so made `- true:` always win under a comparison subject,
    /// and made `{ flag: - else: … }` take the else even when `flag` held.
    private static func hasLabelledArm(_ armLines: [ArmLine]) -> Bool {
        armLines.contains { $0.armGuard.isLabel }
    }

    /// The reference's branch validation for a block of the given form: every
    /// branch without its own expression needs content, and may only sit where
    /// the form allows one. Arms after header-guarded content are checked as
    /// they are opened (`checkArmAfterHeaderGuardedContent`).
    private static func checkBranches(_ armLines: [ArmLine], form: BlockForm) throws {
        try checkBranchesHaveContent(armLines)
        switch form {
        case .headerless:
            try checkHeaderlessBranchesWithoutExpression(armLines)
        case .switchOn, .binary, .elseOnly:
            try checkHeaderBranchesWithoutExpression(armLines)
        case .guardsContent:
            break
        }
    }

    /// Under a header (the `initialQueryExpression` loop), a branch without its
    /// own expression is one of at most two binary branches or the final branch
    /// after a labelled one ("Only final branch can be an 'else'").
    private static func checkHeaderBranchesWithoutExpression(_ armLines: [ArmLine]) throws {
        guard armLines.count > 2,
              let misplaced = armLines.dropLast().first(where: { $0.armGuard.isLabel == false }) else {
            return
        }
        throw syntaxError("Only final branch can be an 'else'. Did you miss a ':'?", line: misplaced.line.number)
    }

    /// Without a header (the headerless loop), only the final branch may lack
    /// an expression. An `- else:` elsewhere is misplaced or repeated (issue
    /// #24); any other such branch "doesn't have condition". The reference
    /// reports a repeated else on the final one, when that is an else too.
    private static func checkHeaderlessBranchesWithoutExpression(_ armLines: [ArmLine]) throws {
        guard let finalArm = armLines.last,
              let misplaced = armLines.dropLast().first(where: { $0.armGuard.isLabel == false }) else {
            return
        }
        if misplaced.armGuard.isElse == false {
            throw syntaxError("Branch doesn't have condition. Are you missing a ':'?", line: misplaced.line.number)
        }
        if finalArm.armGuard.isElse {
            throw syntaxError(
                "Multiple 'else' cases. Can have a maximum of one, at the end.", line: finalArm.line.number)
        }
        throw syntaxError("'else' case in conditional should always be the final one", line: misplaced.line.number)
    }

    /// A branch with neither its own expression nor any content is an error
    /// (`SingleMultilineCondition`); a guarded branch may be left blank
    /// (`- 1:` in a switch), and an else's content may start on a later line.
    private static func checkBranchesHaveContent(_ armLines: [ArmLine]) throws {
        for arm in armLines where arm.armGuard.isLabel == false && arm.hasContent == false {
            throw syntaxError("expected content for the conditional branch following '-'", line: arm.line.number)
        }
    }

    /// Reject a second dash on a branch line (`- - B`): there are no gathers
    /// inside a `{ … }` block, as `StatementsAtLevel(InnerBlock)` reports.
    private static func checkNoGatherDashes(_ inline: String, line: BodyLine) throws {
        guard inline.hasPrefix("-"), inline.hasPrefix(divertMarker) == false else {
            return
        }
        throw syntaxError(
            "You can't use a gather (the dashes) within the { curly braces } context. "
                + "For multi-line sequences and conditions, you should only use one dash.",
            line: line.number
        )
    }

    /// A syntax error reported at the start of a block line, as inklecate does.
    private static func syntaxError(_ message: String, line: Int) -> CompileError {
        CompileError(kind: .syntaxError, message: message, line: line, column: 1)
    }

    /// Open the arm introduced by a `-` branch line with the given match,
    /// seeding its body with any content written inline after the guard.
    private static func openExplicitArm(
        match: InkExpression?,
        inline: String,
        number: Int,
        into arms: inout ArmAccumulator
    ) throws {
        arms.open(match: match)
        if inline.isEmpty == false {
            try appendStatements(from: inline, lineNumber: number, into: &arms.pendingBody)
        }
    }

    /// Collects a block's arms while its body lines are walked: each opened arm
    /// gathers statements until the next one opens. Content before the first
    /// opened arm belongs to no arm and is dropped.
    private struct ArmAccumulator {
        private var branches: [ConditionalBranch] = []
        private var pendingMatch: InkExpression?
        var pendingBody: [InkStatement] = []
        private var armStarted = false

        mutating func open(match: InkExpression?) {
            closePending()
            armStarted = true
            pendingMatch = match
            pendingBody = []
        }

        mutating func finish() -> [ConditionalBranch] {
            closePending()
            armStarted = false
            return branches
        }

        private mutating func closePending() {
            if armStarted {
                branches.append(ConditionalBranch(match: pendingMatch, body: pendingBody))
            }
        }
    }

    /// Reject an else-if chain hung off a header condition (issue #19). When the
    /// header guards the content that follows it (`{ x == 1: One. - else: … }`),
    /// the reference parses that content as the true branch and then accepts at
    /// most ONE further branch, which must be `- else:`
    /// (`InkParser_Conditional.cs`, the `initialQueryExpression` + `soleContent`
    /// path). An extra condition there is a deliberate, named error upstream; a
    /// second branch is never consumed, so the block fails to close. Further
    /// conditions belong in the headerless `{` form, where every condition is an
    /// arm. We match the reference rather than keep the over-acceptance: a story
    /// that compiles here but not under inklecate is silently non-portable.
    private static func checkArmAfterHeaderGuardedContent(
        _ armGuard: ArmGuard,
        priorArmCount: Int,
        line: BodyLine
    ) throws {
        if priorArmCount > 0 {
            throw CompileError(
                kind: .syntaxError,
                message: "Expected closing brace '}' for inline logic but saw '\(line.text)'.",
                line: line.number,
                column: 1
            )
        }
        guard case .otherwise = armGuard else {
            throw CompileError(
                kind: .syntaxError,
                message: "Expected an '- else:' clause here rather than an extra condition. "
                    + "Use a `{` block with every condition as an arm for an else-if chain.",
                line: line.number,
                column: 1
            )
        }
    }

    /// A `{ cond: ...true... }` block with no explicit arms: a single guarded
    /// true-arm and an empty implicit else. Modeled as a guarded block. A bare
    /// `{` with no arms has no condition at all — inklecate rejects it too
    /// ("Branch doesn't have condition" / "Condition block with no conditions").
    private static func plainGuardedBlock(
        header: BlockHeader,
        bodyLines: [BodyLine],
        position: SourcePosition
    ) throws -> InkStatement {
        guard let condition = try header.expression() else {
            throw CompileError(
                kind: .syntaxError,
                message: "Condition block with no conditions: a `{` block needs `- condition:` arms.",
                line: position.line,
                column: position.column
            )
        }
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

    /// True when any body line at brace-nesting depth 0 is an arm opener.
    private static func hasArmOpenerAtDepth0(_ bodyLines: [BodyLine]) -> Bool {
        armLinesAtDepth0(bodyLines).isEmpty == false
    }

    /// The arm openers at brace-nesting depth 0, with their guards. Lines inside
    /// nested `{…}` blocks are at depth > 0 and are excluded so inner block arms
    /// are not mistaken for arms of the enclosing block; they count as content
    /// of the arm they sit in, as does any other non-blank line.
    private static func armLinesAtDepth0(_ bodyLines: [BodyLine]) -> [ArmLine] {
        var depth = 0
        var arms: [ArmLine] = []
        for line in bodyLines {
            if depth == 0, case .arm(let armGuard, let inline) = line.shape {
                arms.append((armGuard, line, inline.isEmpty == false))
            } else if line.text.isEmpty == false, arms.isEmpty == false {
                arms[arms.count - 1].hasContent = true
            }
            depth = max(0, depth + line.shape.depthChange)
        }
        return arms
    }

    /// Process one logical unit from `bodyLines` at `index` into `statements`
    /// and return the next index. A nested block opener is recursively
    /// assembled via `buildConditionalBlock`. Any other line is dispatched to
    /// `appendStatements` as usual.
    private static func appendBodyUnit(
        bodyLines: [BodyLine],
        from index: Int,
        into statements: inout [InkStatement]
    ) throws -> Int {
        let line = bodyLines[index]
        guard case .opener(let header, let inline) = line.shape else {
            try appendStatements(from: line.text, lineNumber: line.number, into: &statements)
            return index + 1
        }
        let position = SourcePosition(line: line.number, column: 1)
        let (body, next) = collectBlockBody(from: index + 1, count: bodyLines.count) { bodyLines[$0] }
        let statement = try buildConditionalBlock(
            header: header, bodyLines: try inlineBodyLines(inline, number: line.number) + body, position: position)
        statements.append(statement)
        return next
    }

    /// Append the statements of one source line. An unlocated `CompileError`
    /// thrown while parsing it (the expression sub-parser sees no source lines)
    /// gets the line's position.
    private static func appendStatements(
        from rawLine: String,
        lineNumber: Int,
        into statements: inout [InkStatement]
    ) throws {
        let position = SourcePosition(line: lineNumber, column: leadingColumn(of: rawLine))
        do {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty == false else {
                return
            }

            try UnsupportedConstructDetector.checkLine(trimmed, at: position)

            if let kind = try headerKind(of: trimmed) {
                statements.append(InkStatement(kind: kind, position: position))
                return
            }
            if let kind = try declarationKind(of: trimmed, at: position) {
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
            if let kind = try weaveKind(of: trimmed) {
                statements.append(InkStatement(kind: kind, position: position))
                return
            }
            try appendContent(from: trimmed, position: position, into: &statements)
        } catch let error as CompileError {
            throw error.located(line: position.line, column: position.column)
        }
    }

    /// Recognise a variable/constant/logic statement. `VAR`/`CONST` declare
    /// globals/constants; `~ temp x = e` declares a local; `~ x = e` reassigns.
    /// The right-hand side is parsed by the Pratt expression sub-parser.
    private static func declarationKind(
        of trimmed: String,
        at position: SourcePosition
    ) throws -> InkStatementKind? {
        if let body = keywordBody(trimmed, keyword: varMarker) {
            let (name, value) = try splitAssignment(body, at: position)
            return .globalVariable(name: name, value: value)
        }
        if let body = keywordBody(trimmed, keyword: constMarker) {
            let (name, value) = try splitAssignment(body, at: position)
            return .constant(name: name, value: value)
        }
        if trimmed.hasPrefix(logicMarker) {
            return try logicKind(of: String(trimmed.dropFirst(logicMarker.count)), at: position)
        }
        return nil
    }

    /// Lower a logic line `~ <body>`: `return e` returns from a function, `temp x
    /// = e` declares a local, `f(args)` calls a function for its side effects
    /// (result discarded), otherwise `x = e` reassigns an existing variable.
    private static func logicKind(
        of body: String,
        at position: SourcePosition
    ) throws -> InkStatementKind {
        let trimmedBody = body.trimmingCharacters(in: .whitespaces)
        if let returnBody = keywordBody(trimmedBody, keyword: returnMarker) {
            return .returnStatement(try InkExpressionParser.parse(returnBody))
        }
        if trimmedBody == returnMarker {
            return .returnStatement(nil)
        }
        if let tempBody = keywordBody(trimmedBody, keyword: tempMarker) {
            let (name, value) = try splitAssignment(tempBody, at: position)
            return .temporaryVariable(name: name, value: value)
        }
        // Only a REAL assignment `=` makes this an assignment. An `=` belonging to
        // a comparison (`==`, `!=`, `>=`, `<=`) or sitting inside a string literal
        // does not — `~ describe(x >= y)` is a call, not an assignment to
        // `"describe(x >"`. The value of an expression statement is discarded by
        // `lowerFunctionCallStatement` (`ev … pop /ev`), so this is safe for any
        // expression, not just a call.
        guard assignmentEqualsIndex(in: trimmedBody) != nil else {
            return .functionCallStatement(try InkExpressionParser.parse(trimmedBody))
        }
        let (name, value) = try splitAssignment(trimmedBody, at: position)
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

    /// The compound-assignment operator characters Ink supports directly before
    /// `=`. Verified against inklecate 1.2.1: `*=`/`/=`/`%=` are NOT accepted by
    /// the reference compiler (`Expected right side of '*' expression but saw
    /// '= ...'`) — only `+=`/`-=` are real Ink syntax.
    private static let compoundAssignmentOperators: Set<Character> = ["+", "-"]

    /// Split a `name = expression` body into the name and the parsed expression.
    /// A compound assignment (`name += expression`, `name -= expression`) is
    /// desugared here into the equivalent full form (`name = name + expression`):
    /// the character immediately before `=` is checked against
    /// `compoundAssignmentOperators` and, if it matches, the parsed right-hand
    /// side is wrapped in a `.binary` node that reads the target variable back.
    /// This reuses the existing simple-assignment and arithmetic codegen paths
    /// rather than introducing a second assignment code path.
    private static func splitAssignment(
        _ body: String,
        at position: SourcePosition
    ) throws -> (name: String, value: InkExpression) {
        guard let equalsIndex = assignmentEqualsIndex(in: body) else {
            throw CompileError(
                kind: .syntaxError,
                message: "Expected an assignment `=` in `\(body)`.",
                line: position.line,
                column: position.column
            )
        }
        let rightHandSide = String(body[body.index(after: equalsIndex)...])
            .trimmingCharacters(in: .whitespaces)
        let beforeEquals = body[..<equalsIndex]

        if let operatorCharacter = beforeEquals.last, assignmentOperatorPrefixes.contains(operatorCharacter) {
            guard compoundAssignmentOperators.contains(operatorCharacter) else {
                throw CompileError(
                    kind: .syntaxError,
                    message: "`\(operatorCharacter)=` is not an Ink assignment operator; "
                        + "only `=`, `+=` and `-=` are supported.",
                    line: position.line,
                    column: position.column
                )
            }
            let name = try assignmentTarget(String(beforeEquals.dropLast()), at: position)
            let addend = try InkExpressionParser.parse(rightHandSide)
            let value = InkExpression.binary(op: String(operatorCharacter), left: .variableReference(name), right: addend)
            return (name, value)
        }

        let name = try assignmentTarget(String(beforeEquals), at: position)
        let value = try InkExpressionParser.parse(rightHandSide)
        return (name, value)
    }

    /// The operator characters that may sit immediately before an assignment `=`.
    /// `+`/`-` desugar (see `compoundAssignmentOperators`); the rest are rejected
    /// with a named error rather than silently producing a bogus target such as
    /// `"x *"`.
    private static let assignmentOperatorPrefixes: Set<Character> = ["+", "-", "*", "/", "%"]

    /// The characters that, immediately BEFORE an `=`, make it part of a
    /// comparison operator (`!=`, `<=`, `>=`, and the second `=` of `==`) rather
    /// than the assignment operator.
    private static let comparisonEqualsPrefixes: Set<Character> = ["!", "<", ">", "="]

    /// The index of the ASSIGNMENT `=` in `body`, or nil when the body contains
    /// none. An `=` is skipped when it belongs to a comparison operator — either
    /// followed by `=` (`==`) or preceded by one of `comparisonEqualsPrefixes` —
    /// or when it sits inside a string literal (`~ f("a=b")`).
    ///
    /// Testing merely for the PRESENCE of `=` (and then splitting at the first
    /// one) misread every logic line carrying a comparison: `~ x >= 5` became an
    /// assignment to `"x >"` and `~ describe(x >= y)` — legal Ink that inklecate
    /// runs — was rejected outright.
    private static func assignmentEqualsIndex(in body: String) -> String.Index? {
        var insideStringLiteral = false
        var previous: Character?
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            if character == "\"" {
                insideStringLiteral.toggle()
            } else if character == "=", insideStringLiteral == false,
                      isAssignmentEquals(at: index, in: body, after: previous) {
                return index
            }
            previous = character
            index = body.index(after: index)
        }
        return nil
    }

    /// True when the `=` at `index` is not part of a comparison operator: not
    /// followed by `=` (`==`) and not preceded by one of `comparisonEqualsPrefixes`.
    private static func isAssignmentEquals(
        at index: String.Index,
        in body: String,
        after previous: Character?
    ) -> Bool {
        let nextIndex = body.index(after: index)
        let followedByEquals = nextIndex < body.endIndex && body[nextIndex] == "="
        let precededByComparison = comparisonEqualsPrefixes.contains(previous ?? " ")
        return followedByEquals == false && precededByComparison == false
    }

    /// Validate and return an assignment target. Ink variable names are plain
    /// identifiers; anything else means the `=` was misread (or the line is
    /// malformed), which previously produced a silently-declared bogus variable
    /// while the intended one kept its old value.
    private static func assignmentTarget(
        _ raw: String,
        at position: SourcePosition
    ) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespaces)
        let isIdentifier = name.first.map { $0.isLetter || $0 == "_" } ?? false
            && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        guard isIdentifier else {
            throw CompileError(
                kind: .syntaxError,
                message: "`\(name)` is not a valid assignment target.",
                line: position.line,
                column: position.column
            )
        }
        return name
    }

    /// Recognise a weave line: a choice (`*`/`+`, once-only/sticky) or a gather
    /// (`-`). The leading marker run gives the weave level; the remainder is the
    /// choice/gather text. `->` is NOT a gather — it is consumed as a divert
    /// before this is reached. Returns `nil` for any non-weave line.
    private static func weaveKind(of trimmed: String) throws -> InkStatementKind? {
        guard let marker = trimmed.first else { return nil }
        if marker == "*" || marker == "+" {
            return try choiceKind(of: trimmed, marker: marker)
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
    private static func choiceKind(of trimmed: String, marker: Character) throws -> InkStatementKind {
        let (level, remainder) = consumeMarkers(trimmed, marker: marker)
        let (weaveLabel, afterLabel) = splitWeaveLabel(remainder)
        let (condition, afterCondition) = try splitChoiceCondition(afterLabel)
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
    private static func splitChoiceCondition(_ remainder: String) throws -> (condition: InkExpression?, rest: String) {
        guard remainder.first == "{",
              let closeIndex = remainder.firstIndex(of: "}") else {
            return (nil, remainder)
        }
        let conditionText = String(remainder[remainder.index(after: remainder.startIndex)..<closeIndex])
            .trimmingCharacters(in: .whitespaces)
        let rest = String(remainder[remainder.index(after: closeIndex)...])
            .trimmingCharacters(in: .whitespaces)
        guard let condition = try InkExpressionParser.parseIfExpression(conditionText) else {
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
        let tokens = ContentTextScanner.scan(remainder, context: .choice)
        guard let open = tokens.first(where: { $0.marker == .bracketOpen }),
              let close = tokens.first(where: { $0.marker == .bracketClose && $0.offset > open.offset }) else {
            return (nil, remainder)
        }
        let characters = Array(remainder)
        let prefix = String(characters[..<open.offset])
        let choiceOnly = String(characters[open.end..<close.offset])
        let suffix = String(characters[close.end...])
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
        if let kind = try declarationKind(of: trimmed, at: position) {
            return InkStatement(kind: kind, position: position)
        }
        // Shortcut plain prose to a `.text` statement, but ONLY when it carries
        // neither an interpolation `{…}` nor a tag `#`. Without `{`, the segment
        // parser can only ever produce literals and tags, so those two markers
        // are exactly the cases that need it.
        //
        // Gating on `{` alone left a choice's post-bracket tag as literal text:
        // `* [Choice A] # sidequest` has the outcome `# sidequest`, which never
        // reached the tag-aware parser and was echoed verbatim into the output
        // (Issue #8). An unrelated `{…}` on the same line masked the defect.
        guard carriesInterpolationOrTag(trimmed) else {
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
        switch GlueMarker.edge(of: trimmed) {
        case .leading(let remainder):
            statements.append(InkStatement(kind: .glue, position: position))
            try appendGluedRemainder(remainder, position: position, into: &statements)
        case .trailing(let prose):
            let text = prose.trimmingCharacters(in: .whitespaces)
            statements.append(InkStatement(kind: .text(text), position: position))
            statements.append(InkStatement(kind: .glue, position: position))
        case .none:
            try appendUngluedContent(trimmed, position: position, into: &statements)
        }
    }

    /// The content after a LEADING `<>`, which glues to the preceding output (the
    /// block conditional body `<>, sipping…` and the post-block `<>.` in
    /// TheIntercept ~161/163): lower the remainder so its prose joins the previous
    /// output line instead of echoing `<>` as literal text. The source
    /// whitespace AFTER `<>` is literal content inklecate preserves (the
    /// post-block `<> You scientists."` at TheIntercept.ink ~1685 lowers to the
    /// oracle text node `^ You scientists.`, a LEADING space). Trimming it would
    /// yield `affairs.You` instead of the oracle's `affairs. You`. So for a
    /// plain-prose remainder, keep the rest VERBATIM; a brace-/divert-/glue-
    /// bearing remainder still re-dispatches through `appendContent` (which
    /// trims) so those constructs are still recognised — symmetric with
    /// `WeaveEmitter.inlineBodyStatements`' leading-`<>` branch.
    private static func appendGluedRemainder(
        _ remainder: String,
        position: SourcePosition,
        into statements: inout [InkStatement]
    ) throws {
        let dispatchable = remainder.trimmingCharacters(in: .whitespaces)
        guard dispatchable.isEmpty == false else {
            return
        }
        if needsContentDispatch(remainder) {
            try appendContent(from: dispatchable, position: position, into: &statements)
        } else {
            statements.append(InkStatement(kind: .text(remainder), position: position))
        }
    }

    /// True when a glued remainder carries a construct `appendContent` must
    /// recognise rather than plain prose: an interpolation, a tag, a divert, or
    /// a trailing glue marker.
    private static func needsContentDispatch(_ remainder: String) -> Bool {
        carriesInterpolationOrTag(remainder)
            || ContentTextScanner.contains(.divert, in: remainder, context: .content)
            || GlueMarker.endsWithGlue(remainder)
    }

    /// True when a content line needs the segment parser: without `{` it can
    /// only ever produce literals and tags, so an interpolation `{…}` or a tag
    /// `#` are exactly the cases that need it.
    private static func carriesInterpolationOrTag(_ text: String) -> Bool {
        ContentTextScanner.scan(text, context: .content).contains { $0.marker == .braceOpen || $0.marker == .hash }
    }

    /// A content line with no glue on either edge: segmented content, prose
    /// followed by a mid-line divert, or plain text.
    private static func appendUngluedContent(
        _ trimmed: String,
        position: SourcePosition,
        into statements: inout [InkStatement]
    ) throws {
        if carriesInterpolationOrTag(trimmed) {
            if ContentTextScanner.contains(.braceOpen, in: trimmed, context: .content) {
                try UnsupportedConstructDetector.check(line: trimmed, lineNumber: position.line)
            }
            let segments = try parseContentSegments(trimmed)
            statements.append(InkStatement(kind: .content(segments), position: position))
            return
        }
        if appendProseThenDivert(trimmed, position: position, into: &statements) {
            return
        }
        statements.append(InkStatement(kind: .text(trimmed), position: position))
    }

    /// A plain prose line carrying a MID-line divert (`Harris looks disapproving.
    /// -> pushes_cup`) splits into the prose text, default divert glue (ink glues
    /// prose to its divert target), and the divert — so the arrow is a real
    /// control-flow divert, not echoed as literal text. A leading-`->` divert is
    /// already handled by the caller before reaching `appendContent`; here the
    /// prefix is non-empty (`range(of:)` finds the arrow past the start).
    /// Returns whether the line had that shape.
    private static func appendProseThenDivert(
        _ trimmed: String,
        position: SourcePosition,
        into statements: inout [InkStatement]
    ) -> Bool {
        guard let arrow = ContentTextScanner.first(.divert, in: trimmed, context: .content), arrow.offset > 0 else {
            return false
        }
        let prose = String(trimmed.prefix(arrow.offset)).trimmingCharacters(in: .whitespaces)
        let target = String(trimmed.dropFirst(arrow.end)).trimmingCharacters(in: .whitespaces)
        let isChain = ContentTextScanner.contains(.divert, in: target, context: .content)
        guard prose.isEmpty == false, target.isEmpty == false, isChain == false else {
            return false
        }
        statements.append(InkStatement(kind: .text(prose), position: position))
        if target == endTarget {
            statements.append(InkStatement(kind: .end, position: position))
        } else {
            statements.append(InkStatement(kind: .glue, position: position))
            statements.append(InkStatement(kind: .divert(target), position: position))
        }
        return true
    }

    /// Split a content line into literal/expression/conditional/tag segments.
    /// Inline groups are delimited by `{` … `}` (an inline-printed expression, or
    /// an inline conditional when the body carries a top-level `:`); a `#` starts
    /// a tag running to the end of the line; everything else is literal text.
    /// Empty literal runs are dropped.
    private static func parseContentSegments(_ line: String) throws -> [ContentSegment] {
        let tokens = ContentTextScanner.scan(line, context: .content)
        var segments: [ContentSegment] = []
        var literal = ""
        var position = 0
        while position < tokens.count {
            switch tokens[position].marker {
            case .braceOpen?:
                appendLiteral(literal, into: &segments)
                literal = ""
                let (segment, next) = try scanBraceSegment(in: tokens, after: position)
                segments.append(segment)
                position = next
            case .hash?:
                // The text before a `#` is emitted untrimmed, as inklecate emits
                // it ("^ after. "): `TrimEndWhitespace` (`InkParser_Content.cs`)
                // only trims the tag text, and the runtime cleans line-end
                // whitespace. Trimming the leading side lost the space in
                // `{n > 0: A} after. # t` (#34).
                appendLiteral(literal, into: &segments)
                segments.append(.tag(tagText(after: tokens[position], in: line)))
                return segments
            default:
                literal += tokens[position].text
                position += 1
            }
        }
        appendLiteral(literal, into: &segments)
        return segments
    }

    /// The text of a tag: everything after its `#` to the end of the line, read
    /// as tag text and trimmed.
    private static func tagText(after hash: ContentTextScanner.Token, in line: String) -> String {
        ContentTextScanner.text(of: String(line.dropFirst(hash.end)), context: .tag)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Scan a `{ … }` group beginning at the brace token at `openPosition`.
    /// Returns the resulting segment and the token position just past the
    /// closing brace. The body runs to the FIRST `}`; nesting is not tracked.
    ///
    /// Classification order matters and mirrors inklecate: a LEADING ALTERNATIVE
    /// MARKER — `!` once, `&` cycle, `\` escape-to-sequence — read after any
    /// leading whitespace, claims the WHOLE body ahead of every other test. Only
    /// an unmarked body is then tested for a top-level `:` (inline conditional
    /// `{ cond: a|b }`), then a top-level `|` (unmarked alternative), and finally
    /// falls through to an inline-printed expression.
    ///
    /// The marker must be tested first because a marked body may legally contain
    /// a `:` (`{!a: x}` is a once-only over the literal stage `"a: x"`, NOT a
    /// conditional on `!a`) or contain neither `:` nor `|` (`{!a}` prints the
    /// stage `"a"`, not the boolean `!a`). Testing `:` first misclassified both.
    ///
    /// Shuffle `~` is deliberately NOT in the marker set: it is rejected upstream
    /// by `UnsupportedConstructDetector`, and claiming it here would silently
    /// downgrade an unsupported shuffle to a plain sequence.
    private static func scanBraceSegment(
        in tokens: [ContentTextScanner.Token],
        after openPosition: Int
    ) throws -> (segment: ContentSegment, next: Int) {
        var position = openPosition + 1
        var body = ""
        while position < tokens.count, tokens[position].marker != .braceClose {
            body += tokens[position].text
            position += 1
        }
        let next = min(position + 1, tokens.count)
        if let markerSegment = leadingAlternativeSegment(body) {
            return (markerSegment, next)
        }
        if let colonIndex = topLevelColonIndex(in: body) {
            return (try inlineConditionalSegment(body, colonIndex: colonIndex), next)
        }
        if topLevelBarIndex(in: body) != nil {
            return (variableTextSegment(body), next)
        }
        let expression = try InkExpressionParser.parse(body.trimmingCharacters(in: .whitespaces))
        return (.expression(expression), next)
    }

    /// The characters that, in leading position, mark a brace body as a
    /// variable-text alternative. Deliberately excludes shuffle `~` — see
    /// `scanBraceSegment`.
    private static let alternativeMarkers: Set<Character> = ["!", "&", "\\"]

    /// Build a variable-text segment when `body` opens with an alternative
    /// marker, skipping any leading whitespace so `{ !a: q }` classifies exactly
    /// like `{!a: q}` (verified against inklecate). Returns nil for an unmarked
    /// body, which then falls through to the conditional / bar / expression
    /// tests in `scanBraceSegment`.
    private static func leadingAlternativeSegment(_ body: String) -> ContentSegment? {
        guard let markerIndex = body.firstIndex(where: { !$0.isWhitespace }),
              alternativeMarkers.contains(body[markerIndex]) else {
            return nil
        }
        return variableTextSegment(String(body[markerIndex...]))
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
    ///
    /// PROBE for 05-02 (escape-aware mode): this reads a leading `\` as a
    /// body-level "escape-to-sequence" marker, unlike inklecate. There
    /// `ContentTextAllowingEcapeChar` makes ANY `\x` in a stage the literal
    /// `x`; an escape is a property of the content run, not of the body, and
    /// only the first one is handled here (`{a|\|b}` still splits at the
    /// escaped bar, `{\!a|b\!}` keeps the second backslash). Because `\` is
    /// in `alternativeMarkers`, `{\x}` is a one-stage sequence even with no
    /// top-level `|`. Once the scanner unescapes, `{\!a|b}` would reach here as
    /// `!a|b` and be misread as a once-only: 05-02 must classify the mode on
    /// the scanner's tokens (an escaped first character is no marker) and drop
    /// `\` from `alternativeMarkers`.
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
        for token in ContentTextScanner.scan(body, context: .content) {
            depth += token.braceDepthChange
            if token.marker == .bar && depth == 0 {
                stages.append(current)
                current = ""
                continue
            }
            current += token.text
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
        topLevelIndex(of: barCharacter, in: body)
    }

    /// The variable-text and inline-branch separator, as the scanner defines it.
    private static let barCharacter = Character(ContentTextScanner.Marker.bar.text)

    /// Index of the first `target` at brace-nesting depth 0. Depth changes only
    /// at brace markers, so a run is searched whole at its depth.
    private static func topLevelIndex(of target: Character, in body: String) -> String.Index? {
        var depth = 0
        for token in ContentTextScanner.scan(body, context: .content) {
            depth += token.braceDepthChange
            guard depth == 0, let offset = token.text.firstIndex(of: target) else { continue }
            let offsetInBody = token.offset + token.text.distance(from: token.text.startIndex, to: offset)
            return body.index(body.startIndex, offsetBy: offsetInBody)
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
