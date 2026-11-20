import Foundation

// MARK: - InkValue

enum InkValue: Codable, Equatable {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)
    case variablePointer(name: String, contextIndex: Int)
    /// C# `Runtime.Void`: the no-value result of a function that returns
    /// nothing (an implicit end of body or a bare `~ return`) and of
    /// `SEED_RANDOM`, and the value a tunnel's `ev void /ev ->->` pushes for
    /// `->->` to pop. Distinct from every story value — a story string "void"
    /// is ordinary text — so `out` can skip exactly this and nothing else.
    case void

    private enum CodingKeys: String, CodingKey {
        case type, intValue, floatValue, stringValue, boolValue, pointerName, pointerContextIndex
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
        case "variablePointer":
            let name = try container.decode(String.self, forKey: .pointerName)
            let contextIndex = try container.decode(Int.self, forKey: .pointerContextIndex)
            self = .variablePointer(name: name, contextIndex: contextIndex)
        case "void":
            self = .void
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
        case .variablePointer(let name, let contextIndex):
            try container.encode("variablePointer", forKey: .type)
            try container.encode(name, forKey: .pointerName)
            try container.encode(contextIndex, forKey: .pointerContextIndex)
        case .void:
            try container.encode("void", forKey: .type)
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
        case .variablePointer, .void: return 0.0
        }
    }

    var asBool: Bool {
        switch self {
        case .bool(let b): return b
        case .int(let n): return n != 0
        case .float(let f): return f != 0.0
        case .string(let s): return !s.isEmpty
        case .variablePointer, .void: return false
        }
    }

    var asString: String {
        switch self {
        case .int(let n): return String(n)
        case .float(let f): return InkFloatText(f).text
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .variablePointer(let name, _): return name
        case .void: return ""
        }
    }
}

// MARK: - Operand coercion

/// A runtime error the reference raises as a `StoryException`: the engine
/// reports `message` bare in `currentErrors` (ADR-017) and ends the flow.
struct InkRuntimeError: Error, Equatable {
    let message: String

    /// C# `Call<T>` (NativeFunctionCall.cs ~125-170): no form of the operation
    /// is registered for the coerced type (C# `ValueType`: Int, Float, String).
    static func cannotPerform(_ function: NativeFunction, on type: String) -> InkRuntimeError {
        InkRuntimeError(message: "Cannot perform operation '\(function.token)' on \(type)")
    }

    /// C# `Call` (NativeFunctionCall.cs ~96-98): checked before any coercion.
    static func voidOperand(_ function: NativeFunction) -> InkRuntimeError {
        InkRuntimeError(message: "Attempting to perform \(function.token) on a void value. "
            + "Did you forget to 'return' a value from a function you called here?")
    }

    /// C# divides ints with plain `/` and `%`, which throw .NET's
    /// DivideByZeroException; inklecate crashes on it (inkle/ink#843, open
    /// and unanswered since 2023), so there is no story behaviour to copy.
    /// InkSwift reports the exception's text as a runtime error and ends the
    /// flow (maintainer decision; docs/reference/differences-from-inklecate.md).
    static let divideByZero = InkRuntimeError(message: "Attempted to divide by zero.")

    /// An instruction found too few values on the evaluation stack: an
    /// operator, an assignment, `out`, `pop`, `->->`, SEED_RANDOM, or the
    /// condition of a divert or choice. inklecate's JSON never does this, but `Story(json:)` accepts any JSON
    /// and must not crash the host on a malformed one (maintainer decision;
    /// docs/reference/differences-from-inklecate.md).
    static let emptyEvaluationStack = InkRuntimeError(message: "Evaluation stack is empty")
}

/// Two operands coerced to one type: what every binary native operates on.
enum CoercedOperands: Equatable {
    case ints(Int, Int)
    case floats(Double, Double)
    case strings(String, String)
}

/// One operand coerced as C# coerces a lone parameter: what every unary
/// native operates on.
enum CoercedOperand: Equatable {
    case int(Int)
    case float(Double)
    case string(String)
}

extension NativeFunction {

    /// C# `Call` (NativeFunctionCall.cs ~96-98) refuses a void operand before
    /// coercing, for unary and binary operations alike.
    func refuseVoid(_ operands: InkValue...) throws(InkRuntimeError) {
        if operands.contains(.void) { throw .voidOperand(self) }
    }
}

extension InkValue {

    /// The C# `ValueType` order used for coercion (Value.cs): bool < int <
    /// float < string. The higher type of two operands "infects" the other.
    enum CoercionType: Int, Comparable {
        case bool, int, float, string

        static func < (lhs: CoercionType, rhs: CoercionType) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    var coercionType: CoercionType {
        switch self {
        case .bool: return .bool
        case .int: return .int
        case .void:
            preconditionFailure("void reached coercion: operators refuse a void operand before coercing it")
        case .float: return .float
        // A pointer is dereferenced before it reaches an operator; should one
        // get here, it takes part by its name, as text.
        case .string, .variablePointer: return .string
        }
    }

    /// C# `CoerceValuesToSingleType` (NativeFunctionCall.cs ~231-250): both
    /// operands cast to the higher of their types, and never below int, so two
    /// bools operate as ints. Host values from `setVariable` already have
    /// their own type (ADR-024 §5); this is the one coercion point.
    static func coerced(_ lhs: InkValue, _ rhs: InkValue) -> CoercedOperands {
        switch max(lhs.coercionType, rhs.coercionType, .int) {
        case .bool, .int: return .ints(lhs.asIntOperand, rhs.asIntOperand)
        case .float: return .floats(lhs.asDouble, rhs.asDouble)
        case .string: return .strings(lhs.asString, rhs.asString)
        }
    }

    /// C# `CoerceValuesToSingleType` with one parameter: lifted to at least
    /// an int, so a lone bool operates as 1 or 0.
    var coercedAlone: CoercedOperand {
        switch max(coercionType, .int) {
        case .bool, .int: return .int(asIntOperand)
        case .float: return .float(asDouble)
        case .string: return .string(asString)
        }
    }

    /// An int or bool operand as an int (C# `BoolValue.Cast(Int)`).
    private var asIntOperand: Int {
        switch self {
        case .int(let n): return n
        default: return asBool ? 1 : 0
        }
    }
}

/// A binary native function per coerced operand type, as C# registers one
/// operation per `ValueType` (NativeFunctionCall.cs GenerateNativeFunctions).
/// An operation without a form for the coerced type raises the reference's
/// error, named after that type (C# `ValueType`: Int, Float, String).
struct BinaryNativeFunction {
    let function: NativeFunction
    var int: ((Int, Int) -> InkValue)?
    var float: ((Double, Double) -> InkValue)?
    var string: ((String, String) -> InkValue)?
    /// Integer division and modulo: see `InkRuntimeError.divideByZero`. A flag
    /// rather than throwing closures, which need macOS 15 runtime support for
    /// typed throws.
    var refusesZeroIntDivisor = false

    func callAsFunction(_ lhs: InkValue, _ rhs: InkValue) throws(InkRuntimeError) -> InkValue {
        try function.refuseVoid(lhs, rhs)
        switch InkValue.coerced(lhs, rhs) {
        case .ints(_, 0) where refusesZeroIntDivisor: throw .divideByZero
        case .ints(let a, let b): return try perform(int, a, b, on: "Int")
        case .floats(let a, let b): return try perform(float, a, b, on: "Float")
        case .strings(let a, let b): return try perform(string, a, b, on: "String")
        }
    }

    private func perform<Operand>(
        _ operation: ((Operand, Operand) -> InkValue)?, _ lhs: Operand, _ rhs: Operand, on type: String
    ) throws(InkRuntimeError) -> InkValue {
        guard let operation else { throw .cannotPerform(function, on: type) }
        return operation(lhs, rhs)
    }

    /// A comparison or logic operation: the same Bool-valued test for ints and floats.
    static func test(
        _ function: NativeFunction,
        int: @escaping (Int, Int) -> Bool,
        float: @escaping (Double, Double) -> Bool,
        string: ((String, String) -> Bool)? = nil
    ) -> BinaryNativeFunction {
        BinaryNativeFunction(
            function: function,
            int: { .bool(int($0, $1)) },
            float: { .bool(float($0, $1)) },
            string: string.map { test in { .bool(test($0, $1)) } })
    }

    static let add = BinaryNativeFunction(
        function: .add, int: { .int($0 + $1) }, float: { .float($0 + $1) }, string: { .string($0 + $1) })
    static let subtract = BinaryNativeFunction(
        function: .subtract, int: { .int($0 - $1) }, float: { .float($0 - $1) })
    static let multiply = BinaryNativeFunction(
        function: .multiply, int: { .int($0 * $1) }, float: { .float($0 * $1) })
    // Int: see `InkRuntimeError.divideByZero`. Floats follow IEEE, as C#'s do.
    static let divide = BinaryNativeFunction(
        function: .divide,
        int: { .int($0 / $1) },
        float: { .float($0 / $1) },
        refusesZeroIntDivisor: true)
    static let modulo = BinaryNativeFunction(
        function: .modulo,
        int: { .int($0 % $1) },
        float: { .float($0.truncatingRemainder(dividingBy: $1)) },
        refusesZeroIntDivisor: true)
    static let equal = test(.equal, int: ==, float: ==, string: ==)
    static let notEqual = test(.notEqual, int: !=, float: !=, string: !=)
    static let greater = test(.greater, int: >, float: >)
    static let less = test(.less, int: <, float: <)
    static let greaterOrEqual = test(.greaterOrEqual, int: >=, float: >=)
    static let lessOrEqual = test(.lessOrEqual, int: <=, float: <=)
    static let and = test(.and, int: { $0 != 0 && $1 != 0 }, float: { $0 != 0 && $1 != 0 })
    static let or = test(.or, int: { $0 != 0 || $1 != 0 }, float: { $0 != 0 || $1 != 0 })
    static let min = BinaryNativeFunction(
        function: .min, int: { .int(Swift.min($0, $1)) }, float: { .float(Swift.min($0, $1)) })
    static let max = BinaryNativeFunction(
        function: .max, int: { .int(Swift.max($0, $1)) }, float: { .float(Swift.max($0, $1)) })

    // `(float)Math.Pow` for ints and floats alike: POW(2, 3) is 8.0.
    static let pow = BinaryNativeFunction(
        function: .pow,
        int: { .float(Foundation.pow(Double($0), Double($1))) },
        float: { .float(Foundation.pow($0, $1)) })
    // Defined for strings (and lists, refused) only: two numbers raise the
    // reference's error, a string on either side casts the other to a string.
    static let has = BinaryNativeFunction(function: .has, string: { .bool(ordinalContains($0, $1)) })
    static let hasnt = BinaryNativeFunction(function: .hasnt, string: { .bool(!ordinalContains($0, $1)) })

    /// C# `String.Contains(string)`: an ordinal search over UTF-16 code units,
    /// so a decomposed "é" contains "e" and the empty string is in every string.
    /// Swift's `String.contains` compares Characters and would disagree.
    static func ordinalContains(_ haystack: String, _ needle: String) -> Bool {
        let text = Array(haystack.utf16)
        let pattern = Array(needle.utf16)
        guard pattern.count <= text.count else { return false }
        return (0...(text.count - pattern.count)).contains { start in
            text[start..<start + pattern.count].elementsEqual(pattern)
        }
    }

    /// The binary natives by the catalog native they implement, read from
    /// `NativeFunction.operation`.
    static let byFunction: [NativeFunction: BinaryNativeFunction] = Dictionary(
        uniqueKeysWithValues: NativeFunction.allCases.compactMap { native in
            guard case .binary(let operation) = native.operation else { return nil }
            return (native, operation)
        })
}

/// A unary native function per coerced operand type. C# registers the unary
/// operations for Int and Float only (NativeFunctionCall.cs ~336-385), so a
/// string operand raises the reference's error, like a binary operation
/// without a string form.
struct UnaryNativeFunction {
    let function: NativeFunction
    let int: (Int) -> InkValue
    let float: (Double) -> InkValue

    func callAsFunction(_ operand: InkValue) throws(InkRuntimeError) -> InkValue {
        try function.refuseVoid(operand)
        switch operand.coercedAlone {
        case .int(let number): return int(number)
        case .float(let number): return float(number)
        case .string: throw .cannotPerform(function, on: "String")
        }
    }

    static let not = UnaryNativeFunction(
        function: .not, int: { .bool($0 == 0) }, float: { .bool($0 == 0.0) })
    static let negate = UnaryNativeFunction(
        function: .negate, int: { .int(-$0) }, float: { .float(-$0) })
    // FLOOR and CEILING of a float stay a float (`(float)Math.Floor(x)`); on
    // an int they are the identity.
    static let floor = UnaryNativeFunction(
        function: .floor, int: { .int($0) }, float: { .float(Foundation.floor($0)) })
    static let ceiling = UnaryNativeFunction(
        function: .ceiling, int: { .int($0) }, float: { .float(Foundation.ceil($0)) })
    static let int = UnaryNativeFunction(
        function: .int, int: { .int($0) }, float: { .int(truncatedToInkInt($0)) })
    static let float = UnaryNativeFunction(
        function: .float, int: { .float(Double($0)) }, float: { .float($0) })

    /// C# `(int)x`: truncation toward zero into a 32-bit int, saturating as
    /// .NET's conversion does — Infinity and values above the range give
    /// int.MaxValue, -Infinity and values below give int.MinValue, NaN gives 0
    /// (inklecate prints `2147483647 -2147483648 0`). Swift's `Int(_:)` would
    /// trap on all three, and float division by zero now reaches them.
    private static func truncatedToInkInt(_ value: Double) -> Int {
        guard value.isNaN == false else { return 0 }
        return Int(Swift.min(Swift.max(value, Double(Int32.min)), Double(Int32.max)))
    }
}

/// How the engine executes a native function.
enum NativeOperation {
    case binary(BinaryNativeFunction)
    case unary(UnaryNativeFunction)
    /// SEED_RANDOM: pops the seed and pushes void, as C# `Story` does.
    case seedRandom
}

extension NativeFunction {

    /// The operation for this native. The switch is exhaustive over the
    /// catalog, so a new native cannot be dispatched to nothing.
    var operation: NativeOperation {
        switch self {
        case .add: .binary(.add)
        case .subtract: .binary(.subtract)
        case .multiply: .binary(.multiply)
        case .divide: .binary(.divide)
        case .modulo: .binary(.modulo)
        case .equal: .binary(.equal)
        case .notEqual: .binary(.notEqual)
        case .greater: .binary(.greater)
        case .less: .binary(.less)
        case .greaterOrEqual: .binary(.greaterOrEqual)
        case .lessOrEqual: .binary(.lessOrEqual)
        case .and: .binary(.and)
        case .or: .binary(.or)
        case .min: .binary(.min)
        case .max: .binary(.max)
        case .pow: .binary(.pow)
        case .has: .binary(.has)
        case .hasnt: .binary(.hasnt)
        case .not: .unary(.not)
        case .negate: .unary(.negate)
        case .floor: .unary(.floor)
        case .ceiling: .unary(.ceiling)
        case .int: .unary(.int)
        case .float: .unary(.float)
        case .seedRandom: .seedRandom
        }
    }
}

// MARK: - ChoiceFlags

/// Typed bitmask for the `flg` field emitted by inklecate in choice-point JSON.
/// Encodes as its raw `Int` value so saved states remain wire-compatible.
struct ChoiceFlags: OptionSet, Codable {
    let rawValue: Int

    /// Bit 0: a boolean on the evalStack gates whether this choice is shown.
    static let hasCondition      = ChoiceFlags(rawValue: 0x01)
    /// Bit 3: invisible-default / gather fallback — never shown to the user.
    static let isInvisibleDefault = ChoiceFlags(rawValue: 0x08)
    /// Bit 4: once-only choice — suppressed after the first pick.
    static let isOnceOnly        = ChoiceFlags(rawValue: 0x10)

    /// Mask covering all bits that make a choice point visible to the user.
    /// A choice with none of these set is treated as an invisible default.
    static let visibleChoiceMask = ChoiceFlags(rawValue: 0x17)
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
    /// Typed choice flags from the inklecate `flg` bitmask.
    /// Decoded with `decodeIfPresent` so legacy saves without this key default to empty.
    let flags: ChoiceFlags
    /// Choice-level tags (`* [Text # tag]`) — see `StoryState.stringModeTags`.
    /// Decoded with `decodeIfPresent` so legacy saves without this key default to empty.
    let tags: [String]

    private enum CodingKeys: String, CodingKey {
        case text, targetPath, continuationFrames, index, flags, tags
    }

    init(
        text: String, targetPath: String, continuationFrames: [ContainerStackFrame], index: Int,
        flags: ChoiceFlags = [], tags: [String] = []
    ) {
        self.text = text
        self.targetPath = targetPath
        self.continuationFrames = continuationFrames
        self.index = index
        self.flags = flags
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text               = try container.decode(String.self,               forKey: .text)
        targetPath         = try container.decode(String.self,               forKey: .targetPath)
        continuationFrames = try container.decode([ContainerStackFrame].self, forKey: .continuationFrames)
        index              = try container.decode(Int.self,                  forKey: .index)
        let rawFlags       = try container.decodeIfPresent(Int.self,         forKey: .flags) ?? 0
        flags              = ChoiceFlags(rawValue: rawFlags)
        tags               = try container.decodeIfPresent([String].self,    forKey: .tags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text,               forKey: .text)
        try container.encode(targetPath,         forKey: .targetPath)
        try container.encode(continuationFrames, forKey: .continuationFrames)
        try container.encode(index,              forKey: .index)
        try container.encode(flags.rawValue,     forKey: .flags)
        try container.encode(tags,               forKey: .tags)
    }
}

struct StoryPointer: Codable {
    var containerPath: ContainerPath
    var index: Int

    init(containerPath: ContainerPath, index: Int) {
        self.containerPath = containerPath
        self.index = index
    }

    private enum CodingKeys: String, CodingKey {
        case containerPath, index
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        containerPath = ContainerPath(savedComponents: try container.decode([String].self, forKey: .containerPath))
        index = try container.decode(Int.self, forKey: .index)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(containerPath.savedComponents, forKey: .containerPath)
        try container.encode(index, forKey: .index)
    }
}

/// One frame of the container execution stack, serialised for save/restore.
/// `pathFromRoot` is the absolute path from root to this frame's container:
/// each component is either a numeric index into the parent's `children`
/// array, or a name lookup into the parent's `namedContent`. No components =
/// root; saved as an array of component strings (ADR-018). `executionIndex` is the next-to-process position within the container.
/// `isChoiceContinuationRoot` marks frames installed by chooseChoice so the
/// engine stops walking when the continuation exhausts (one-level callstack).
struct ContainerStackFrame: Codable {
    var pathFromRoot: ContainerPath
    var executionIndex: Int
    var isChoiceContinuationRoot: Bool

    init(pathFromRoot: ContainerPath, executionIndex: Int, isChoiceContinuationRoot: Bool = false) {
        self.pathFromRoot = pathFromRoot
        self.executionIndex = executionIndex
        self.isChoiceContinuationRoot = isChoiceContinuationRoot
    }

    private enum CodingKeys: String, CodingKey {
        case pathFromRoot, executionIndex, isChoiceContinuationRoot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pathFromRoot = ContainerPath(savedComponents: try container.decode([String].self, forKey: .pathFromRoot))
        executionIndex = try container.decode(Int.self, forKey: .executionIndex)
        isChoiceContinuationRoot = try container.decodeIfPresent(Bool.self, forKey: .isChoiceContinuationRoot) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pathFromRoot.savedComponents, forKey: .pathFromRoot)
        try container.encode(executionIndex, forKey: .executionIndex)
        try container.encode(isChoiceContinuationRoot, forKey: .isChoiceContinuationRoot)
    }
}

// MARK: - StoryState

struct StoryState: Codable {
    var pointer: StoryPointer
    /// Typed in memory (ADR-020 §1); saved as the `[String]` of its text and
    /// newline items (ADR-018) plus `outputStreamTags` when it holds a tag.
    var outputStream: [OutputItem]
    var variablesState: [String: InkValue]
    /// Saved as `{"a.b": n}`: keys are `ContainerPath.description` (ADR-018).
    var visitCounts: [ContainerPath: Int]
    /// The tags of the line `continue()` last returned (ADR-020 §2).
    var currentTags: [String]
    var isEnded: Bool
    var currentChoices: [ChoiceData]

    // Evaluation stack for expression evaluation
    var evalStack: [InkValue]

    /// The top of the evaluation stack, for an operator or assignment. Only
    /// malformed JSON leaves it empty; that is reported, not skipped.
    mutating func popEvaluationStack() throws(InkRuntimeError) -> InkValue {
        guard let value = evalStack.popLast() else { throw .emptyEvaluationStack }
        return value
    }

    // Tag accumulation state
    var inTagMode: Bool
    var tagAccumulator: String

    // String accumulation mode (for "str"/"/str" control commands)
    var inStringMode: Bool
    var stringAccumulator: String

    /// Tags closed WHILE `inStringMode` is true — i.e. `# tag` markup emitted
    /// inside the `ev str …/str /ev` block that builds a choice's own display
    /// text (`WeaveEmitter.choicePointNodes`), as opposed to a tag on a plain
    /// content line (which is never inside a `str`/`/str` span). Reset when a
    /// new `str` block opens; drained by `InkEngine.resolveChoiceTextAndTags`
    /// into the constructed `ChoiceData.tags` — mirrors the C# reference
    /// (`Story.PopChoiceStringAndTags`), which pops `Tag` objects off the same
    /// eval-stack region as the choice string, rather than the generic
    /// `currentTags` a content line's tags land in.
    var stringModeTags: [String]

    var lastCompletedLine: String

    // Full container execution stack for save/restore.
    // Each frame holds the container's absolute path from the story root
    // (`pathFromRoot`) and the current execution index within that container.
    var stackFrames: [ContainerStackFrame]

    /// Pending tunnel and function returns, top last (ADR-017). Saved as the
    /// legacy return-address strings (ADR-018, see `CallStackElement`).
    var returnStack: [CallStackElement]

    /// Paths of choices that have already been taken (once-only suppression).
    /// Serialised as a sorted array of dotted strings for deterministic JSON output.
    var chosenChoiceTargets: Set<ContainerPath>

    /// When true, glue `<>` is in force and every `\n` is suppressed. Reset
    /// when non-whitespace text reaches the output stream, as the reference
    /// keeps its glue until `isNonWhitespace` text is pushed.
    var suppressNextNewline: Bool

    /// Per-function-call temp-variable scope. Each frame is a `[String: InkValue]`
    /// of local temp variables declared inside that function call. Pushed by
    /// `applyFunctionCall`, popped by `applyFunctionReturn`. Empty outside any
    /// function call.
    ///
    /// Without this, `temp= x` inside a function call leaks into
    /// `variablesState` as a global. Two consecutive ref-param function calls
    /// (e.g. The Intercept's `~ raise(forceful); ~ raise(evasive)`) corrupt
    /// state because the second call's `temp= x` writes through the previous
    /// call's stale pointer instead of replacing the local — see
    /// `distill/upstream-issues.md` Issue 5 (bug 2). This implements the
    /// DESIGN D5 Option A scope that was deferred at original Tier 3 delivery.
    var callFrameVariables: [[String: InkValue]]

    init() {
        pointer = StoryPointer(containerPath: .root, index: 0)
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
        stringModeTags = []
        lastCompletedLine = ""
        stackFrames = []
        returnStack = []
        chosenChoiceTargets = []
        suppressNextNewline = false
        callFrameVariables = []
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case pointer, outputStream, outputStreamTags, variablesState, visitCounts, currentTags
        case isEnded, currentChoices, evalStack
        case inTagMode, tagAccumulator, inStringMode, stringAccumulator, stringModeTags
        case lastCompletedLine, stackFrames, returnStack
        case chosenChoiceTargets, suppressNextNewline
        case callFrameVariables
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pointer              = try container.decode(StoryPointer.self,         forKey: .pointer)
        outputStream         = OutputStreamWire(
            strings: try container.decode([String].self, forKey: .outputStream),
            tags: try container.decodeIfPresent([PendingOutputTag].self, forKey: .outputStreamTags) ?? []
        ).items
        variablesState       = try container.decode([String: InkValue].self,   forKey: .variablesState)
        let savedVisitCounts = try container.decode([String: Int].self,        forKey: .visitCounts)
        visitCounts          = savedVisitCounts.reduce(into: [:]) { $0[ContainerPath(savedKey: $1.key)] = $1.value }
        currentTags          = try container.decode([String].self,             forKey: .currentTags)
        isEnded              = try container.decode(Bool.self,                 forKey: .isEnded)
        currentChoices       = try container.decode([ChoiceData].self,         forKey: .currentChoices)
        evalStack            = try container.decode([InkValue].self,           forKey: .evalStack)
        inTagMode            = try container.decode(Bool.self,                 forKey: .inTagMode)
        tagAccumulator       = try container.decode(String.self,               forKey: .tagAccumulator)
        inStringMode         = try container.decode(Bool.self,                 forKey: .inStringMode)
        stringAccumulator    = try container.decode(String.self,               forKey: .stringAccumulator)
        stringModeTags       = try container.decodeIfPresent([String].self,    forKey: .stringModeTags) ?? []
        lastCompletedLine    = try container.decode(String.self,               forKey: .lastCompletedLine)
        stackFrames          = try container.decode([ContainerStackFrame].self, forKey: .stackFrames)
        returnStack          = try container.decodeIfPresent([CallStackElement].self, forKey: .returnStack) ?? []
        let chosenTargetsArray = try container.decodeIfPresent([String].self,  forKey: .chosenChoiceTargets) ?? []
        chosenChoiceTargets  = Set(chosenTargetsArray.map(ContainerPath.init(savedKey:)))
        suppressNextNewline  = try container.decodeIfPresent(Bool.self,        forKey: .suppressNextNewline) ?? false
        callFrameVariables   = try container.decodeIfPresent([[String: InkValue]].self, forKey: .callFrameVariables) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pointer,           forKey: .pointer)
        let outputWire = OutputStreamWire(outputStream)
        try container.encode(outputWire.strings, forKey: .outputStream)
        if outputWire.tags.isEmpty == false {
            try container.encode(outputWire.tags, forKey: .outputStreamTags)
        }
        try container.encode(variablesState,    forKey: .variablesState)
        let savedVisitCounts = visitCounts.reduce(into: [String: Int]()) { $0[$1.key.description] = $1.value }
        try container.encode(savedVisitCounts,  forKey: .visitCounts)
        try container.encode(currentTags,       forKey: .currentTags)
        try container.encode(isEnded,           forKey: .isEnded)
        try container.encode(currentChoices,    forKey: .currentChoices)
        try container.encode(evalStack,         forKey: .evalStack)
        try container.encode(inTagMode,         forKey: .inTagMode)
        try container.encode(tagAccumulator,    forKey: .tagAccumulator)
        try container.encode(inStringMode,      forKey: .inStringMode)
        try container.encode(stringAccumulator, forKey: .stringAccumulator)
        try container.encode(stringModeTags,    forKey: .stringModeTags)
        try container.encode(lastCompletedLine, forKey: .lastCompletedLine)
        try container.encode(stackFrames,       forKey: .stackFrames)
        try container.encode(returnStack,       forKey: .returnStack)
        try container.encode(chosenChoiceTargets.map(\.description).sorted(), forKey: .chosenChoiceTargets)
        try container.encode(suppressNextNewline, forKey: .suppressNextNewline)
        try container.encode(callFrameVariables,  forKey: .callFrameVariables)
    }
}

// MARK: - ContainerPath save wire (ADR-018)

/// The legacy string forms a `ContainerPath` takes in a save, kept byte-identical
/// so saves cross builds in both directions. Parsing never fails and never reads a
/// path as relative: a state key is always absolute, and `PathComponent(parsing:)`
/// round-trips every component through `description`.
extension ContainerPath {
    /// `["a", "0", "g-2"]`, the form of `pointer.containerPath` and `pathFromRoot`.
    init(savedComponents: [String]) {
        self.init(components: savedComponents.map(PathComponent.init(parsing:)))
    }

    var savedComponents: [String] {
        components.map(\.description)
    }

    /// `"a.0.g-2"`, the form of a `visitCounts` key and a `chosenChoiceTargets`
    /// entry. "" is the root, not one empty name.
    init(savedKey: String) {
        let saved = savedKey.isEmpty ? [] : savedKey.split(separator: ".", omittingEmptySubsequences: false)
        self.init(savedComponents: saved.map(String.init))
    }
}

// MARK: - Float printing (ADR-024 §2)

/// The text of an ink float, spelled as inklecate spells it.
///
/// ink floats are 32-bit and print with C# `float.ToString(InvariantCulture)`
/// (Value.cs FloatValue; inkle/ink#842, maintainer: "just the default C#
/// behaviour"). InkSwift stores and computes in `Double` (ADR-024 §1) and only
/// prints the 32-bit value: the shortest round-trip digits of `Float(value)`,
/// laid out the .NET way — fixed notation while the decimal point sits within
/// nine digits (`100000000`, `0.0001`), otherwise `1.5E-05` / `1E+20`, and
/// `Infinity`, `-Infinity`, `NaN`. Every float-to-text site goes through here.
struct InkFloatText {
    /// .NET "G" round-trip for `float`: scientific when the decimal exponent
    /// exceeds the float round-trip precision (9) or falls below -4.
    private static let maxFixedScale = 9
    private static let minFixedScale = -3

    let text: String

    init(_ value: Double) {
        let single = Float(value)
        if single.isNaN {
            text = "NaN"
        } else if single.isInfinite {
            text = single < 0 ? "-Infinity" : "Infinity"
        } else {
            let sign = single.sign == .minus ? "-" : ""
            text = sign + Self.layout(ShortestDigits(single.magnitude))
        }
    }

    private static func layout(_ number: ShortestDigits) -> String {
        if number.digits.isEmpty { return "0" }
        if number.scale > maxFixedScale || number.scale < minFixedScale {
            return scientific(number)
        }
        return fixed(number)
    }

    private static func fixed(_ number: ShortestDigits) -> String {
        let digits = number.digits
        if number.scale <= 0 {
            return "0." + String(repeating: "0", count: -number.scale) + digits
        }
        if number.scale >= digits.count {
            return digits + String(repeating: "0", count: number.scale - digits.count)
        }
        let point = digits.index(digits.startIndex, offsetBy: number.scale)
        return digits[..<point] + "." + digits[point...]
    }

    private static func scientific(_ number: ShortestDigits) -> String {
        let digits = number.digits
        let rest = digits.dropFirst()
        let mantissa = rest.isEmpty ? String(digits.prefix(1)) : digits.prefix(1) + "." + rest
        let exponent = number.scale - 1
        let exponentDigits = String(abs(exponent))
        let padded = exponentDigits.count < 2 ? "0" + exponentDigits : exponentDigits
        return mantissa + "E" + (exponent < 0 ? "-" : "+") + padded
    }
}

/// The shortest round-trip decimal digits of a finite, non-negative `Float`,
/// as `0.digits × 10^scale`, read off Swift's own shortest-form `description`
/// (`"123.45"`, `"1.5e-05"`). Leading and trailing zeros are dropped; zero has
/// no digits.
private struct ShortestDigits {
    let digits: String
    let scale: Int

    init(_ magnitude: Float) {
        let parts = magnitude.description.split(separator: "e")
        let exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        let integerPart = mantissa[0]
        let allDigits = integerPart + (mantissa.count > 1 ? mantissa[1] : "")
        let significant = allDigits.drop { $0 == "0" }
        let leadingZeros = allDigits.count - significant.count
        digits = String(significant.reversed().drop { $0 == "0" }.reversed())
        scale = integerPart.count + exponent - leadingZeros
    }
}
