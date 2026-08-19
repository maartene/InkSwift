// First stage of the native compile pipeline (DDD-10): strip Ink comments
// before parsing. String-literal aware so `//` or `/* */` appearing inside a
// double-quoted string is preserved verbatim. Minimal but real — for S0
// plain-text fixtures it is effectively a pass-through.

import Foundation

enum CommentEliminator {

    /// Remove `//` line comments and `/* */` block comments from `source`,
    /// leaving comment-like sequences inside double-quoted string literals intact.
    static func strip(_ source: String) -> String {
        var output = ""
        output.reserveCapacity(source.count)

        var index = source.startIndex
        var insideString = false
        var insideLineComment = false
        var insideBlockComment = false

        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            let following: Character? = next < source.endIndex ? source[next] : nil

            if insideLineComment {
                if character == "\n" {
                    insideLineComment = false
                    output.append(character)
                }
                index = next
                continue
            }

            if insideBlockComment {
                if character == "*" && following == "/" {
                    insideBlockComment = false
                    index = source.index(after: next)
                    continue
                }
                // Preserve newlines so downstream source positions stay accurate
                // even across a multi-line block comment.
                if character == "\n" {
                    output.append(character)
                }
                index = next
                continue
            }

            if insideString {
                output.append(character)
                if character == "\\" {
                    // The backslash escapes the next character (an escaped quote
                    // or escaped backslash), so copy it through verbatim and let
                    // it never act as a string terminator.
                    if let escaped = following {
                        output.append(escaped)
                        index = source.index(after: next)
                        continue
                    }
                }
                if character == "\"" {
                    insideString = false
                } else if character == "\n" {
                    // A genuine Ink string literal never spans a line break —
                    // verified against inklecate 1.2.1, which rejects one with
                    // "Expected close quote for string expression but saw end of
                    // line". So reaching a newline still `insideString` means the
                    // opening quote was never a real string literal to begin
                    // with: ordinary content text is not tokenised as containing
                    // string literals at all in Ink, and a bare `"` there is just
                    // punctuation (e.g. a closing quotation mark paired with a
                    // typographic opener the lexer doesn't recognise, such as the
                    // German „). Treating that stray quote as having opened a
                    // string that stays open indefinitely made comment
                    // recognition depend on the total count of unrelated quote
                    // characters anywhere earlier in the (possibly
                    // multi-file-concatenated) source — resetting here confines
                    // the false positive to the single line it occurred on.
                    insideString = false
                }
                index = next
                continue
            }

            if character == "\"" {
                insideString = true
                output.append(character)
                index = next
                continue
            }

            if character == "/" && following == "/" {
                insideLineComment = true
                index = source.index(after: next)
                continue
            }

            if character == "/" && following == "*" {
                insideBlockComment = true
                index = source.index(after: next)
                continue
            }

            output.append(character)
            index = next
        }

        return output
    }
}
