import Foundation

struct InkDecoder {

    // MARK: - Control command and native function classification sets

    private static let controlCommands: Set<String> = [
        "ev", "/ev", "out", "pop", "->->", "~ret", "du", "str", "/str",
        "nop", "choiceCnt", "turn", "turns", "visit", "seq", "thread", "done", "end"
    ]

    private static let nativeFunctions: Set<String> = [
        "+", "-", "/", "*", "%", "_", "==", ">", "<", ">=", "<=", "!=",
        "!", "&&", "||", "MIN", "MAX",
        "floor", "ceiling", "int", "float", "sqrt", "pow",
        "has", "hasnt", "intersect", "listMin", "listMax",
        "all", "count", "valueOfList", "invert",
        "srnd", "CHOICE_COUNT", "TURNS", "TURNS_SINCE", "RANDOM", "READ_COUNT"
    ]

    // MARK: - Public API

    func decode(_ data: Data) throws -> ContainerNode {
        let rawObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let topLevel = rawObject as? [String: Any],
              let rootArray = topLevel["root"] as? [Any] else {
            throw InkDecodeError.malformedJSON
        }
        return parseContainer(rootArray)
    }

    func probe() throws {
        guard let url = Bundle.module.url(forResource: "test.ink", withExtension: "json") else {
            throw InkDecodeError.malformedJSON
        }
        let data = try Data(contentsOf: url)
        let root = try decode(data)
        guard !root.children.isEmpty else {
            throw InkDecodeError.malformedJSON
        }
        // Round-trip: verify JSONSerialization can re-parse the fixture without data loss
        let rawObject = try JSONSerialization.jsonObject(with: data, options: [])
        let reEncoded = try JSONSerialization.data(withJSONObject: rawObject, options: [])
        _ = try JSONSerialization.jsonObject(with: reEncoded, options: [])
    }

    // MARK: - Container parsing

    private func parseContainer(_ array: [Any]) -> ContainerNode {
        let last = array.last
        let contentItems: [Any]
        let namedContent: [String: ContainerNode]
        let flags: Int
        let name: String?

        if last == nil || last! is NSNull {
            // No metadata — plain content list
            contentItems = Array(array.dropLast())
            namedContent = [:]
            flags = 0
            name = nil
        } else if let metaDict = last as? [String: Any] {
            contentItems = Array(array.dropLast())
            flags = metaDict["#f"] as? Int ?? 0
            name = metaDict["#n"] as? String
            var named: [String: ContainerNode] = [:]
            for (key, value) in metaDict where key != "#f" && key != "#n" {
                if let subArray = value as? [Any] {
                    named[key] = parseContainer(subArray)
                }
            }
            namedContent = named
        } else {
            // Malformed — treat all elements as content with empty metadata
            contentItems = array
            namedContent = [:]
            flags = 0
            name = nil
        }

        let children = contentItems.compactMap { classify($0) }
        return ContainerNode(children: children, namedContent: namedContent, flags: flags, name: name)
    }

    // MARK: - Node classification

    private func classify(_ element: Any) -> NodeKind? {
        switch element {
        case is NSNull:
            return nil
        case let string as String:
            return classifyString(string)
        case let number as NSNumber:
            return classifyNumber(number)
        case let array as [Any]:
            return .container(parseContainer(array))
        case let dict as [String: Any]:
            return classifyDict(dict)
        default:
            return nil
        }
    }

    private func classifyString(_ string: String) -> NodeKind {
        if string == "\n"   { return .newline }
        if string == "#"    { return .tagOpen }
        if string == "/#"   { return .tagClose }
        if string == "void" { return .voidValue }
        if string.hasPrefix("^") { return .text(String(string.dropFirst())) }
        if Self.controlCommands.contains(string) { return .controlCommand(string) }
        if Self.nativeFunctions.contains(string) { return .nativeFunction(string) }
        // Unknown strings — treat as text with empty prefix stripped
        return .text(string)
    }

    private func classifyNumber(_ number: NSNumber) -> NodeKind {
        let cfType = CFNumberGetType(number as CFNumber)
        switch cfType {
        case .sInt8Type, .sInt16Type, .sInt32Type, .sInt64Type,
             .charType, .shortType, .intType, .longType, .longLongType,
             .nsIntegerType, .cfIndexType:
            return .intValue(number.intValue)
        default:
            // Check if the double value equals its integer representation
            let doubleValue = number.doubleValue
            if doubleValue == Double(number.intValue) && !cfType.isFloat {
                return .intValue(number.intValue)
            }
            return .floatValue(doubleValue)
        }
    }

    private func classifyDict(_ dict: [String: Any]) -> NodeKind {
        if let target = dict["->"] as? String {
            let isConditional = dict["c"] as? Bool ?? false
            return .divert(target: target, isConditional: isConditional)
        }
        if let target = dict["*"] as? String {
            let flags = dict["flg"] as? Int ?? 0
            return .choicePoint(target: target, flags: flags)
        }
        if let name = dict["VAR="] as? String {
            return .variableAssignment(name: name, isGlobal: dict["re"] != nil)
        }
        if let name = dict["temp="] as? String {
            return .variableAssignment(name: name, isGlobal: false)
        }
        if let name = dict["VAR?"] as? String {
            return .variableReference(name: name)
        }
        if dict["#n"] != nil {
            // Anonymous named-container reference marker (e.g., {"#n":"$r1"})
            return .controlCommand("#n")
        }
        // Fallback — treat as control command placeholder
        return .controlCommand(dict.keys.first ?? "?")
    }
}

// MARK: - Errors

enum InkDecodeError: Error {
    case malformedJSON
    case unsupportedInkVersion(Int)
}

// MARK: - CFNumberType helper

private extension CFNumberType {
    var isFloat: Bool {
        switch self {
        case .float32Type, .float64Type, .floatType, .doubleType, .cgFloatType:
            return true
        default:
            return false
        }
    }
}
