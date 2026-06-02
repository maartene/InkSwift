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
        return engine.currentText
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
}
