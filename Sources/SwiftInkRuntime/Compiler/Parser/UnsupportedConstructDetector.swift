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
    /// construct (matrix rows 36-39): thread `<- knot`, `LIST` declaration,
    /// `RANDOM(`/`SEED_RANDOM(` calls, and `EXTERNAL` declaration. Throws a
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
    /// `nil` when the statement uses no such construct. Threads/LIST/EXTERNAL are
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
