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
    /// body is a supported interpolation/conditional rather than an alternative.
    private static func variableTextConstruct(of body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        if let marker = leadingMarker(of: trimmed) {
            return marker
        }
        if hasTopLevelAlternation(trimmed) && hasTopLevelColon(trimmed) == false {
            return "sequence"
        }
        return nil
    }

    /// Map a leading `&`/`!`/`~` marker (a leading `\` escape is skipped) to its
    /// construct name. Returns `nil` when the body starts with no such marker.
    private static func leadingMarker(of trimmed: String) -> String? {
        var characters = Substring(trimmed)
        if characters.first == "\\" {
            characters = characters.dropFirst()
        }
        switch characters.first {
        case "&": return "cycle"
        case "!": return "once"
        case "~": return "shuffle"
        default: return nil
        }
    }

    /// True when the body has a `|` at brace-nesting depth 0 (an alternation
    /// separator), ignoring `|` inside any nested `{…}`.
    private static func hasTopLevelAlternation(_ body: String) -> Bool {
        topLevel(body, contains: "|")
    }

    /// True when the body has a `:` at brace-nesting depth 0 (the inline
    /// conditional discriminator), ignoring `:` inside any nested `{…}`.
    private static func hasTopLevelColon(_ body: String) -> Bool {
        topLevel(body, contains: ":")
    }

    private static func topLevel(_ body: String, contains target: Character) -> Bool {
        var depth = 0
        for character in body {
            if character == "{" {
                depth += 1
                continue
            }
            if character == "}" {
                depth -= 1
                continue
            }
            if character == target && depth == 0 {
                return true
            }
        }
        return false
    }
}
