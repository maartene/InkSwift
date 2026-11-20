//
//  ContentTextScanner.swift
//  InkSwift
//
//  The one content-text rule of the native compiler (ADR-026).
//

/// Splits content text into literal runs and structural markers, the way
/// inklecate's `ContentTextAllowingEcapeChar` over `ContentTextNoEscape` reads
/// it (`InkParser_Content.cs:117-199`, upstream spelling): text runs until a
/// stop character of the current context, and `->` and `<>` pause it as the
/// divert arrow and glue.
///
/// Stop sets per context:
/// - content and tag: `{ } | #` and a newline;
/// - choice: content plus `[ ]`;
/// - string: content plus `"`.
///
/// Every token carries its source offset (in characters) and source length,
/// so a consumer can locate it in the text it scanned.
///
/// A backslash escapes the character after it, as in inklecate (#35): `\x` is
/// the literal `x` in a run and never a stop. A lone trailing `\` is text.
///
/// Thread arrows `<-` are not a marker yet: no consumer splits on them, and
/// making `<-` a marker would change how `<->` reads.
enum ContentTextScanner {

    /// Which text is being scanned; selects the stop set.
    enum Context: CaseIterable, Sendable {
        case content, choice, string, tag
    }

    /// A structural character (or pair) that stops a literal run.
    enum Marker: Equatable, Sendable {
        case braceOpen, braceClose, bar, hash, newline
        case glue, divert
        case bracketOpen, bracketClose, quote

        /// The source text of a two-character marker.
        var text: String {
            switch self {
            case .glue: return "<>"
            case .divert: return "->"
            default: return ContentTextScanner.singleMarkerText[self] ?? ""
            }
        }
    }

    /// A literal run (`marker == nil`) or a marker, located in the source.
    struct Token: Equatable, Sendable {
        /// The marker, or `nil` for a literal run.
        let marker: Marker?
        /// The token's text: a marker's source text, or a run's unescaped text.
        let text: String
        /// Offset of the token's first source character.
        let offset: Int
        /// Number of source characters the token spans.
        let length: Int

        /// Offset just past the token in the source.
        var end: Int { offset + length }

        /// The source text the token spans, escape pairs intact.
        func source(in characters: [Character]) -> String {
            String(characters[offset..<end])
        }

        /// `+1` for `{`, `-1` for `}`, `0` otherwise.
        var braceDepthChange: Int {
            switch marker {
            case .braceOpen?: return 1
            case .braceClose?: return -1
            default: return 0
            }
        }
    }

    // MARK: - Scanning

    /// Scan `text` in `context` into literal runs and markers.
    static func scan(_ text: String, context: Context) -> [Token] {
        var cursor = Cursor(characters: Array(text), context: context)
        return cursor.scanAll()
    }

    /// The escape primitive: `\` at `index` escapes the character after it, so
    /// the two read as one unit. A lone trailing `\` escapes nothing.
    static func isEscapePair(at index: Int, in characters: [Character]) -> Bool {
        characters[index] == "\\" && index + 1 < characters.count
    }

    // MARK: - Queries

    /// The scanned text joined back together, unescaped.
    static func text(of text: String, context: Context) -> String {
        scan(text, context: context).map(\.text).joined()
    }

    /// `text` as the compiler prints it: every escape pair `\x` read as `x`.
    ///
    /// Every piece of text is unescaped exactly once, when it is final: nothing
    /// will split it again. Where that happens depends on the piece:
    /// - the literal runs of a content line and its tag text are final when the
    ///   parser scans the line (`InkParser.parseContentSegments`), and are
    ///   unescaped there, by the scan itself;
    /// - text the parser keeps for later splitting keeps its escape pairs, since
    ///   a split must still know which characters were escaped: a `.text`
    ///   statement, a brace body (alternative stages, conditional arms) and a
    ///   choice label. Each is unescaped here, by the emitter that turns it into
    ///   a text node.
    static func unescaped(_ text: String) -> String {
        self.text(of: text, context: .content)
    }

    /// The offset of the first unescaped `target` in `text` outside any `{…}`
    /// group, or `nil`. Depth changes only at brace markers, so a token is
    /// searched whole at its depth; an escape pair is skipped whole, so `\:`
    /// never matches `:`.
    static func firstTopLevel(_ target: Character, in text: String) -> Int? {
        let characters = Array(text)
        var depth = 0
        var index = 0
        for token in scan(text, context: .content) {
            depth += token.braceDepthChange
            index = token.offset
            while depth == 0, index < token.end {
                if characters[index] == target {
                    return index
                }
                index += isEscapePair(at: index, in: characters) ? 2 : 1
            }
        }
        return nil
    }

    /// The first `marker` in `text`, or `nil`.
    static func first(_ marker: Marker, in text: String, context: Context) -> Token? {
        scan(text, context: context).first { $0.marker == marker }
    }

    /// Whether `text` holds `marker`.
    static func contains(_ marker: Marker, in text: String, context: Context) -> Bool {
        first(marker, in: text, context: context) != nil
    }

    /// `text` cut at every `marker`, empty pieces kept.
    static func split(_ text: String, at marker: Marker, context: Context) -> [String] {
        var pieces = [""]
        for token in scan(text, context: context) {
            if token.marker == marker {
                pieces.append("")
            } else {
                pieces[pieces.count - 1] += token.text
            }
        }
        return pieces
    }

    // MARK: - Stop sets

    private static let singleMarkerText: [Marker: String] = [
        .braceOpen: "{", .braceClose: "}", .bar: "|", .hash: "#", .newline: "\n",
        .bracketOpen: "[", .bracketClose: "]", .quote: "\"",
    ]

    private static let contentStops: [Character: Marker] = [
        "{": .braceOpen, "}": .braceClose, "|": .bar, "#": .hash,
        "\n": .newline, "\r": .newline, "\r\n": .newline,
    ]

    private static func stops(for context: Context) -> [Character: Marker] {
        switch context {
        case .content, .tag: return contentStops
        case .choice: return contentStops.merging(["[": .bracketOpen, "]": .bracketClose]) { $1 }
        case .string: return contentStops.merging(["\"": .quote]) { $1 }
        }
    }

    /// The two-character markers, which pause a run rather than stop it.
    private static let pairMarkers: [Marker] = [.glue, .divert]

    /// The marker starting at `index`, or `nil` when it is run text.
    fileprivate static func marker(at index: Int, in characters: [Character], stops: [Character: Marker]) -> Marker? {
        if let single = stops[characters[index]] {
            return single
        }
        guard index + 1 < characters.count else { return nil }
        let pair = String(characters[index...index + 1])
        return pairMarkers.first { $0.text == pair }
    }

    // MARK: - Cursor

    private struct Cursor {
        let characters: [Character]
        let stops: [Character: Marker]
        var index = 0
        var tokens: [Token] = []
        var run = ""
        var runStart = 0

        init(characters: [Character], context: Context) {
            self.characters = characters
            self.stops = ContentTextScanner.stops(for: context)
        }

        mutating func scanAll() -> [Token] {
            while index < characters.count {
                if ContentTextScanner.isEscapePair(at: index, in: characters) {
                    appendEscapePair()
                } else if let marker = ContentTextScanner.marker(at: index, in: characters, stops: stops) {
                    appendMarker(marker)
                } else {
                    run.append(characters[index])
                    index += 1
                }
            }
            flushRun()
            return tokens
        }

        /// The escaped character joins the run; its backslash is dropped.
        private mutating func appendEscapePair() {
            run.append(characters[index + 1])
            index += 2
        }

        private mutating func appendMarker(_ marker: Marker) {
            flushRun()
            let length = marker.text.count
            tokens.append(Token(marker: marker, text: String(characters[index..<index + length]), offset: index, length: length))
            index += length
            runStart = index
        }

        private mutating func flushRun() {
            if index > runStart {
                tokens.append(Token(marker: nil, text: run, offset: runStart, length: index - runStart))
            }
            run = ""
            runStart = index
        }
    }
}
