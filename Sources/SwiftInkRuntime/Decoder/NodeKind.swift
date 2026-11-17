// NodeKind is intentionally internal — never public (Rule R2)
internal enum NodeKind {
    case container(ContainerNode)
    case text(String)
    case newline
    case divert(target: DivertTarget, isConditional: Bool)
    case pushDivertTarget(PathReference)
    case tunnelDivert(target: PathReference)
    case choicePoint(target: PathReference, flags: ChoiceFlags)
    case controlCommand(String)
    case nativeFunction(String)
    case intValue(Int)
    case floatValue(Double)
    case boolValue(Bool)
    case variableAssignment(name: String, isGlobal: Bool)
    case variableReference(name: String)
    case tagOpen
    case tagClose
    case voidValue
    case readCount(PathReference)
    case variablePointer(name: String, contextIndex: Int)
}

/// Where a `.divert` goes: a path written in the node, or the divert-target value
/// held by a variable (inklecate's `"var": true`), resolved when the divert runs.
enum DivertTarget: Hashable {
    case path(PathReference)
    case variable(name: String)
}
