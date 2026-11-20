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
/// Two modes, so that only one step changes behaviour (ADR-026 §5):
/// - `.escapeAgnostic` reproduces the compiler before #35. A backslash is
///   ordinary text: it neither protects the next character nor disappears. The
///   one exception is the string context, whose closing quote has always skipped
///   escape pairs: there a pair `\x` is never a stop, and stays raw in the run.
/// - `.escapeAware` is inklecate's rule: `\x` is the literal `x` and never a
///   stop. `UnsupportedConstructDetector` already reads text this way (#31).
///
/// Thread arrows `<-` are not a marker yet: no consumer splits on them, and
/// making `<-` a marker would change how `<->` reads.
enum ContentTextScanner {

    /// Which text is being scanned; selects the stop set.
    enum Context: CaseIterable, Sendable {
        case content, choice, string, tag
    }

    /// How a backslash reads.
    enum Mode: Sendable {
        case escapeAgnostic, escapeAware
    }

    /// The compiler's mode. 05-02 flips it to `.escapeAware` (#35).
    static let compilerMode = Mode.escapeAgnostic

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
        /// The token's text: a marker's source text, or a run's text (raw in
        /// escape-agnostic mode, unescaped in escape-aware mode).
        let text: String
        /// Offset of the token's first source character.
        let offset: Int
        /// Number of source characters the token spans.
        let length: Int

        /// Offset just past the token in the source.
        var end: Int { offset + length }

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
    static func scan(_ text: String, context: Context, mode: Mode = compilerMode) -> [Token] {
        var cursor = Cursor(characters: Array(text), context: context, pairsEscapes: pairsEscapes(context, mode))
        return cursor.tokens(unescaping: mode == .escapeAware)
    }

    /// The escape primitive: `\` at `index` escapes the character after it, so
    /// the two read as one unit. A lone trailing `\` escapes nothing.
    static func isEscapePair(at index: Int, in characters: [Character]) -> Bool {
        characters[index] == "\\" && index + 1 < characters.count
    }

    /// Whether escape pairs are units in this context and mode (see `Mode`).
    private static func pairsEscapes(_ context: Context, _ mode: Mode) -> Bool {
        mode == .escapeAware || context == .string
    }

    // MARK: - Queries

    /// The scanned text joined back together: `text` itself in escape-agnostic
    /// mode, the unescaped text in escape-aware mode.
    static func text(of text: String, context: Context, mode: Mode = compilerMode) -> String {
        scan(text, context: context, mode: mode).map(\.text).joined()
    }

    /// The first `marker` in `text`, or `nil`.
    static func first(_ marker: Marker, in text: String, context: Context, mode: Mode = compilerMode) -> Token? {
        scan(text, context: context, mode: mode).first { $0.marker == marker }
    }

    /// Whether `text` holds `marker`.
    static func contains(_ marker: Marker, in text: String, context: Context, mode: Mode = compilerMode) -> Bool {
        first(marker, in: text, context: context, mode: mode) != nil
    }

    /// `text` cut at every `marker`, empty pieces kept.
    static func split(_ text: String, at marker: Marker, context: Context, mode: Mode = compilerMode) -> [String] {
        var pieces = [""]
        for token in scan(text, context: context, mode: mode) {
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
        let pairsEscapes: Bool
        var index = 0
        var tokens: [Token] = []
        var run = ""
        var runStart = 0

        init(characters: [Character], context: Context, pairsEscapes: Bool) {
            self.characters = characters
            self.stops = ContentTextScanner.stops(for: context)
            self.pairsEscapes = pairsEscapes
        }

        mutating func tokens(unescaping: Bool) -> [Token] {
            while index < characters.count {
                if pairsEscapes, ContentTextScanner.isEscapePair(at: index, in: characters) {
                    appendEscapePair(unescaping: unescaping)
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

        private mutating func appendEscapePair(unescaping: Bool) {
            if unescaping == false {
                run.append(characters[index])
            }
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
