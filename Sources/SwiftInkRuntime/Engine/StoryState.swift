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
    /// Stack snapshot to install when this choice is selected. Captured at
    /// choice-collection time so the continuation can be resumed even after a
    /// save/restore round-trip (when in-memory resolution caches are gone).
    let continuationFrames: [ContainerStackFrame]
    let index: Int
}

struct StoryPointer: Codable {
    var containerPath: [String]
    var index: Int
}

/// One frame of the container execution stack, serialised for save/restore.
/// `pathFromRoot` is the absolute path from root to this frame's container:
/// each component is either a numeric index into the parent's `children`
/// array, or a name lookup into the parent's `namedContent`. Empty array =
/// root. `executionIndex` is the next-to-process position within the container.
/// `isChoiceContinuationRoot` marks frames installed by chooseChoice so the
/// engine stops walking when the continuation exhausts (one-level callstack).
struct ContainerStackFrame: Codable {
    var pathFromRoot: [String]
    var executionIndex: Int
    var isChoiceContinuationRoot: Bool

    init(pathFromRoot: [String], executionIndex: Int, isChoiceContinuationRoot: Bool = false) {
        self.pathFromRoot = pathFromRoot
        self.executionIndex = executionIndex
        self.isChoiceContinuationRoot = isChoiceContinuationRoot
    }

    private enum CodingKeys: String, CodingKey {
        case pathFromRoot, executionIndex, isChoiceContinuationRoot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pathFromRoot = try container.decode([String].self, forKey: .pathFromRoot)
        executionIndex = try container.decode(Int.self, forKey: .executionIndex)
        isChoiceContinuationRoot = try container.decodeIfPresent(Bool.self, forKey: .isChoiceContinuationRoot) ?? false
    }
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

    var lastCompletedLine: String

    // Full container execution stack for save/restore.
    // Each frame holds the child-index used to enter it (nil = root) and the
    // current execution index within that container.
    var stackFrames: [ContainerStackFrame]

    // Call/return stack: push-divert-target nodes write here; variable-divert nodes pop from here.
    var returnStack: [String]

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
        lastCompletedLine = ""
        stackFrames = []
        returnStack = []
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case pointer, outputStream, variablesState, visitCounts, currentTags
        case isEnded, currentChoices, evalStack
        case inTagMode, tagAccumulator, inStringMode, stringAccumulator
        case lastCompletedLine, stackFrames, returnStack
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pointer           = try container.decode(StoryPointer.self,         forKey: .pointer)
        outputStream      = try container.decode([String].self,             forKey: .outputStream)
        variablesState    = try container.decode([String: InkValue].self,   forKey: .variablesState)
        visitCounts       = try container.decode([String: Int].self,        forKey: .visitCounts)
        currentTags       = try container.decode([String].self,             forKey: .currentTags)
        isEnded           = try container.decode(Bool.self,                 forKey: .isEnded)
        currentChoices    = try container.decode([ChoiceData].self,         forKey: .currentChoices)
        evalStack         = try container.decode([InkValue].self,           forKey: .evalStack)
        inTagMode         = try container.decode(Bool.self,                 forKey: .inTagMode)
        tagAccumulator    = try container.decode(String.self,               forKey: .tagAccumulator)
        inStringMode      = try container.decode(Bool.self,                 forKey: .inStringMode)
        stringAccumulator = try container.decode(String.self,               forKey: .stringAccumulator)
        lastCompletedLine = try container.decode(String.self,               forKey: .lastCompletedLine)
        stackFrames       = try container.decode([ContainerStackFrame].self, forKey: .stackFrames)
        returnStack       = try container.decodeIfPresent([String].self,    forKey: .returnStack) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pointer,           forKey: .pointer)
        try container.encode(outputStream,      forKey: .outputStream)
        try container.encode(variablesState,    forKey: .variablesState)
        try container.encode(visitCounts,       forKey: .visitCounts)
        try container.encode(currentTags,       forKey: .currentTags)
        try container.encode(isEnded,           forKey: .isEnded)
        try container.encode(currentChoices,    forKey: .currentChoices)
        try container.encode(evalStack,         forKey: .evalStack)
        try container.encode(inTagMode,         forKey: .inTagMode)
        try container.encode(tagAccumulator,    forKey: .tagAccumulator)
        try container.encode(inStringMode,      forKey: .inStringMode)
        try container.encode(stringAccumulator, forKey: .stringAccumulator)
        try container.encode(lastCompletedLine, forKey: .lastCompletedLine)
        try container.encode(stackFrames,       forKey: .stackFrames)
        try container.encode(returnStack,       forKey: .returnStack)
    }
}
