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

    var isTag: Bool {
        if case .tag = self { return true }
        return false
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

/// A tag still in the output stream at a save (ADR-020 §6): `at` is the index
/// into the saved `outputStream` strings before which it sat, `0...count`.
struct PendingOutputTag: Codable, Equatable {
    let at: Int
    let text: String
}

/// The output stream as saved: its text and newline strings (the
/// `outputStream` key, ADR-018) and its tags at their positions between them
/// (the optional `outputStreamTags` key, ADR-020 §6).
struct OutputStreamWire: Equatable {
    let strings: [String]
    let tags: [PendingOutputTag]

    init(strings: [String], tags: [PendingOutputTag]) {
        self.strings = strings
        self.tags = tags
    }

    init(_ items: [OutputItem]) {
        var strings: [String] = []
        var tags: [PendingOutputTag] = []
        for item in items {
            if case .tag(let tag) = item {
                tags.append(PendingOutputTag(at: strings.count, text: tag))
            } else if let text = item.wireText {
                strings.append(text)
            }
        }
        self.init(strings: strings, tags: tags)
    }

    /// The stream with each tag put back before the string at its `at`, tags
    /// at one position in array order; an `at` past the end goes last.
    var items: [OutputItem] {
        var tagsAt = Dictionary(grouping: tags) { min(max($0.at, 0), strings.count) }
        var items: [OutputItem] = []
        for (index, string) in strings.enumerated() {
            items += (tagsAt.removeValue(forKey: index) ?? []).map { .tag($0.text) }
            items.append(OutputItem(wireText: string))
        }
        return items + (tagsAt[strings.count] ?? []).map { .tag($0.text) }
    }
}
