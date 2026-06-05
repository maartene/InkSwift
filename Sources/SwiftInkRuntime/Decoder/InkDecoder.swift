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
        guard let topLevel = rawObject as? [String: Any] else {
            throw InkDecodeError.malformedJSON
        }
        if let inkVersion = topLevel["inkVersion"] as? Int, inkVersion < 20 {
            throw InkDecodeError.unsupportedInkVersion(inkVersion)
        }
        guard let rootArray = topLevel["root"] as? [Any] else {
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
    }

    // MARK: - Container parsing

    private func parseContainer(_ array: [Any]) -> ContainerNode {
        guard let metaDict = array.last as? [String: Any] else {
            // Last element is absent, null, or not a dict — treat all elements as content
            let contentItems = array.last is NSNull ? Array(array.dropLast()) : array
            let children = contentItems.compactMap { classify($0) }
            return ContainerNode(children: children, namedContent: [:], flags: 0, name: nil)
        }

        let contentItems = Array(array.dropLast())
        let flags = metaDict["#f"] as? Int ?? 0
        let name = metaDict["#n"] as? String
        let namedContent = parseNamedContent(from: metaDict)
        let children = contentItems.compactMap { classify($0) }
        return ContainerNode(children: children, namedContent: namedContent, flags: flags, name: name)
    }

    private func parseNamedContent(from metaDict: [String: Any]) -> [String: ContainerNode] {
        var named: [String: ContainerNode] = [:]
        for (key, value) in metaDict where key != "#f" && key != "#n" {
            if let subArray = value as? [Any] {
                named[key] = parseContainer(subArray)
            }
        }
        return named
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
        // Unknown string token — surface as plain text
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
            return .floatValue(number.doubleValue)
        }
    }

    private func classifyDict(_ dict: [String: Any]) -> NodeKind {
        if let path = dict["^->"] as? String {
            return .pushDivertTarget(path)
        }
        if let target = dict["->"] as? String {
            let isConditional = dict["c"] as? Bool ?? false
            let isVariable = dict["var"] != nil
            return .divert(target: target, isConditional: isConditional, isVariable: isVariable)
        }
        if let target = dict["f()"] as? String {
            // Function-call divert: tagged with "f():" prefix so the engine
            // knows to push a return address before jumping.
            return .divert(target: "f():" + target, isConditional: false, isVariable: false)
        }
        if let target = dict["*"] as? String {
            let rawFlags = dict["flg"] as? Int ?? 0
            return .choicePoint(target: target, flags: ChoiceFlags(rawValue: rawFlags))
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
            // Named-container reference marker (e.g., {"#n":"$r1"}) — treated as a no-op node
            return .controlCommand("#n")
        }
        if let key = dict["CNT?"] as? String {
            return .readCount(key)
        }
        // Unknown dict node — surface the first key for diagnostics
        return .controlCommand(dict.keys.first ?? "?")
    }
}

// MARK: - Errors

enum InkDecodeError: Error {
    case malformedJSON
    case unsupportedInkVersion(Int)
}

