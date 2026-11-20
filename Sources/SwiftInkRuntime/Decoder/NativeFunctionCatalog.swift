// The one table of ink's built-in functions and unsupported constructs (ADR-025).
// The decoder accepts and refuses tokens from it, the TreeWalker dispatches its
// supported natives exhaustively, and the compiler builds native nodes from it,
// so all three share one vocabulary. Names and arities follow the reference's
// `NativeFunctionCall.cs` and `FunctionCall.cs`.

/// A built-in function the engine executes, by its runtime token.
enum NativeFunction: String, CaseIterable, CustomStringConvertible {
    case add = "+"
    case subtract = "-"
    case divide = "/"
    case multiply = "*"
    case modulo = "%"
    /// Arithmetic negation; the reference names it `_` to keep it apart from `-`.
    case negate = "_"
    case equal = "=="
    case greater = ">"
    case less = "<"
    case greaterOrEqual = ">="
    case lessOrEqual = "<="
    case notEqual = "!="
    case not = "!"
    case and = "&&"
    case or = "||"
    case min = "MIN"
    case max = "MAX"
    case floor = "FLOOR"
    case ceiling = "CEILING"
    case int = "INT"
    case float = "FLOAT"
    /// SEED_RANDOM is accepted: without the RNG tokens, which are refused, a seed
    /// has no observable effect, so ignoring it plays exactly as the reference does.
    case seedRandom = "srnd"

    /// The token ink JSON spells this native with.
    var token: String { rawValue }

    var description: String { token }
}

/// One catalog row: what the author writes, what the runtime reads, and
/// whether the engine supports it.
struct NativeFunctionEntry {
    enum Status {
        case supported(NativeFunction)
        /// Refused, under the name an author knows the feature by.
        case unsupported(feature: String)
    }

    let sourceName: String
    let token: String
    let arity: Int
    let status: Status

    static func supported(_ native: NativeFunction, source: String? = nil, arity: Int) -> NativeFunctionEntry {
        NativeFunctionEntry(sourceName: source ?? native.token, token: native.token, arity: arity, status: .supported(native))
    }

    static func unsupported(_ source: String, token: String? = nil, arity: Int, feature: String) -> NativeFunctionEntry {
        NativeFunctionEntry(sourceName: source, token: token ?? source, arity: arity, status: .unsupported(feature: feature))
    }
}

/// Statement-level constructs neither the compiler nor the runtime supports,
/// under the one name both report them by.
enum UnsupportedConstruct: CaseIterable {
    case thread, list, external, include, shuffle

    var name: String {
        switch self {
        case .thread: return "threads (<-)"
        case .list: return "LIST"
        case .external: return "EXTERNAL functions"
        case .include: return "INCLUDE"
        case .shuffle: return "shuffle {~a|b}"
        }
    }

    /// The bare token the construct compiles to in ink JSON, if it has one.
    /// LIST and EXTERNAL appear as objects (`{"list": …}`, `{"x()": …}`) and
    /// INCLUDE never reaches the runtime.
    var runtimeToken: String? {
        switch self {
        case .thread: return "thread"
        case .shuffle: return "seq"
        case .list, .external, .include: return nil
        }
    }
}

enum NativeFunctionCatalog {

    static let entries: [NativeFunctionEntry] = supportedEntries + unsupportedEntries

    private static let supportedEntries: [NativeFunctionEntry] =
        [NativeFunction.add, .subtract, .divide, .multiply, .modulo, .equal, .greater, .less,
         .greaterOrEqual, .lessOrEqual, .notEqual, .and, .or, .min, .max]
            .map { .supported($0, arity: 2) }
        + [NativeFunction.not, .floor, .ceiling, .int, .float].map { .supported($0, arity: 1) }
        + [.supported(.negate, source: "-", arity: 1),
           .supported(.seedRandom, source: "SEED_RANDOM", arity: 1)]

    private static let unsupportedEntries: [NativeFunctionEntry] = [
        .unsupported("CHOICE_COUNT", token: "choiceCnt", arity: 0, feature: "CHOICE_COUNT()"),
        .unsupported("TURNS", token: "turn", arity: 0, feature: "TURNS()"),
        .unsupported("TURNS_SINCE", token: "turns", arity: 1, feature: "TURNS_SINCE()"),
        .unsupported("READ_COUNT", token: "readc", arity: 1, feature: "READ_COUNT() of a divert-target variable"),
        .unsupported("RANDOM", token: "rnd", arity: 2, feature: "RANDOM()"),
        .unsupported("POW", arity: 2, feature: "POW()"),
        .unsupported("?", arity: 2, feature: "? (contains)"),
        .unsupported("!?", arity: 2, feature: "!? (does not contain)"),
    ] + listEntries

    private static let listFeature = UnsupportedConstruct.list.name

    /// The list natives; every one is refused as the LIST feature.
    private static let listEntries: [NativeFunctionEntry] = [
        .unsupported("<list name>", token: "listInt", arity: 1, feature: listFeature),
        .unsupported("LIST_RANGE", token: "range", arity: 3, feature: listFeature),
        .unsupported("LIST_RANDOM", token: "lrnd", arity: 1, feature: listFeature),
        .unsupported("^", token: "L^", arity: 2, feature: listFeature),
    ] + ["LIST_MIN", "LIST_MAX", "LIST_ALL", "LIST_COUNT", "LIST_VALUE", "LIST_INVERT"]
        .map { .unsupported($0, arity: 1, feature: listFeature) }

    private static let supportedByToken: [String: NativeFunction] = Dictionary(
        uniqueKeysWithValues: NativeFunction.allCases.map { ($0.token, $0) })

    /// Every valid ink token the runtime refuses, by its feature name: the
    /// unsupported natives and the statement-level constructs with a token.
    static let unsupportedFeatureByToken: [String: String] = {
        var features: [String: String] = [:]
        for entry in entries {
            if case .unsupported(let feature) = entry.status { features[entry.token] = feature }
        }
        for construct in UnsupportedConstruct.allCases {
            if let token = construct.runtimeToken { features[token] = construct.name }
        }
        return features
    }()

    private static let entryByNative: [NativeFunction: NativeFunctionEntry] = {
        var byNative: [NativeFunction: NativeFunctionEntry] = [:]
        for entry in entries {
            if case .supported(let native) = entry.status { byNative[native] = entry }
        }
        return byNative
    }()

    static func supportedNative(forToken token: String) -> NativeFunction? {
        supportedByToken[token]
    }

    static func unsupportedFeature(forToken token: String) -> String? {
        unsupportedFeatureByToken[token]
    }

    static func entry(for native: NativeFunction) -> NativeFunctionEntry {
        guard let entry = entryByNative[native] else {
            preconditionFailure("NativeFunctionCatalog has no entry for \(native)")
        }
        return entry
    }
}
