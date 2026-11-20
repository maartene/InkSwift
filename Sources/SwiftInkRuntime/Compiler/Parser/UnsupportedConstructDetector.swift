// Reject-list detection for the native Ink compiler (DDD-8). It runs during the
// statement and inline scans and short-circuits with a located, construct-named
// `.unsupportedConstruct` error BEFORE any codegen — fail-closed, no partial
// story (D2 / KPI #2). It refuses the statement-level constructs (threads,
// LIST, EXTERNAL, INCLUDE, divert-target built-ins), the tag and string shapes
// of #31, and one variable-text form.
//
// Variable-text alternatives share the `{…|…}` syntax; the marker leading the
// brace group names the form:
//   {a|b|c}   plain alternatives, no top-level `:`  → sequence, supported
//   {&a|b}    leading `&`                            → cycle, supported
//   {!a|b}    leading `!` (optionally escaped `\!`)  → once, supported
//   {~a|b}    leading `~`                            → "shuffle {~a|b}", refused
//
// Inline conditionals `{cond: a|b}` (S4) also use `|`, but carry a top-level
// `:` before the alternatives — the `:` discriminates them so supported forms
// are never mis-rejected. Plain interpolation `{x}` has no top-level `|`.

import Foundation

/// Detects variable-text alternative sequences in a content line and reports
/// the first one as an unsupported construct. Stateless; called per content line.
enum UnsupportedConstructDetector {

    /// Inspect a whole statement `line` for a statement-level unsupported
    /// construct (matrix rows 36-39, 41): thread `<- knot`, `LIST` declaration,
    /// `EXTERNAL` declaration, `INCLUDE`, and a call of a built-in that takes a
    /// divert target. Throws a located `.unsupportedConstruct` under the
    /// catalog's name, the one the runtime refuses the feature by, so the
    /// statement scan short-circuits BEFORE any StoryBlueprint is built
    /// (fail-closed). The `line` is the whitespace-trimmed statement; `column`
    /// is its leading column.
    static func checkStatement(line trimmed: String, lineNumber: Int, column: Int) throws {
        guard let (construct, offset) = statementConstruct(of: trimmed) ?? divertTargetBuiltInCall(in: trimmed) else {
            return
        }
        throw CompileError(
            kind: .unsupportedConstruct,
            construct: construct,
            message: "Ink \(construct) is not supported by the runtime.",
            line: lineNumber,
            column: column + offset
        )
    }

    /// Name the statement-level unsupported construct of a trimmed statement,
    /// which starts the statement, or `nil` when the statement uses no such
    /// construct. Each is recognised by its leading arrow or keyword.
    private static func statementConstruct(of trimmed: String) -> (construct: String, offset: Int)? {
        if trimmed.hasPrefix("<-") {
            return (UnsupportedConstruct.thread.name, 0)
        }
        return UnsupportedConstruct.allCases.first { opens(trimmed, with: $0) }.map { ($0.name, 0) }
    }

    /// True when `trimmed` begins with the construct's keyword followed by
    /// whitespace, so `LISTING` is not mistaken for `LIST` and `EXTERNALITY` not
    /// for `EXTERNAL`.
    private static func opens(_ trimmed: String, with construct: UnsupportedConstruct) -> Bool {
        guard let keyword = construct.statementKeyword, trimmed.hasPrefix(keyword) else { return false }
        let remainder = trimmed.dropFirst(keyword.count)
        return remainder.first == " " || remainder.first == "\t"
    }

    /// The unsupported built-ins the catalog flags as taking a divert target
    /// (`-> knot`), by source name, with their catalog name. The expression
    /// parser cannot read a divert target, so they are refused at the call,
    /// before the argument.
    private static let divertTargetBuiltIns: [String: String] = Dictionary(
        uniqueKeysWithValues: NativeFunctionCatalog.entries.compactMap { entry in
            guard entry.takesDivertTarget, case .unsupported(let feature) = entry.status else { return nil }
            return (entry.sourceName, feature)
        })

    /// The first call of a divert-target built-in in `trimmed`, as its feature
    /// name and the call's offset from the start of the statement. Only a whole
    /// identifier counts: `MY_TURNS_SINCE(` is a different function.
    private static func divertTargetBuiltInCall(in trimmed: String) -> (construct: String, offset: Int)? {
        var identifier = ""
        for (offset, character) in trimmed.enumerated() {
            let isAlphanumeric = character.isLetter || character.isNumber
            if isAlphanumeric || "_.".contains(character) {
                identifier.append(character)
                continue
            }
            if character == "(", let feature = divertTargetBuiltIns[identifier] {
                return (feature, offset - identifier.count)
            }
            identifier = ""
        }
        return nil
    }

    /// Run every statement-level check on one trimmed source line: the
    /// unsupported statements (`checkStatement`) and tags with inline logic
    /// (`checkTag`).
    static func checkLine(_ trimmed: String, at position: SourcePosition) throws {
        try checkStatement(line: trimmed, lineNumber: position.line, column: position.column)
        try checkTag(line: trimmed, lineNumber: position.line, column: position.column)
    }

    /// Reject a string literal in logic that carries inline logic
    /// (`~ return "value {n}"`). inklecate builds such a string at runtime
    /// (`str … out … /str`); the native compiler would keep the braces as literal
    /// text (issue #31). The expression sub-parser sees no source lines, so the
    /// error is unlocated; `InkParser` fills in the statement's position.
    /// `contents` is the literal's raw text, escape pairs (`\{`) still in place.
    static func checkStringLiteral(_ contents: String) throws {
        guard ContentTextScanner.scan(contents, context: .string).contains(where: { $0.marker == .braceOpen }) else { return }
        throw CompileError(
            kind: .unsupportedConstruct,
            construct: "string with inline logic",
            message: "A string literal with inline logic (`\"…{…}…\"`) is not supported by the native compiler yet."
        )
    }

    /// Reject the two tag shapes the native compiler would keep as literal text
    /// (issue #31), on any statement line: content, choice, gather or
    /// tag-only. The error points at the tag's `#`.
    ///
    /// - A tag inside inline logic: a `#` within a `{…}` group, i.e. in an inline
    ///   conditional arm (`{x: A # t}`) or a sequence alternative (`{A # t|B}`).
    ///   inklecate reads every unescaped `#` there as a tag, even inside quoted
    ///   prose; inside a string literal it is a compile error.
    /// - A tag with inline logic: a top-level tag, which runs to the end of the
    ///   line, holding a `{` (`Line # pic{n}.jpg`, `# {a|b}`).
    static func checkTag(line trimmed: String, lineNumber: Int, column: Int) throws {
        let tokens = ContentTextScanner.scan(trimmed, context: .content)
        guard let (hash, insideLogic) = firstTag(in: tokens) else { return }
        let construct: String
        if insideLogic {
            construct = "tag inside inline logic"
        } else if tokens.contains(where: { $0.marker == .braceOpen && $0.offset > hash.offset }) {
            construct = "tag with inline logic"
        } else {
            return
        }
        throw CompileError(
            kind: .unsupportedConstruct,
            construct: construct,
            message: "A \(construct) is not supported by the native compiler yet.",
            line: lineNumber,
            column: column + hash.offset
        )
    }

    /// The first unescaped `#` in the scanned line, and whether it sits inside a
    /// `{…}` group, or `nil` when the line has no tag.
    private static func firstTag(in tokens: [ContentTextScanner.Token]) -> (hash: ContentTextScanner.Token, insideLogic: Bool)? {
        var depth = 0
        for token in tokens {
            if token.marker == .hash {
                return (token, depth > 0)
            }
            depth = max(0, depth + token.braceDepthChange)
        }
        return nil
    }

    /// Inspect the inline `{…}` groups of `line`. If one is a variable-text
    /// alternative (sequence / cycle / once / shuffle), throw a located
    /// `.unsupportedConstruct` naming it. Returns normally when none is present.
    static func check(line: String, lineNumber: Int) throws {
        let tokens = ContentTextScanner.scan(line, context: .content)
        var position = 0
        while position < tokens.count {
            guard tokens[position].marker == .braceOpen else {
                position += 1
                continue
            }
            let group = scanBraceGroup(in: tokens, openPosition: position)
            if let construct = variableTextConstruct(of: group.body) {
                throw CompileError(
                    kind: .unsupportedConstruct,
                    construct: construct,
                    message: "Variable-text \(construct) is not supported.",
                    line: lineNumber,
                    column: tokens[position].offset + 1
                )
            }
            position = group.next
        }
    }

    /// Scan a brace group beginning at the `{` token at `openPosition`, tracking
    /// brace nesting so a nested `{…}` does not terminate the outer group.
    /// Returns the inner body (without the outer braces) and the token position
    /// just past the closing brace.
    private static func scanBraceGroup(
        in tokens: [ContentTextScanner.Token],
        openPosition: Int
    ) -> (body: String, next: Int) {
        var depth = 1
        var body = ""
        var position = openPosition + 1
        while position < tokens.count {
            depth += tokens[position].braceDepthChange
            if depth == 0 {
                return (body, position + 1)
            }
            body += tokens[position].text
            position += 1
        }
        return (body, position)
    }

    /// Name the variable-text construct of a brace-group body, or `nil` when the
    /// body is a SUPPORTED form (sequence / cycle / once, all lowered by
    /// VariableTextEmitter as of slice-01) or a supported interpolation/conditional.
    /// Only shuffle `{~a|b}` remains unsupported — the gate is now shuffle-only
    /// (DDD-5 / DISTILL U-2): deterministic alternatives compile.
    private static func variableTextConstruct(of body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        return leadingMarker(of: trimmed)
    }

    /// Map a leading `~` marker (a leading `\` escape is skipped) to the
    /// catalog's shuffle name.
    /// Returns `nil` for every other leading character — `&` cycle, `!` once, and
    /// the no-marker sequence form are now SUPPORTED and lowered by the compiler,
    /// so only shuffle short-circuits here.
    private static func leadingMarker(of trimmed: String) -> String? {
        var characters = Substring(trimmed)
        if characters.first == "\\" {
            characters = characters.dropFirst()
        }
        switch characters.first {
        case "~": return UnsupportedConstruct.shuffle.name
        default: return nil
        }
    }
}
