import Foundation

final class InkEngine {
    var state: StoryState
    let root: ContainerNode
    private var lastCompletedLine: String = ""

    // Container execution stack. Each frame tracks a container and the current index.
    // Anonymous sub-containers are pushed as additional frames during execution.
    private var containerStack: [ContainerFrame] = []

    init(root: ContainerNode) {
        self.root = root
        self.state = StoryState()
        containerStack = [ContainerFrame(container: root, index: 0)]
    }

    // MARK: - Container frame management

    private struct ContainerFrame {
        var container: ContainerNode
        var index: Int
    }

    private func enterContainer(_ container: ContainerNode) {
        containerStack.append(ContainerFrame(container: container, index: 0))
    }

    private func popContainer() {
        containerStack.removeLast()
    }

    // MARK: - Computed properties

    var canContinue: Bool {
        guard !state.isEnded else { return false }
        // Story cannot continue if choices are pending (user must choose first)
        guard state.currentChoices.isEmpty else { return false }
        guard let top = containerStack.last else { return false }
        return top.index < top.container.children.count
    }

    var currentText: String {
        return lastCompletedLine
    }

    var currentChoices: [Choice] {
        return state.currentChoices.map { data in
            Choice(text: data.text, index: data.index, tags: [])
        }
    }

    var currentTags: [String] {
        return state.currentTags
    }

    var globalTags: [String] {
        return []
    }

    var currentErrors: [String] {
        return []
    }

    // MARK: - Step loop

    /// Advance the walker until a complete line of output is ready, then return it.
    /// Returns nil when there is no more output to produce.
    func stepToNextLine() -> String? {
        let walker = TreeWalker()
        while !state.isEnded {
            guard let top = containerStack.last else { break }

            if top.index >= top.container.children.count {
                popContainer()
                if containerStack.isEmpty { break }
                continue
            }

            let currentChild = top.container.children[top.index]

            if case .container(let sub) = currentChild {
                containerStack[containerStack.count - 1].index += 1
                enterContainer(sub)
                continue
            }

            containerStack[containerStack.count - 1].index += 1
            walker.dispatchNode(currentChild, state: &state)

            if case .divert(let target, _) = currentChild {
                applyDivert(target: target)
                continue
            }

            if case .choicePoint = currentChild { continue }

            if state.isEnded { break }

            if let line = consumeNextLine() { return line }

            if !state.currentChoices.isEmpty { break }
        }

        return flushRemainingOutput()
    }

    /// Extract one complete line from the output stream, or nil if no newline is present yet.
    private func consumeNextLine() -> String? {
        guard let newlineIndex = state.outputStream.firstIndex(of: "\n") else { return nil }
        let lineContent = state.outputStream[..<newlineIndex].joined()
        state.outputStream = Array(state.outputStream[(newlineIndex + 1)...])
        guard !lineContent.isEmpty else { return nil }
        return lineContent + "\n"
    }

    /// Flush any buffered output that remains after the step loop exits.
    private func flushRemainingOutput() -> String? {
        guard !state.outputStream.isEmpty else { return nil }
        let remaining = state.outputStream.filter { $0 != "\n" }.joined()
        state.outputStream.removeAll()
        return remaining.isEmpty ? nil : remaining + "\n"
    }

    /// Advance one line and store the result in lastCompletedLine.
    func step() {
        lastCompletedLine = stepToNextLine() ?? ""
    }

    // MARK: - Path resolution

    private func pathComponents(from dottedPath: String) -> [String] {
        dottedPath.split(separator: ".").map(String.init)
    }

    private func resolveNamedPath(_ components: [String]) -> ContainerNode? {
        guard !components.isEmpty else { return nil }
        var container = root
        for component in components {
            guard let named = container.namedContent[component] else { return nil }
            container = named
        }
        return container
    }

    // MARK: - Divert handling

    private func applyDivert(target: String) {
        let components = pathComponents(from: target)
        if let container = resolveNamedPath(components) {
            containerStack = [ContainerFrame(container: container, index: 0)]
        }
        // If unresolvable, leave stack as-is (will exhaust and stop)
    }

    // MARK: - Choice handling

    func chooseChoice(at index: Int) throws {
        guard index >= 0 && index < state.currentChoices.count else {
            throw StoryError.invalidChoiceIndex(index)
        }
        let choice = state.currentChoices[index]
        state.currentChoices = []
        state.currentTags = []
        if !choice.targetPath.isEmpty {
            let components = pathComponents(from: choice.targetPath)
            if let container = resolveNamedPath(components) {
                containerStack = [ContainerFrame(container: container, index: 0)]
                state.pointer.containerPath = components
                state.pointer.index = 0
            }
        }
    }

    // MARK: - Save / restore

    func saveState() throws -> Data {
        // Snapshot the full container execution stack so restore can rebuild it exactly.
        // Each frame records which child-index was followed from the parent (nil = root)
        // and the current execution position within that container.
        var snapshot = state
        snapshot.stackFrames = buildStackFrameSnapshot()
        // Keep pointer.index in sync for backwards compatibility with unit tests.
        snapshot.pointer.index = containerStack.last?.index ?? 0
        return try JSONEncoder().encode(snapshot)
    }

    /// Builds a serialisable representation of the current containerStack.
    /// Frame 0 is always the root (childIndex = nil). Subsequent frames record
    /// the index into the parent's children array that was used to enter them.
    /// Note: the parent incremented its index BEFORE entering, so the entry child is at parent.index - 1.
    private func buildStackFrameSnapshot() -> [ContainerStackFrame] {
        return containerStack.enumerated().map { depth, frame in
            let childIndex = depth == 0 ? nil : Optional(containerStack[depth - 1].index - 1)
            return ContainerStackFrame(childIndex: childIndex, executionIndex: frame.index)
        }
    }

    func restoreState(_ data: Data) throws {
        do {
            state = try JSONDecoder().decode(StoryState.self, from: data)
        } catch {
            throw StoryError.invalidStateData
        }
        rebuildContainerStack()
    }

    /// Rebuild containerStack from state.stackFrames after a state restore.
    /// Falls back to the legacy state.pointer approach when stackFrames is empty
    /// (for backwards compatibility with states saved before this field was added).
    private func rebuildContainerStack() {
        guard !state.stackFrames.isEmpty else {
            containerStack = [ContainerFrame(container: legacyRestoredContainer(), index: state.pointer.index)]
            return
        }
        containerStack = rebuildStackFromFrames()
    }

    /// Resolve the container for a legacy (pre-stackFrames) save file.
    private func legacyRestoredContainer() -> ContainerNode {
        guard !state.pointer.containerPath.isEmpty else { return root }
        return resolveNamedPath(state.pointer.containerPath) ?? root
    }

    /// Reconstruct a ContainerFrame stack from the serialised stack frames.
    private func rebuildStackFromFrames() -> [ContainerFrame] {
        var rebuilt: [ContainerFrame] = []
        for (depth, frame) in state.stackFrames.enumerated() {
            if depth == 0 {
                rebuilt.append(ContainerFrame(container: root, index: frame.executionIndex))
            } else if let childIdx = frame.childIndex {
                let parentContainer = rebuilt[depth - 1].container
                guard childIdx < parentContainer.children.count,
                      case .container(let child) = parentContainer.children[childIdx] else {
                    break  // Unresolvable child — truncate and stop
                }
                rebuilt.append(ContainerFrame(container: child, index: frame.executionIndex))
            }
        }
        return rebuilt.isEmpty ? [ContainerFrame(container: root, index: 0)] : rebuilt
    }
}
