import Foundation

struct InkDecoder {

    // MARK: - Control command and native function classification sets

    private static let controlCommands: Set<String> = [
        "ev", "/ev", "out", "pop", "->->", "~ret", "du", "str", "/str",
        "nop", "choiceCnt", "turn", "turns", "visit", "seq", "thread", "done", "end",
        "<>"
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
        let topValue: InkJSONValue
        do {
            topValue = try JSONDecoder().decode(InkJSONValue.self, from: data)
        } catch {
            throw InkDecodeError.malformedJSON
        }
        guard case .object(let topLevel) = topValue else {
            throw InkDecodeError.malformedJSON
        }
        if case .int(let inkVersion)? = topLevel["inkVersion"], inkVersion < 20 {
            throw InkDecodeError.unsupportedInkVersion(inkVersion)
        }
        guard case .array(let rootArray)? = topLevel["root"] else {
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

        // Earned Trust (ADR-013 DD-4): exercise the number/bool classification
        // substrate, which is exactly what differs across platforms — CoreFoundation
        // type identity is unavailable under swift-corelibs-foundation, and the
        // JSONDecoder path must reproduce macOS int/float/bool tagging. Decode a
        // fixture carrying a float, a bool, and an int, and verify each keeps its
        // type. On a platform whose JSON decoding misclassifies scalars this fails
        // HERE — surfaced as StoryError.decoderProbeFailure at Story.init — rather
        // than shipping a silently wrong story ("2.5" -> "2", "true" -> "1").
        let scalarProbe = #"{"inkVersion":21,"root":[2.5,true,42,null],"listDefs":{}}"#
        guard let scalarData = scalarProbe.data(using: .utf8) else {
            throw InkDecodeError.malformedJSON
        }
        let scalarRoot = try decode(scalarData)
        guard scalarRoot.children.count >= 3,
              case .floatValue = scalarRoot.children[0],
              case .boolValue = scalarRoot.children[1],
              case .intValue = scalarRoot.children[2] else {
            throw InkDecodeError.probeClassificationDrift
        }
    }

    // MARK: - Container parsing

    private func parseContainer(_ array: [InkJSONValue]) -> ContainerNode {
        guard case .object(let metaDict)? = array.last else {
            // Last element is absent, null, or not a dict — treat all elements as content
            let contentItems: [InkJSONValue]
            if case .null? = array.last {
                contentItems = Array(array.dropLast())
            } else {
                contentItems = array
            }
            let children = contentItems.compactMap { classify($0) }
            // Named sequential children are accessible by name (mirrors C# TryAddNamedContent).
            var namedContent: [String: ContainerNode] = [:]
            for child in children {
                if case .container(let sub) = child, let subName = sub.name {
                    namedContent[subName] = sub
                }
            }
            return ContainerNode(children: children, namedContent: namedContent, flags: 0, name: nil)
        }

        let contentItems = Array(array.dropLast())
        let flags = metaDict["#f"]?.intValue ?? 0
        let name = metaDict["#n"]?.stringValue
        var namedContent = parseNamedContent(from: metaDict)
        let children = contentItems.compactMap { classify($0) }
        // Named sequential children are accessible by name (mirrors C# TryAddNamedContent).
        // Named-only content from the metadata dict takes precedence if keys collide.
        for child in children {
            if case .container(let sub) = child, let subName = sub.name,
               namedContent[subName] == nil {
                namedContent[subName] = sub
            }
        }
        return ContainerNode(children: children, namedContent: namedContent, flags: flags, name: name)
    }

    private func parseNamedContent(from metaDict: [String: InkJSONValue]) -> [String: ContainerNode] {
        var named: [String: ContainerNode] = [:]
        for (key, value) in metaDict where key != "#f" && key != "#n" {
            if case .array(let subArray) = value {
                named[key] = parseContainer(subArray)
            }
        }
        return named
    }

    // MARK: - Node classification

    private func classify(_ element: InkJSONValue) -> NodeKind? {
        switch element {
        case .null:
            return nil
        case .string(let string):
            return classifyString(string)
        case .bool(let value):
            return .boolValue(value)
        case .int(let value):
            return .intValue(value)
        case .double(let value):
            return .floatValue(value)
        case .array(let array):
            return .container(parseContainer(array))
        case .object(let dict):
            return classifyDict(dict)
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

    private func classifyDict(_ dict: [String: InkJSONValue]) -> NodeKind {
        if let path = dict["^->"]?.stringValue {
            return .pushDivertTarget(path)
        }
        if let target = dict["->t->"]?.stringValue {
            return .tunnelDivert(target: target)
        }
        if let target = dict["->"]?.stringValue {
            let isConditional = dict["c"]?.boolValue ?? false
            let isVariable = dict["var"] != nil
            return .divert(target: target, isConditional: isConditional, isVariable: isVariable)
        }
        if let target = dict["f()"]?.stringValue {
            // Function-call divert: tagged with "f():" prefix so the engine
            // knows to push a return address before jumping.
            return .divert(target: "f():" + target, isConditional: false, isVariable: false)
        }
        if let target = dict["*"]?.stringValue {
            let rawFlags = dict["flg"]?.intValue ?? 0
            return .choicePoint(target: target, flags: ChoiceFlags(rawValue: rawFlags))
        }
        if let name = dict["VAR="]?.stringValue {
            return .variableAssignment(name: name, isGlobal: dict["re"] != nil)
        }
        if let name = dict["temp="]?.stringValue {
            return .variableAssignment(name: name, isGlobal: false)
        }
        if let name = dict["VAR?"]?.stringValue {
            return .variableReference(name: name)
        }
        if dict["#n"] != nil {
            // Named-container reference marker (e.g., {"#n":"$r1"}) — treated as a no-op node
            return .controlCommand("#n")
        }
        if let key = dict["CNT?"]?.stringValue {
            return .readCount(key)
        }
        if let name = dict["^var"]?.stringValue, let contextIndex = dict["ci"]?.intValue {
            return .variablePointer(name: name, contextIndex: contextIndex)
        }
        // Unknown dict node — surface the first key for diagnostics
        return .controlCommand(dict.keys.first ?? "?")
    }
}

// MARK: - Portable Ink JSON value model

/// A platform-stable, `Decodable` representation of the heterogeneous Ink JSON
/// tree. Scalar typing is driven by decode-success ORDER — Bool → Int → Double —
/// never by CoreFoundation type identity (`CFGetTypeID`/`CFNumberGetType`), which
/// is unavailable under swift-corelibs-foundation on Linux (ADR-013 / DD-1).
///
/// The ordering is load-bearing: a JSON `true`/`false` decodes as `.bool` before
/// `Int` is attempted; a whole number `42` decodes as `.int` before `Double` is
/// attempted; a fractional `2.5` fails `Int` and lands on `.double`.
private indirect enum InkJSONValue: Decodable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([InkJSONValue])
    case object([String: InkJSONValue])
    case null

    init(from decoder: Decoder) throws {
        // Keyed/unkeyed containers first so structural JSON (objects, arrays) is
        // modelled directly; scalars fall through to the single-value container.
        if let keyed = try? decoder.container(keyedBy: DynamicKey.self) {
            var object: [String: InkJSONValue] = [:]
            for key in keyed.allKeys {
                object[key.stringValue] = try keyed.decode(InkJSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var array: [InkJSONValue] = []
            if let count = unkeyed.count {
                array.reserveCapacity(count)
            }
            while !unkeyed.isAtEnd {
                array.append(try unkeyed.decode(InkJSONValue.self))
            }
            self = .array(array)
            return
        }

        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Int.self) {
            self = .int(value)
        } else if let value = try? single.decode(Double.self) {
            self = .double(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: single,
                debugDescription: "Unsupported Ink JSON scalar"
            )
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Coding key that accepts any JSON object key (Ink dictionaries are open-keyed).
    private struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}

// MARK: - Errors

enum InkDecodeError: Error {
    case malformedJSON
    case unsupportedInkVersion(Int)
    // DD-4: the startup probe found a JSON scalar mis-typed on this platform
    // (a float/bool/int did not classify to the expected NodeKind) — the story
    // refuses to start rather than play with silently wrong values.
    case probeClassificationDrift
}
