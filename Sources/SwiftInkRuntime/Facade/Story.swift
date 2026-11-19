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
    /// The story uses ink features the runtime does not support yet. Thrown by
    /// `Story(json:)` for the whole story, so nothing unsupported is ever played
    /// silently (issue #32). Each feature lists where the story uses it.
    case unsupportedFeatures([UnsupportedFeature])
}

public final class Story {

    let engine: InkEngine

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

    /// Collapse runs of inline whitespace (spaces and tabs) to a single space,
    /// dropping any run at the start or end of a line. Mirrors
    /// `StoryState.CleanOutputWhitespace` in the C# reference runtime (and inkjs),
    /// which is applied to every `currentText` value before it is returned. That
    /// character loop emits a run as one space only when it is neither at the
    /// start of a line nor followed by a newline / the end of the text — i.e. it
    /// trims each line and collapses inner runs, which is what this does.
    /// Newlines are preserved so multi-line output is unaffected.
    private func cleanOutputWhitespace(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            }
            .joined(separator: "\n")
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

    public func getVariable(_ name: String) -> Any? {
        engine.getVariable(name)
    }

    public func setVariable(_ name: String, to value: some Any) {
        engine.setVariable(name, to: value)
    }

    public func visitCount(forKnot name: String) -> Int {
        engine.visitCount(forKnot: name)
    }

    @discardableResult
    public func continueMaximally() -> String {
        var output = ""
        while canContinue {
            output += `continue`()
        }
        return output
    }
}
