// Second stage of the native compile pipeline (DDD-10): turn sanitized Ink
// source into the parsed units the codegen consumes. At S0 the only construct
// is plain text, so parsing is a trivial line split; the full stateful
// cursor/combinator engine lands in 01-01. Kept minimal but real.

import Foundation

enum StringParser {

    /// Split sanitized source into its plain-text lines, dropping a single
    /// trailing newline so a one-line source yields exactly one line. An empty
    /// (or whitespace-only) source yields no lines.
    static func parseLines(_ source: String) -> [String] {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return []
        }
        return trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
