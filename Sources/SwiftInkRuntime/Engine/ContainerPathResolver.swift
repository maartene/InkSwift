/// Stateless navigation over the immutable story tree (D5). Every query reads the
/// root plus, for relative paths, a passed-in current path; nothing here touches
/// the engine's container stack, which `InkEngine` alone mutates.
struct ContainerPathResolver {

    let root: ContainerNode

    /// One ancestor on the way down an absolute path: the container, its own
    /// path, and the index its frame resumes at once the next child is entered.
    struct Ancestor {
        let container: ContainerNode
        let path: ContainerPath
        let resumeIndex: Int
    }

    // MARK: - Absolute navigation

    /// Walk an absolute path from the root. Nil when any component names no container.
    func node(at path: ContainerPath) -> ContainerNode? {
        navigate(path.components, from: root)
    }

    /// One step down the static container tree: the child `component` names, and
    /// the index its parent's frame resumes at once that child has been entered —
    /// just past it for a numeric child, the end of the parent for a named one.
    func descend(
        from container: ContainerNode,
        through component: PathComponent
    ) -> (child: ContainerNode, resumeIndex: Int)? {
        switch component {
        case .index(let index):
            // Positional index into the container's ordered children array.
            guard index < container.children.count,
                  case .container(let child) = container.children[index]
            else { return nil }
            return (child, index + 1)
        case .name(let name):
            guard let named = container.namedContent[name] else { return nil }
            return (named, container.children.count)
        }
    }

    /// The ancestors met walking `path` from the root, each with the index its
    /// frame resumes at (see `descend`). Stops at the first unresolvable component;
    /// the container `path` itself is not included.
    func ancestors(along path: ContainerPath) -> [Ancestor] {
        var chain: [Ancestor] = []
        var current = root
        var currentPath: [PathComponent] = []
        for component in path.components {
            guard let (child, resumeIndex) = descend(from: current, through: component) else { break }
            chain.append(Ancestor(container: current, path: ContainerPath(components: currentPath), resumeIndex: resumeIndex))
            currentPath.append(component)
            current = child
        }
        return chain
    }

    // MARK: - Relative resolution

    /// The anchor a relative path's carets reach from `current`. Nil when the
    /// carets would climb above the root.
    ///
    /// Ink relative paths use filesystem-style "../"-equivalent semantics:
    /// `.^{N}.rest` where the first caret moves from the divert Object to its
    /// containing container (no path-component change), and each subsequent
    /// caret walks one level up the **static container tree**. This is the
    /// canonical C# runtime semantic (ink Path.cs: ".^.^.hello.5 is equivalent
    /// to ../../hello/5"; Object.cs:106-123: each caret returns Container.parent).
    ///
    /// Carets count **compiled path-component depth**, NOT execution-stack
    /// frame depth. Stack frames may compress multiple path components into
    /// one frame (when a divert lands via multi-component descent), so the
    /// anchor is `current` minus `parentSteps - 1` trailing components.
    func anchorPath(parentSteps: Int, from current: ContainerPath) -> ContainerPath? {
        // Zero carets is also tolerated (treated as "anchor is the current
        // container") for symmetry with the C# model when the runtime is already
        // at a container Object.
        let dropCount = max(0, parentSteps - 1)
        guard dropCount <= current.components.count else { return nil }
        return ContainerPath(components: Array(current.components.dropLast(dropCount)))
    }

    /// Navigate `tail` down from the container at `anchorPath`, returning both the
    /// destination container and the ACTUAL resolved path (which may include an
    /// extra "0" segment if the anchor's named content is stored in an anonymous
    /// sequential child — the inklecate "knot namespace flattening" convention).
    func destination(
        of tail: [PathComponent],
        from anchorPath: ContainerPath
    ) -> (container: ContainerNode, path: ContainerPath)? {
        guard let anchor = node(at: anchorPath) else { return nil }
        // First try direct navigation (works when namedContent is in the anchor itself)
        if let destination = navigate(tail, from: anchor) {
            return (destination, ContainerPath(components: anchorPath.components + tail))
        }
        // Fallthrough: in inklecate, knot stitches are stored in an anonymous container
        // at index 0 of the knot. Try navigating from anchor.children[0].
        if !anchor.children.isEmpty,
           case .container(let firstChild) = anchor.children[0],
           let destination = navigate(tail, from: firstChild) {
            return (destination, ContainerPath(components: anchorPath.components + [.index(0)] + tail))
        }
        return nil
    }

    /// Resolve a path reference (relative or absolute) to the absolute path of an
    /// existing container. A relative reference with nothing after its carets is
    /// the anchor itself; otherwise the destination's ACTUAL path (see
    /// `destination(of:from:)`). Nil when the target does not exist.
    func absolutePath(of reference: PathReference, from current: ContainerPath) -> ContainerPath? {
        switch reference {
        case .absolute(let path):
            return node(at: path) == nil ? nil : path
        case .relative(let parentSteps, let tail):
            guard let anchorPath = anchorPath(parentSteps: parentSteps, from: current) else { return nil }
            if tail.isEmpty {
                return anchorPath
            }
            return destination(of: tail, from: anchorPath)?.path
        }
    }

    /// Resolve a CNT? key to the absolute path its visit count is stored under.
    /// Absolute keys are returned as-is. Relative keys use the same caret rule as
    /// diverts, falling back to plain concatenation when the destination does not
    /// resolve. Nil when the carets climb above the root.
    func readCountKey(for reference: PathReference, from current: ContainerPath) -> ContainerPath? {
        switch reference {
        case .absolute(let path):
            return path
        case .relative(let parentSteps, let tail):
            guard let anchorPath = anchorPath(parentSteps: parentSteps, from: current) else { return nil }
            return absolutePath(of: reference, from: current)
                ?? ContainerPath(components: anchorPath.components + tail)
        }
    }

    // MARK: - $-anchors

    /// Resolve a path whose last component is a `$` anchor name. Resolves the
    /// prefix from the root (an empty prefix resolves to nothing), scans that
    /// parent container's children for a sub-container whose `.name` equals the
    /// anchor component, and returns the parent with the index just past it.
    func anchorTarget(of path: ContainerPath) -> (container: ContainerNode, resumeIndex: Int)? {
        guard let anchorComponent = path.components.last, anchorComponent.isAnchor else { return nil }
        let prefix = ContainerPath(components: Array(path.components.dropLast()))
        guard prefix.components.isEmpty == false,
              let parentContainer = node(at: prefix) else { return nil }
        for (i, child) in parentContainer.children.enumerated() {
            if case .container(let sub) = child, sub.name == anchorComponent.description {
                return (parentContainer, i + 1)
            }
        }
        return nil
    }

    // MARK: - Private

    /// Navigate `components` down from `container`, following indices into
    /// `.children` and names into `.namedContent`.
    private func navigate(_ components: [PathComponent], from container: ContainerNode) -> ContainerNode? {
        var current = container
        for component in components {
            guard let (child, _) = descend(from: current, through: component) else { return nil }
            current = child
        }
        return current
    }
}

extension PathComponent {
    /// A `$`-prefixed name: an anchor marker inside its parent's children, such as
    /// the `$r1` that a choice's return-address divert target points at.
    var isAnchor: Bool {
        guard case .name(let name) = self else { return false }
        return name.hasPrefix("$")
    }
}
