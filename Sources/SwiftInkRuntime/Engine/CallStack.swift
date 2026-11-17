// Typed call-stack elements (ADR-017). The return stack holds one element per
// pending tunnel or function return; its save wire stays the legacy strings
// (ADR-018), so saves cross builds in both directions.

/// What pushed a call-stack element. C# `PushPopType` without
/// `FunctionEvaluationFromGame`: there is no EvaluateFunction API.
enum CallKind: Hashable {
    case tunnel
    case function

    /// The statement that pops this kind, as C# Story.cs names it in a refusal.
    fileprivate var popStatement: String {
        switch self {
        case .tunnel: "tunnel onwards statement (->->)"
        case .function: "function return statement (~ return)"
        }
    }
}

/// A pending return: where execution resumes once the tunnel or function that
/// pushed it returns. Mirrors C# `CallStack.Element(type, pointer)`.
struct CallStackElement: Hashable {
    let kind: CallKind
    let returnPath: ContainerPath
    let returnIndex: Int
}

extension Array where Element == CallStackElement {
    /// Whether the top element is of `kind`. C# `CallStack.CanPop(type)`.
    func canPop(_ kind: CallKind) -> Bool {
        last?.kind == kind
    }

    /// Removes and returns the top element if it is of `kind`; otherwise leaves
    /// the stack unchanged and returns nil. C# `CallStack.Pop(type)`.
    mutating func pop(_ kind: CallKind) -> CallStackElement? {
        canPop(kind) ? removeLast() : nil
    }

    /// The error for a refused `pop(kind)`: C# Story.cs ~1275-1288, where the
    /// expected statement is the top element's, or the end of flow when empty.
    func popRefusal(_ kind: CallKind) -> String {
        let expected = last?.kind.popStatement ?? "end of flow (-> END or choice)"
        return "Found \(kind.popStatement), when expected \(expected)"
    }
}

// MARK: - Legacy save wire (ADR-018)

/// A tunnel element is `"<dotted path>.<index>"` (`"<index>"` at the root), a
/// function element `"fnret:<dotted path>|<index>"` (`"fnret:|<index>"` at the
/// root). The tunnel form is ambiguous with a path whose last component is an
/// index: the LAST component is always the return index, as the runtime has
/// always resumed it. A string fitting neither form is rejected.
extension CallStackElement: Codable {
    private static let functionPrefix = "fnret:"
    private static let functionIndexSeparator: Character = "|"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let wire = try container.decode(String.self)
        guard let element = Self(legacyWire: wire) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not a legacy return-stack entry: \"\(wire)\"")
        }
        self = element
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(legacyWire)
    }

    private init?(legacyWire wire: String) {
        if wire.hasPrefix(Self.functionPrefix) {
            self.init(functionWire: wire.dropFirst(Self.functionPrefix.count))
        } else {
            self.init(tunnelWire: wire)
        }
    }

    private init?(functionWire: Substring) {
        guard let separator = functionWire.lastIndex(of: Self.functionIndexSeparator),
              let index = Self.returnIndex(functionWire[functionWire.index(after: separator)...]) else {
            return nil
        }
        let path = ContainerPath(savedKey: String(functionWire[..<separator]))
        self.init(kind: .function, returnPath: path, returnIndex: index)
    }

    private init?(tunnelWire: String) {
        let components = ContainerPath(savedKey: tunnelWire).components
        guard case .index(let index)? = components.last else { return nil }
        self.init(kind: .tunnel, returnPath: ContainerPath(components: components.dropLast()), returnIndex: index)
    }

    /// Only the canonical spelling of a non-negative integer, so it re-encodes identically.
    private static func returnIndex(_ string: Substring) -> Int? {
        guard case .index(let index) = PathComponent(parsing: String(string)) else { return nil }
        return index
    }

    private var legacyWire: String {
        switch kind {
        case .tunnel:
            return returnPath.appending(.index(returnIndex)).description
        case .function:
            return "\(Self.functionPrefix)\(returnPath)\(Self.functionIndexSeparator)\(returnIndex)"
        }
    }
}
