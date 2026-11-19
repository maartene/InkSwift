/// One item of the in-memory output stream (ADR-020 §1): text, a line break,
/// or a tag at its position in the stream, as in C#'s output stream.
///
/// The save wire is a `[String]` of the text and newline items only (ADR-018):
/// `"\n"` is a newline, any other string is text, and tag items are left out.
/// The string-literal form uses the same spelling.
enum OutputItem: Equatable, Sendable, ExpressibleByStringLiteral {
    case text(String)
    case newline
    case tag(String)

    init(wireText: String) {
        self = wireText == "\n" ? .newline : .text(wireText)
    }

    init(stringLiteral value: String) {
        self.init(wireText: value)
    }

    /// The item as saved, or nil for a tag (not part of the `outputStream` wire).
    var wireText: String? {
        switch self {
        case .text(let text): return text
        case .newline: return "\n"
        case .tag: return nil
        }
    }

    /// Text holding anything but spaces and tabs.
    var isNonWhitespaceText: Bool {
        guard case .text(let text) = self else { return false }
        return text.contains(where: { $0 != " " && $0 != "\t" })
    }
}

extension Array where Element == OutputItem {
    /// The text items joined, newlines and tags left out.
    var joinedText: String {
        compactMap { item -> String? in
            guard case .text(let text) = item else { return nil }
            return text
        }.joined()
    }
}

/// A line split off the front of the output stream (ADR-020 §2). A pure
/// function of the stream: the items before the first newline form the line
/// (its text and its tags, in order); everything after that newline is the
/// remainder. Without a newline the whole stream is the line.
struct OutputLine: Equatable {
    let text: String
    let tags: [String]
    let remainder: [OutputItem]

    init(splitting stream: [OutputItem]) {
        let end = stream.firstIndex(of: .newline) ?? stream.endIndex
        let lineItems = Array(stream[..<end])
        text = lineItems.joinedText
        tags = lineItems.compactMap { item -> String? in
            guard case .tag(let tag) = item else { return nil }
            return tag
        }
        remainder = end < stream.endIndex ? Array(stream[(end + 1)...]) : []
    }
}
