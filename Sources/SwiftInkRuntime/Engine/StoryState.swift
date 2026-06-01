import Foundation

// MARK: - InkValue

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
        let typeName = try container.decode(String.self, forKey: .type)
        switch typeName {
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
                debugDescription: "Unknown InkValue type: \(typeName)"
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

// MARK: - InkValue arithmetic and conversion

extension InkValue {

    var asDouble: Double {
        switch self {
        case .int(let n): return Double(n)
        case .float(let f): return f
        case .bool(let b): return b ? 1.0 : 0.0
        case .string: return 0.0
        }
    }

    var asBool: Bool {
        switch self {
        case .bool(let b): return b
        case .int(let n): return n != 0
        case .float(let f): return f != 0.0
        case .string(let s): return !s.isEmpty
        }
    }

    var asString: String {
        switch self {
        case .int(let n): return String(n)
        case .float(let f): return String(f)
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        }
    }

    func adding(_ rhs: InkValue) -> InkValue {
        switch (self, rhs) {
        case (.int(let a), .int(let b)): return .int(a + b)
        case (.string(let a), .string(let b)): return .string(a + b)
        default: return .float(asDouble + rhs.asDouble)
        }
    }

    func subtracting(_ rhs: InkValue) -> InkValue {
        switch (self, rhs) {
        case (.int(let a), .int(let b)): return .int(a - b)
        default: return .float(asDouble - rhs.asDouble)
        }
    }

    func multiplying(_ rhs: InkValue) -> InkValue {
        switch (self, rhs) {
        case (.int(let a), .int(let b)): return .int(a * b)
        default: return .float(asDouble * rhs.asDouble)
        }
    }

    func dividing(by rhs: InkValue) -> InkValue {
        switch (self, rhs) {
        case (.int(let a), .int(let b)) where b != 0: return .int(a / b)
        default:
            let divisor = rhs.asDouble
            guard divisor != 0.0 else { return .float(0.0) }
            return .float(asDouble / divisor)
        }
    }

    func modulo(_ rhs: InkValue) -> InkValue {
        switch (self, rhs) {
        case (.int(let a), .int(let b)) where b != 0: return .int(a % b)
        default:
            let divisor = rhs.asDouble
            guard divisor != 0.0 else { return .float(0.0) }
            return .float(asDouble.truncatingRemainder(dividingBy: divisor))
        }
    }

    func comparing(to rhs: InkValue, using op: (Double, Double) -> Bool) -> InkValue {
        return .bool(op(asDouble, rhs.asDouble))
    }

    var floored: InkValue {
        switch self {
        case .float(let f): return .int(Int(Foundation.floor(f)))
        default: return self
        }
    }

    var ceiled: InkValue {
        switch self {
        case .float(let f): return .int(Int(Foundation.ceil(f)))
        default: return self
        }
    }

    var toInt: InkValue {
        switch self {
        case .int: return self
        case .float(let f): return .int(Int(f))
        case .bool(let b): return .int(b ? 1 : 0)
        case .string(let s): return .int(Int(s) ?? 0)
        }
    }

    var toFloat: InkValue {
        switch self {
        case .float: return self
        case .int(let n): return .float(Double(n))
        case .bool(let b): return .float(b ? 1.0 : 0.0)
        case .string(let s): return .float(Double(s) ?? 0.0)
        }
    }
}

// MARK: - Supporting types

struct ChoiceData: Codable {
    let text: String
    let targetPath: String
    let index: Int
}

struct StoryPointer: Codable {
    var containerPath: [String]
    var index: Int
}

/// One frame of the container execution stack, serialised for save/restore.
/// `childIndex` is the index into the parent's children array used to enter
/// this frame (nil for the root frame). `executionIndex` is the next-to-process
/// position within the container at this depth.
struct ContainerStackFrame: Codable {
    var childIndex: Int?   // nil = root container; otherwise parent.children[childIndex]
    var executionIndex: Int
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

    // Full container execution stack for save/restore.
    // Each frame holds the child-index used to enter it (nil = root) and the
    // current execution index within that container.
    var stackFrames: [ContainerStackFrame]

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
        stackFrames = []
    }
}
