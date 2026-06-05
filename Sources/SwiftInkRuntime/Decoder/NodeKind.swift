// NodeKind is intentionally internal — never public (Rule R2)
internal enum NodeKind {
    case container(ContainerNode)
    case text(String)
    case newline
    case divert(target: String, isConditional: Bool, isVariable: Bool)
    case pushDivertTarget(String)
    case choicePoint(target: String, flags: ChoiceFlags)
    case controlCommand(String)
    case nativeFunction(String)
    case intValue(Int)
    case floatValue(Double)
    case variableAssignment(name: String, isGlobal: Bool)
    case variableReference(name: String)
    case tagOpen
    case tagClose
    case voidValue
    case readCount(String)
}
