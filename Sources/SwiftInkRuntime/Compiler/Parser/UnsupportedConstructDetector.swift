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
//   {~a|b}    leading `~`                            → "shuffle"
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
    /// `RANDOM(`/`SEED_RANDOM(` calls, `EXTERNAL` declaration, and `INCLUDE`. Throws a
    /// located `.unsupportedConstruct` naming the construct so the statement scan
    /// short-circuits BEFORE any StoryBlueprint is built (fail-closed). The
    /// `line` is the whitespace-trimmed statement; `column` is its leading column.
    static func checkStatement(line trimmed: String, lineNumber: Int, column: Int) throws {
        guard let construct = statementConstruct(of: trimmed) else { return }
        throw CompileError(
            kind: .unsupportedConstruct,
            construct: construct,
            message: "Ink \(construct) is not supported by the runtime.",
            line: lineNumber,
            column: column
        )
    }

    /// Name the statement-level unsupported construct of a trimmed statement, or
    /// `nil` when the statement uses no such construct. Threads/LIST/EXTERNAL/INCLUDE are
    /// recognised by their leading keyword; RANDOM by its call appearing anywhere
    /// in an expression (e.g. on a `~ temp x = RANDOM(...)` right-hand side).
    private static func statementConstruct(of trimmed: String) -> String? {
        if trimmed.hasPrefix("<-") {
            return "thread"
        }
        if keyword(trimmed, isLeading: "LIST") {
            return "list"
        }
        if keyword(trimmed, isLeading: "EXTERNAL") {
            return "external"
        }
        if keyword(trimmed, isLeading: "INCLUDE") {
            return "include"
        }
        if containsRandomCall(trimmed) {
            return "random"
        }
        return nil
    }

    /// True when `trimmed` begins with `keyword` followed by whitespace, so
    /// `LISTING` is not mistaken for `LIST` and `EXTERNALITY` not for `EXTERNAL`.
    private static func keyword(_ trimmed: String, isLeading keyword: String) -> Bool {
        guard trimmed.hasPrefix(keyword) else { return false }
        let remainder = trimmed.dropFirst(keyword.count)
        guard let first = remainder.first else { return false }
        return first == " " || first == "\t"
    }

    /// True when the line contains a `RANDOM(` call (case-insensitive). This also
    /// matches `SEED_RANDOM(`, since `RANDOM(` is its trailing substring.
    private static func containsRandomCall(_ trimmed: String) -> Bool {
        trimmed.range(of: "RANDOM(", options: .caseInsensitive) != nil
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

    /// Reject a tag that carries inline logic (`Line # pic{n}.jpg`, `# {a|b}`)
    /// on any statement line: content, choice, gather or tag-only, and inside a
    /// conditional arm (`{x: A # t{n}}`). inklecate evaluates the logic into the
    /// tag; the native compiler would keep it as literal text (issue #31). The
    /// error points at the tag's `#`.
    static func checkTag(line trimmed: String, lineNumber: Int, column: Int) throws {
        guard let hash = startOfTagWithLogic(in: trimmed) else { return }
        throw CompileError(
            kind: .unsupportedConstruct,
            construct: "tag with inline logic",
            message: "A tag with inline logic (`# …{…}…`) is not supported by the native compiler yet.",
            line: lineNumber,
            column: column + trimmed.distance(from: trimmed.startIndex, to: hash)
        )
    }

    /// The `#` of the first tag that holds a `{`, or `nil` when no tag does.
    /// A tag runs from an unescaped `#` to the end of its scope: the end of the
    /// line at the top level, or, inside a `{…}` group, the `|` or `}` that ends
    /// the arm it sits in. So `{x: A # t}{n}` holds a static tag followed by an
    /// interpolation, as in inklecate; only a `{` inside the tag itself counts.
    private static func startOfTagWithLogic(in line: String) -> String.Index? {
        var scope = TagScope()
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == "\\" {
                index = line.index(after: index)
                if index == line.endIndex { return nil }
            } else if let tagStart = scope.read(line[index], at: index) {
                return tagStart
            }
            index = line.index(after: index)
        }
        return nil
    }

    /// Where a line scan stands: its `{…}` depth, and the tag it is in, if any.
    private struct TagScope {
        private var depth = 0
        private var tag: (start: String.Index, depth: Int)?

        /// Read one unescaped character. Returns the tag's `#` when the
        /// character is a `{` inside that tag.
        mutating func read(_ character: Character, at index: String.Index) -> String.Index? {
            switch character {
            case "{":
                if let tag { return tag.start }
                depth += 1
            case "}":
                depth = max(0, depth - 1)
                endTag { tagDepth, depth in depth < tagDepth }
            case "|":
                endTag { tagDepth, depth in tagDepth > 0 && depth == tagDepth }
            case "#" where tag == nil || tag?.depth == depth:
                tag = (index, depth)
            default:
                break
            }
            return nil
        }

        /// End the current tag when `ends` holds for the depth it started at
        /// and the current depth.
        private mutating func endTag(where ends: (_ tagDepth: Int, _ depth: Int) -> Bool) {
            if let open = tag, ends(open.depth, depth) { tag = nil }
        }
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
                    message: "Variable-text \(construct) `{…|…}` is not supported.",
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

    /// Map a leading `~` marker (a leading `\` escape is skipped) to "shuffle".
    /// Returns `nil` for every other leading character — `&` cycle, `!` once, and
    /// the no-marker sequence form are now SUPPORTED and lowered by the compiler,
    /// so only shuffle short-circuits here.
    private static func leadingMarker(of trimmed: String) -> String? {
        var characters = Substring(trimmed)
        if characters.first == "\\" {
            characters = characters.dropFirst()
        }
        switch characters.first {
        case "~": return "shuffle"
        default: return nil
        }
    }
}
