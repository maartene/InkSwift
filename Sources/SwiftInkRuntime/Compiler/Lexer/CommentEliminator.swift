// First stage of the native compile pipeline (DDD-10): strip Ink comments
// before parsing.
//
// Deliberately NOT string-literal aware, mirroring the reference implementation
// (`compiler/InkParser/CommentEliminator.cs` in inkle/ink), whose
// `EndOfLineComment`/`BlockComment` rules strip unconditionally with no notion
// of quoting. Ink really does eliminate comments before it has any concept of a
// string literal, so `~ url = "http://example.com"` is a compile error upstream
// ("Expected close quote for string expression but saw end of line") rather than
// a preserved URL — verified against inklecate 1.2.1.
//
// Tracking quote state here instead made comment recognition depend on the
// cumulative parity of every `"` earlier in the (possibly multi-file
// concatenated) source: one stray quote in ordinary content text — say a closing
// ASCII `"` paired with a typographic opener like `„` — left the flag stuck and
// silently preserved every later comment verbatim.
//
// Escapes need no handling here either: `\/\/` survives because its slashes are
// not adjacent, and the main parser resolves the escapes afterwards.

import Foundation

enum CommentEliminator {

    /// Remove `//` line comments and `/* */` block comments from `source`.
    ///
    /// Newlines inside stripped comments are preserved so downstream source
    /// positions keep pointing at the right line.
    static func strip(_ source: String) -> String {
        var output = ""
        output.reserveCapacity(source.count)

        var index = source.startIndex
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
