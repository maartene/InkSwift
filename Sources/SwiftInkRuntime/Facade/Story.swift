import Foundation

public struct Choice {
    public let text: String
    public let index: Int
    public let tags: [String]
}

public enum StoryError: Error, Equatable {
    case decoderProbeFailure(reason: String)
    case invalidJSON
    case unsupportedInkVersion(Int)
    case invalidChoiceIndex(Int)
    case invalidStateData
    case knotNotFound(String)
}

public final class Story {

    private let engine: InkEngine

    public init(blueprint: StoryBlueprint) {
        engine = InkEngine(root: blueprint.root)
    }

    public convenience init(json: String) throws {
        self.init(blueprint: try StoryBlueprint(json: json))
    }

    public var canContinue: Bool {
        engine.canContinue
    }

    public var currentText: String {
        engine.currentText
    }

    public var currentChoices: [Choice] {
        engine.currentChoices
    }

    public var currentTags: [String] {
        engine.currentTags
    }

    public var globalTags: [String] {
        engine.globalTags
    }

    public var currentErrors: [String] {
        engine.currentErrors
    }

    @discardableResult
    public func `continue`() -> String {
        engine.step()
        return cleanOutputWhitespace(engine.currentText)
    }

    /// Collapse runs of inline whitespace (spaces and tabs) to a single space.
    /// Mirrors the `CleanOutputWhitespace` function in the inkjs reference runtime
    /// which is applied to every `currentText` value before it is returned.
    /// Newlines are preserved so multi-line output is unaffected.
    private func cleanOutputWhitespace(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var whitespaceStart = -1
        var lastNewlinePos = 0
        for (i, c) in text.enumerated() {
            let isWS = c == " " || c == "\t"
            if isWS {
                if whitespaceStart == -1 { whitespaceStart = i }
            } else {
                if whitespaceStart >= 0 {
                    // We have a run of whitespace. Collapse to single space
                    // unless it's at the start of a new line (whitespaceStart == lastNewlinePos).
                    if c != "\n" && whitespaceStart != lastNewlinePos {
                        result.append(" ")
                    }
                    whitespaceStart = -1
                }
                if c == "\n" { lastNewlinePos = i + 1 }
                result.append(c)
            }
        }
        return result
    }

    public func chooseChoice(at index: Int) throws {
        try engine.chooseChoice(at: index)
    }

    public func saveState() throws -> Data {
        try engine.saveState()
    }

    public func restoreState(_ data: Data) throws {
        try engine.restoreState(data)
    }

    public func moveToKnot(_ knot: String, stitch: String? = nil) throws {
        try engine.moveToKnot(knot, stitch: stitch)
    }
}
