import Foundation

// MARK: - Supporting types

enum InkValue: Codable, Equatable {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)

    private enum CodingKeys: String, CodingKey {
        case type, intValue, floatValue, stringValue, boolValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(String.self, forKey: .type)
        switch type_ {
        case "int":
            self = .int(try container.decode(Int.self, forKey: .intValue))
        case "float":
            self = .float(try container.decode(Double.self, forKey: .floatValue))
        case "string":
            self = .string(try container.decode(String.self, forKey: .stringValue))
        case "bool":
            self = .bool(try container.decode(Bool.self, forKey: .boolValue))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown InkValue type: \(type_)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .int(let value):
            try container.encode("int", forKey: .type)
            try container.encode(value, forKey: .intValue)
        case .float(let value):
            try container.encode("float", forKey: .type)
            try container.encode(value, forKey: .floatValue)
        case .string(let value):
            try container.encode("string", forKey: .type)
            try container.encode(value, forKey: .stringValue)
        case .bool(let value):
            try container.encode("bool", forKey: .type)
            try container.encode(value, forKey: .boolValue)
        }
    }
}

struct ChoiceData: Codable {
    let text: String
    let targetPath: String
    let index: Int
}

struct StoryPointer: Codable {
    var containerPath: [String]
    var index: Int
}

// MARK: - StoryState

struct StoryState: Codable {
    var pointer: StoryPointer
    var outputStream: [String]
    var variablesState: [String: InkValue]
    var visitCounts: [String: Int]
    var currentTags: [String]
    var isEnded: Bool
    var currentChoices: [ChoiceData]

    // Evaluation stack for expression evaluation
    var evalStack: [InkValue]

    // Tag accumulation state
    var inTagMode: Bool
    var tagAccumulator: String

    // String accumulation mode (for "str"/"/str" control commands)
    var inStringMode: Bool
    var stringAccumulator: String

    init() {
        pointer = StoryPointer(containerPath: [], index: 0)
        outputStream = []
        variablesState = [:]
        visitCounts = [:]
        currentTags = []
        isEnded = false
        currentChoices = []
        evalStack = []
        inTagMode = false
        tagAccumulator = ""
        inStringMode = false
        stringAccumulator = ""
    }
}
