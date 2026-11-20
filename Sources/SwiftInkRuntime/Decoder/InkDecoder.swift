import Foundation

struct InkDecoder {

    // MARK: - Control command and native function classification sets

    // The reference vocabulary (`JsonSerialisation.cs` `_controlCommandNames`,
    // `NativeFunctionCall.cs`) splits three ways: tokens the engine executes, tokens
    // it does not support yet (`NativeFunctionCatalog.unsupportedFeatureByToken`),
    // and anything else, which is not ink JSON at all and makes the story malformed
    // — as the reference's "Failed to convert token to runtime object". Natives
    // and refused tokens come from `NativeFunctionCatalog` (ADR-025).

    private static let controlCommands: Set<String> = [
        "ev", "/ev", "out", "pop", "->->", "~ret", "du", "str", "/str",
        "nop", "visit", "done", "end", "<>"
    ]

    // MARK: - Public API

    func decode(_ data: Data) throws -> ContainerNode {
        guard case .object(let topLevel) = try InkJSONReader.read(Array(data)) else {
            throw InkDecodeError.malformedJSON
        }
        if case .int(let inkVersion)? = topLevel["inkVersion"], inkVersion < 20 {
            throw InkDecodeError.unsupportedInkVersion(inkVersion)
        }
        guard case .array(let rootArray)? = topLevel["root"] else {
            throw InkDecodeError.malformedJSON
        }
        return try parseStory(rootArray)
    }

    /// Parse the root container, refusing the story if any part of it, visited or
    /// not, uses a feature the runtime does not support (issue #32).
    private func parseStory(_ rootArray: [InkJSONValue]) throws -> ContainerNode {
        var log = UnsupportedFeatureLog()
        let root = try parseContainer(rootArray, at: [], log: &log)
        guard log.isEmpty else {
            throw InkDecodeError.unsupportedFeatures(log.features)
        }
        return root
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

        // Earned Trust (ADR-013 DD-4, ADR-023): exercise the number/bool
        // classification, the part of decoding that has gone wrong before —
        // CoreFoundation type identity on Linux, then JSONDecoder typing `2.0` as
        // an int (issue #37). A drift fails HERE, surfaced as
        // StoryError.decoderProbeFailure at Story.init, rather than shipping a
        // silently wrong story ("2.5" -> "2", "true" -> "1", "1.0 / 3" -> "0").
        try probeScalarTyping(of: Self.scalarProbeFixture)
        try probePathPayloads()
    }

    /// The scalar fixture: a fraction, a bool, an int, and the whole-number
    /// float tokens inklecate writes (`2.0`, `1e2`), which must stay floats.
    static let scalarProbeFixture = #"{"inkVersion":21,"root":[2.5,true,42,2.0,1e2,null],"listDefs":{}}"#

    /// Decode `fixture` and check that its five scalars are typed float, bool,
    /// int, float, float, or throw `probeClassificationDrift`.
    func probeScalarTyping(of fixture: String) throws {
        let scalars = try decode(Data(fixture.utf8)).children
        guard scalars.count == 5,
              case .floatValue = scalars[0],
              case .boolValue = scalars[1],
              case .intValue = scalars[2],
              case .floatValue = scalars[3],
              case .floatValue = scalars[4] else {
            throw InkDecodeError.probeClassificationDrift
        }
    }

    /// Earned Trust (typed-runtime-paths): path payloads are parsed once, here, so a
    /// relative `.^` read count, a `->t->` tunnel target and a function-call target
    /// must reach the engine as the typed nodes it resolves — never re-parsed later.
    private func probePathPayloads() throws {
        let pathProbe = #"{"inkVersion":21,"root":[{"CNT?":".^"},{"->t->":"t"},{"f()":"f"},null],"listDefs":{}}"#
        guard let pathData = pathProbe.data(using: .utf8) else {
            throw InkDecodeError.malformedJSON
        }
        let pathRoot = try decode(pathData)
        guard pathRoot.children.count == 3,
              case .readCount(.relative(parentSteps: 1, tail: [])) = pathRoot.children[0],
              case .tunnelDivert(.absolute(let tunnelTarget)) = pathRoot.children[1],
              tunnelTarget.components == [.name("t")],
              case .functionCall(.absolute(let functionTarget)) = pathRoot.children[2],
              functionTarget.components == [.name("f")] else {
            throw InkDecodeError.probeClassificationDrift
        }
    }

    // MARK: - Container parsing

    /// Parse a container found at `location`: the author-visible names (knots,
    /// stitches, labels) of the containers around it. Unsupported tokens inside
    /// it are recorded in `log` with that location.
    private func parseContainer(
        _ array: [InkJSONValue],
        at location: [String],
        log: inout UnsupportedFeatureLog
    ) throws -> ContainerNode {
        guard case .object(let metaDict)? = array.last else {
            // Last element is absent, null, or not a dict — treat all elements as content
            let contentItems: [InkJSONValue]
            if case .null? = array.last {
                contentItems = Array(array.dropLast())
            } else {
                contentItems = array
            }
            let children = try contentItems.compactMap { try classify($0, at: location, log: &log) }
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
        let here = UnsupportedFeatureLog.location(location, entering: name)
        var namedContent = try parseNamedContent(from: metaDict, at: here, log: &log)
        let children = try contentItems.compactMap { try classify($0, at: here, log: &log) }
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

    private func parseNamedContent(
        from metaDict: [String: InkJSONValue],
        at location: [String],
        log: inout UnsupportedFeatureLog
    ) throws -> [String: ContainerNode] {
        var named: [String: ContainerNode] = [:]
        for (key, value) in metaDict where key != "#f" && key != "#n" {
            if case .array(let subArray) = value {
                let keyLocation = UnsupportedFeatureLog.location(location, entering: key)
                named[key] = try parseContainer(subArray, at: keyLocation, log: &log)
            }
        }
        return named
    }

    // MARK: - Node classification

    /// Classify `element`, or record it in `log` at `location` and leave it out
    /// when it is a feature the runtime does not support.
    private func classify(
        _ element: InkJSONValue,
        at location: [String],
        log: inout UnsupportedFeatureLog
    ) throws -> NodeKind? {
        guard let feature = Self.unsupportedFeature(of: element) else {
            return try classify(element, at: location, recordingIn: &log)
        }
        log.record(feature, at: location)
        return nil
    }

    private func classify(
        _ element: InkJSONValue,
        at location: [String],
        recordingIn log: inout UnsupportedFeatureLog
    ) throws -> NodeKind? {
        switch element {
        case .null:
            return nil
        case .string(let string):
            return try classifyString(string)
        case .bool(let value):
            return .boolValue(value)
        case .int(let value):
            return .intValue(value)
        case .double(let value):
            return .floatValue(value)
        case .array(let array):
            return .container(try parseContainer(array, at: location, log: &log))
        case .object(let dict):
            return try classifyDict(dict)
        }
    }

    /// The unsupported feature a token stands for, or `nil`: one of
    /// the catalog's refused tokens (issue #32: playing on would silently print or
    /// skip them), a list value, an external function call, or a tag in
    /// the inkVersion 20 format (`{"#": "text"}`, replaced by `"#"`…`"/#"` in 21).
    private static func unsupportedFeature(of element: InkJSONValue) -> String? {
        if case .string(let string) = element { return NativeFunctionCatalog.unsupportedFeature(forToken: string) }
        guard case .object(let dict) = element else { return nil }
        if dict["list"] != nil { return UnsupportedConstruct.list.name }
        if dict["x()"] != nil { return UnsupportedConstruct.external.name }
        if dict["#"] != nil { return "tags in the inkVersion 20 format (recompile with a current inklecate)" }
        return nil
    }

    private static let fixedTokens: [String: NodeKind] = [
        "\n": .newline, "#": .tagOpen, "/#": .tagClose, "void": .voidValue,
    ]

    private func classifyString(_ string: String) throws -> NodeKind {
        if let node = Self.fixedTokens[string] { return node }
        if string.hasPrefix("^") { return .text(String(string.dropFirst())) }
        if Self.controlCommands.contains(string) { return .controlCommand(string) }
        if let native = NativeFunctionCatalog.supportedNative(forToken: string) { return .nativeFunction(native) }
        throw InkDecodeError.malformedJSON
    }

    private func classifyDict(_ dict: [String: InkJSONValue]) throws -> NodeKind {
        if let divert = classifyDivert(dict) {
            return divert
        }
        if let target = dict["*"]?.stringValue {
            let rawFlags = dict["flg"]?.intValue ?? 0
            return .choicePoint(target: PathReference(parsing: target), flags: ChoiceFlags(rawValue: rawFlags))
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
            return .readCount(PathReference(parsing: key))
        }
        if let name = dict["^var"]?.stringValue, let contextIndex = dict["ci"]?.intValue {
            return .variablePointer(name: name, contextIndex: contextIndex)
        }
        throw InkDecodeError.malformedJSON
    }

    /// A divert-shaped object (a divert-target value, a tunnel divert, a divert
    /// or a function call), or `nil` for any other object.
    private func classifyDivert(_ dict: [String: InkJSONValue]) -> NodeKind? {
        if let path = dict["^->"]?.stringValue {
            return .pushDivertTarget(PathReference(parsing: path))
        }
        if let target = dict["->t->"]?.stringValue {
            return .tunnelDivert(target: PathReference(parsing: target))
        }
        if let target = dict["->"]?.stringValue {
            let isConditional = dict["c"]?.boolValue ?? false
            let divertTarget: DivertTarget = dict["var"] != nil
                ? .variable(name: target)
                : .path(PathReference(parsing: target))
            return .divert(target: divertTarget, isConditional: isConditional)
        }
        if let target = dict["f()"]?.stringValue {
            return .functionCall(target: PathReference(parsing: target))
        }
        return nil
    }
}

// MARK: - Portable Ink JSON value model

/// The heterogeneous ink JSON tree, as `InkJSONReader` reads it. Scalar
/// typing follows the token text — `2.0` is a `.double`, `2` an `.int` —
/// never a platform's runtime type identity (ADR-013, ADR-023).
indirect enum InkJSONValue: Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([InkJSONValue])
    case object([String: InkJSONValue])
    case null

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
}

// MARK: - Errors

enum InkDecodeError: Error, Equatable {
    case malformedJSON
    /// Valid ink the runtime does not support yet (issue #32).
    case unsupportedFeatures([UnsupportedFeature])
    case unsupportedInkVersion(Int)
    // DD-4: the startup probe found a JSON scalar mis-typed on this platform
    // (a float/bool/int did not classify to the expected NodeKind) — the story
    // refuses to start rather than play with silently wrong values.
    case probeClassificationDrift
}
