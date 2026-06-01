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

    private let root: ContainerNode
    private var _canContinue: Bool
    private var _currentText: String

    public init(json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw StoryError.invalidJSON
        }

        // Validate inkVersion
        guard let rawObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let topLevel = rawObject as? [String: Any] else {
            throw StoryError.invalidJSON
        }

        if let inkVersion = topLevel["inkVersion"] as? Int, inkVersion < 20 {
            throw StoryError.unsupportedInkVersion(inkVersion)
        }

        // Run decoder probe to validate bundle fixture
        do {
            try InkDecoder().probe()
        } catch {
            throw StoryError.decoderProbeFailure(reason: error.localizedDescription)
        }

        // Decode the story JSON
        let decoder = InkDecoder()
        do {
            root = try decoder.decode(data)
        } catch {
            throw StoryError.invalidJSON
        }

        // Minimal walking skeleton: find first text node
        let firstText = Story.findFirstText(in: root)
        _currentText = firstText ?? ""
        _canContinue = firstText != nil
    }

    public var canContinue: Bool {
        return _canContinue
    }

    public var currentText: String {
        return _currentText
    }

    public var currentChoices: [Choice] {
        return []
    }

    public var currentTags: [String] {
        return []
    }

    public var globalTags: [String] {
        return []
    }

    public var currentErrors: [String] {
        return []
    }

    @discardableResult
    public func `continue`() -> String {
        let text = _currentText
        _canContinue = false
        _currentText = ""
        return text
    }

    public func chooseChoice(at index: Int) throws {
        throw StoryError.invalidChoiceIndex(index)
    }

    public func saveState() throws -> Data {
        throw StoryError.invalidStateData
    }

    public func restoreState(_ data: Data) throws {
        throw StoryError.invalidStateData
    }

    // MARK: - Minimal walking skeleton helper

    private static func findFirstText(in node: ContainerNode) -> String? {
        for child in node.children {
            if let text = extractText(from: child) {
                return text
            }
        }
        return nil
    }

    private static func extractText(from kind: NodeKind) -> String? {
        switch kind {
        case .text(let value):
            return value
        case .container(let container):
            return findFirstText(in: container)
        default:
            return nil
        }
    }
}
