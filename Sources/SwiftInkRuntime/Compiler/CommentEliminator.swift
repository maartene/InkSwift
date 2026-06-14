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
                index = next
                continue
            }

            if insideString {
                output.append(character)
                if character == "\"" {
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
