import Foundation

final class InkEngine {
    var state: StoryState
    let root: ContainerNode
    private var lastCompletedLine: String = ""

    init(root: ContainerNode) {
        self.root = root
        self.state = StoryState()
    }

    // MARK: - Container resolution

    private func currentContainer() -> ContainerNode? {
        var container = root
        for name in state.pointer.containerPath {
            guard let named = container.namedContent[name] else { return nil }
            container = named
        }
        return container
    }

    // MARK: - Computed properties

    var canContinue: Bool {
        guard !state.isEnded else { return false }
        guard let container = currentContainer() else { return false }
        return state.pointer.index < container.children.count
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
        while canContinue {
            guard let container = currentContainer() else { break }
            _ = walker.step(in: container, state: &state)
            if let newlineIndex = state.outputStream.firstIndex(of: "\n") {
                let line = state.outputStream[..<newlineIndex].joined()
                state.outputStream = Array(state.outputStream[(newlineIndex + 1)...])
                return line
            }
        }
        // Flush any remaining buffered output
        if !state.outputStream.isEmpty {
            let remaining = state.outputStream.filter { $0 != "\n" }.joined()
            state.outputStream.removeAll()
            if !remaining.isEmpty {
                return remaining
            }
        }
        return nil
    }

    /// Advance one line and store the result in lastCompletedLine.
    func step() {
        if let line = stepToNextLine() {
            lastCompletedLine = line
        }
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
            state.pointer.containerPath = components
            state.pointer.index = 0
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
