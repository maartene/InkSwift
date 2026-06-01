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
        while !state.isEnded {
            guard let top = containerStack.last else { break }

            // Container exhausted — pop and continue in parent
            if top.index >= top.container.children.count {
                popContainer()
                if containerStack.isEmpty { break }
                continue
            }

            // Peek at current child
            let currentChild = top.container.children[top.index]

            if case .container(let sub) = currentChild {
                // Enter anonymous sub-container inline
                containerStack[containerStack.count - 1].index += 1
                enterContainer(sub)
                continue
            }

            // Advance the index before dispatch
            containerStack[containerStack.count - 1].index += 1

            // Dispatch the node
            var walker = TreeWalker()
            walker.dispatchNode(currentChild, state: &state)

            // Handle divert: apply new path to container stack
            if case .divert(let target, _) = currentChild {
                applyDivert(target: target)
                continue
            }

            // Stop when choices are accumulated — user must choose
            if case .choicePoint = currentChild {
                // Continue collecting additional choices (multiple * in a row)
                continue
            }

            // Stop when story ends
            if state.isEnded { break }

            // Check for newline sentinel in output stream
            if let newlineIndex = state.outputStream.firstIndex(of: "\n") {
                let lineContent = state.outputStream[..<newlineIndex].joined()
                state.outputStream = Array(state.outputStream[(newlineIndex + 1)...])
                // Skip empty lines (paragraph separators with no visible text)
                if !lineContent.isEmpty {
                    return lineContent + "\n"
                }
                // Empty line: continue processing
                continue
            }

            // If choices were just collected (via stream of choice points), stop
            if !state.currentChoices.isEmpty { break }
        }

        // Flush any remaining buffered output
        if !state.outputStream.isEmpty {
            let remaining = state.outputStream.filter { $0 != "\n" }.joined()
            state.outputStream.removeAll()
            if !remaining.isEmpty {
                return remaining + "\n"
            }
        }
        return nil
    }

    /// Advance one line and store the result in lastCompletedLine.
    func step() {
        lastCompletedLine = stepToNextLine() ?? ""
    }

    // MARK: - Divert handling

    private func applyDivert(target: String) {
        let components = target.split(separator: ".").map(String.init)
        if let container = resolveNamedPath(components) {
            containerStack = [ContainerFrame(container: container, index: 0)]
        }
        // If unresolvable, leave stack as-is (will exhaust and stop)
    }

    private func resolveNamedPath(_ components: [String]) -> ContainerNode? {
        guard !components.isEmpty else { return nil }
        var container = root
        for component in components {
            if let named = container.namedContent[component] {
                container = named
            } else {
                return nil
            }
        }
        return container
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
            let components = choice.targetPath.split(separator: ".").map(String.init)
            if let container = resolveNamedPath(components) {
                containerStack = [ContainerFrame(container: container, index: 0)]
            }
        }
    }

    // MARK: - Save / restore

    func saveState() throws -> Data {
        return try JSONEncoder().encode(state)
    }

    func restoreState(_ data: Data) throws {
        do {
            state = try JSONDecoder().decode(StoryState.self, from: data)
        } catch {
            throw StoryError.invalidStateData
        }
    }
}
