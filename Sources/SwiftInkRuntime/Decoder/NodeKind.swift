// NodeKind is intentionally internal — never public (Rule R2)
internal enum NodeKind {
    case container(ContainerNode)
    case text(String)
    case newline
    case divert(target: String, isConditional: Bool)
    case choicePoint(flags: Int)
    case controlCommand(String)
    case nativeFunction(String)
    case intValue(Int)
    case floatValue(Double)
    case variableAssignment(name: String, isGlobal: Bool)
    case variableReference(name: String)
    case tagOpen
    case tagClose
    case voidValue
}
