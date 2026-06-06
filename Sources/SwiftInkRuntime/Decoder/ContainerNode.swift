struct ContainerNode {
    let children: [NodeKind]
    let namedContent: [String: ContainerNode]
    let flags: Int
    let name: String?
}
