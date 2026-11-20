// Reject-list detection for the native Ink compiler (DDD-8): variable-text
// alternative constructs share the `{…|…}` syntax and are outside the runtime's
// supported set (matrix rows 25-28). This detector runs during the inline scan
// and short-circuits with a located, construct-named `.unsupportedConstruct`
// error BEFORE any codegen — fail-closed, no partial story (D2 / KPI #2).
//
// The four forms are distinguished by the marker leading the brace group:
//   {a|b|c}   plain alternatives, no top-level `:`  → "sequence"
//   {&a|b}    leading `&`                            → "cycle"
//   {!a|b}    leading `!` (optionally escaped `\!`)  → "once"
//   {~a|b}    leading `~`                            → "shuffle {~a|b}"
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

    /// The unsupported built-ins whose argument is a divert target (`-> knot`),
    /// by source name, with their catalog name. The expression parser cannot
    /// read a divert target, so they are refused at the call, before the argument.
    private static let divertTargetBuiltIns: [String: String] = Dictionary(
        uniqueKeysWithValues: NativeFunctionCatalog.entries.compactMap { entry in
            guard ["TURNS_SINCE", "READ_COUNT"].contains(entry.sourceName),
                  case .unsupported(let feature) = entry.status else { return nil }
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
        guard unescapedIndex(of: "{", in: Substring(contents)) != nil else { return }
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
        guard let (hash, insideLogic) = firstTag(in: trimmed) else { return }
        let construct: String
        if insideLogic {
            construct = "tag inside inline logic"
        } else if unescapedIndex(of: "{", in: trimmed[hash...]) != nil {
            construct = "tag with inline logic"
        } else {
            return
        }
        throw CompileError(
            kind: .unsupportedConstruct,
            construct: construct,
            message: "A \(construct) is not supported by the native compiler yet.",
            line: lineNumber,
            column: column + trimmed.distance(from: trimmed.startIndex, to: hash)
        )
    }

    /// The first unescaped `#` in `line`, and whether it sits inside a `{…}`
    /// group, or `nil` when the line has no tag.
    private static func firstTag(in line: String) -> (hash: String.Index, insideLogic: Bool)? {
        var depth = 0
        var index = line.startIndex
        while index < line.endIndex {
            switch line[index] {
            case "\\":
                index = line.index(after: index)
                if index == line.endIndex { return nil }
            case "{":
                depth += 1
            case "}":
                depth = max(0, depth - 1)
            case "#":
                return (index, depth > 0)
            default:
                break
            }
            index = line.index(after: index)
        }
        return nil
    }

    /// The first `character` in `text` not escaped by a preceding `\`.
    private static func unescapedIndex(of character: Character, in text: Substring) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\\" {
                index = text.index(after: index)
                if index == text.endIndex { return nil }
            } else if text[index] == character {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Inspect the inline `{…}` groups of `line`. If one is a variable-text
    /// alternative (sequence / cycle / once / shuffle), throw a located
    /// `.unsupportedConstruct` naming it. Returns normally when none is present.
    static func check(line: String, lineNumber: Int) throws {
        var index = line.startIndex
        while index < line.endIndex {
            guard line[index] == "{" else {
                index = line.index(after: index)
                continue
            }
            let group = scanBraceGroup(in: line, openIndex: index)
            if let construct = variableTextConstruct(of: group.body) {
                let column = line.distance(from: line.startIndex, to: index) + 1
                throw CompileError(
                    kind: .unsupportedConstruct,
                    construct: construct,
                    message: "Variable-text \(construct) is not supported.",
                    line: lineNumber,
                    column: column
                )
            }
            index = group.next
        }
    }

    /// Scan a brace group beginning at `openIndex`, tracking brace nesting so a
    /// nested `{…}` does not terminate the outer group. Returns the inner body
    /// (without the outer braces) and the index just past the closing brace.
    private static func scanBraceGroup(
        in line: String,
        openIndex: String.Index
    ) -> (body: String, next: String.Index) {
        var depth = 0
        var body = ""
        var index = openIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "{" {
                depth += 1
                if depth > 1 {
                    body.append(character)
                }
                index = line.index(after: index)
                continue
            }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return (body, line.index(after: index))
                }
                body.append(character)
                index = line.index(after: index)
                continue
            }
            body.append(character)
            index = line.index(after: index)
        }
        return (body, index)
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
