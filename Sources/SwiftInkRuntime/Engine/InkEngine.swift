import Foundation

final class InkEngine {
    var state: StoryState
    let root: ContainerNode
    private var lastCompletedLine: String = ""

    // Container execution stack. Each frame tracks a container, its execution
    // index, and its absolute path from root. Anonymous sub-containers are
    // pushed as additional frames during execution.
    private var containerStack: [ContainerFrame] = []

    init(root: ContainerNode) {
        self.root = root
        self.state = StoryState()
        containerStack = [ContainerFrame(container: root, index: 0, pathFromRoot: [])]
    }

    // MARK: - Container frame management

    private struct ContainerFrame {
        var container: ContainerNode
        var index: Int
        // Absolute path from root. Each component is either a numeric child
        // index (string-encoded) or a name from the parent's namedContent.
        // Used for save/restore so any frame can be rebuilt by walking the path.
        var pathFromRoot: [String]
        // True for the top frame installed by chooseChoice. When such a frame
        // exhausts naturally, the engine stops rather than popping into the
        // parent — modelling a single-level callstack so the choice's
        // continuation doesn't fall through into the parent's remaining content.
        var isChoiceContinuationRoot: Bool = false
    }

    /// Push a child container that was reached by sequential descent from the
    /// current top frame. The caller has already incremented the parent's index
    /// past the child, so the entry index is `parent.index - 1`.
    private func enterContainer(_ container: ContainerNode) {
        let parentPath = containerStack.last?.pathFromRoot ?? []
        let entryIndex = (containerStack.last?.index ?? 0) - 1
        let path = parentPath + ["\(entryIndex)"]
        containerStack.append(ContainerFrame(container: container, index: 0, pathFromRoot: path))
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
                // A chosen-choice continuation acts as a callstack root: when it
                // exhausts, the engine stops rather than popping into the parent's
                // remaining content (which would re-generate the outer choices).
                if top.isChoiceContinuationRoot { break }
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

            if case .choicePoint(let target, let flags) = currentChild {
                // flg=8 (bit 3): invisible default / gather fallback — never shown to user.
                guard (flags & 8) == 0 else { continue }

                // flg=0x10 (bit 4): once-only choice — suppress if already chosen.
                // Use the resolved absolute path as the suppression key so that
                // identically-named relative paths in different containers do not
                // incorrectly collide.
                if (flags & 0x10) != 0 {
                    if let absolutePath = resolveAbsoluteTargetPath(for: target),
                       state.chosenChoiceTargets.contains(absolutePath) { continue }
                }

                // Choice text sources, in priority order:
                //   1. Non-empty string on evalStack: placed there by preceding str/[text]/str
                //      sequence (flg=20 bracket-only choices and correctly-executing flg=18/22).
                //   2. namedContent["s"] in current container: direct read shortcut for flg=18/22
                //      when the str/{->".^.s"}/str divert fails (relative path not yet resolved).
                //   3. Accumulated output stream: fallback for hand-crafted / legacy JSON.
                let choiceText: String
                if case .string(let s) = state.evalStack.last, !s.isEmpty {
                    state.evalStack.removeLast()
                    choiceText = s
                } else {
                    if case .string(_) = state.evalStack.last { state.evalStack.removeLast() }
                    if let sContainer = containerStack.last?.container.namedContent["s"] {
                        choiceText = sContainer.children
                            .compactMap { if case .text(let t) = $0 { return t } else { return nil } }
                            .joined()
                    } else {
                        choiceText = state.outputStream.filter { $0 != "\n" }.joined()
                    }
                }

                let index = state.currentChoices.count
                // Capture the continuation stack NOW while containerStack still
                // has the choice-collection context. This snapshot survives
                // save/restore and lets chooseChoice resume even on a fresh engine.
                let continuationFrames = buildContinuationFrames(forTarget: target)
                state.currentChoices.append(
                    ChoiceData(
                        text: choiceText,
                        targetPath: target,
                        continuationFrames: continuationFrames,
                        index: index,
                        flags: flags
                    )
                )
                state.outputStream.removeAll { $0 != "\n" }
                continue
            }

            walker.dispatchNode(currentChild, state: &state)

            if case .divert(let target, _, let isVariable) = currentChild {
                // Flush any buffered output as a line BEFORE the divert collapses
                // the stack — Ink commonly emits `text + divert` with the implicit
                // newline placed AFTER the divert. Without this flush, content
                // like the inner choice continuation's response text gets wiped
                // by the choice-collection clear in the divert target.
                let flushedLine = flushRemainingOutput()
                if isVariable, !state.returnStack.isEmpty {
                    applyDivert(target: state.returnStack.removeLast())
                } else if !isVariable {
                    applyDivert(target: target)
                }
                if let line = flushedLine { return line }
                continue
            }

            if state.isEnded { break }

            if let line = consumeNextLine() { return line }
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
        state.lastCompletedLine = lastCompletedLine
    }

    // MARK: - Path resolution

    private func pathComponents(from dottedPath: String) -> [String] {
        dottedPath.split(separator: ".").map(String.init)
    }

    private func resolveNamedPath(_ components: [String]) -> ContainerNode? {
        guard !components.isEmpty else { return nil }
        var container = root
        for component in components {
            if let index = Int(component) {
                // Numeric component: positional index into the container's ordered children array.
                guard index < container.children.count,
                      case .container(let child) = container.children[index]
                else { return nil }
                container = child
            } else {
                guard let named = container.namedContent[component] else { return nil }
                container = named
            }
        }
        return container
    }

    /// Parse a relative Ink path into (stackIndex, remainingComponents).
    /// Returns nil when the caret count would push the index out of bounds.
    ///
    /// Ink relative paths: `.^{N}.rest` where N carets each move one level up the
    /// execution stack.  N=1 → `containerStack[count-1]`, N=2 → `containerStack[count-2]`, etc.
    private func parseRelativePath(_ path: String) -> (stackIndex: Int, components: [String])? {
        var components = path.split(separator: ".").map(String.init)
        var caretCount = 0
        while components.first == "^" {
            caretCount += 1
            components.removeFirst()
        }
        let stackIndex = containerStack.count - caretCount
        guard stackIndex >= 0, stackIndex < containerStack.count else { return nil }
        return (stackIndex: stackIndex, components: components)
    }

    /// Navigate `components` down from `container`, following numeric indices into
    /// `.children` and named strings into `.namedContent`.
    private func navigate(_ components: [String], from container: ContainerNode) -> ContainerNode? {
        var current = container
        for component in components {
            if let index = Int(component) {
                guard index < current.children.count,
                      case .container(let child) = current.children[index]
                else { return nil }
                current = child
            } else {
                guard let named = current.namedContent[component] else { return nil }
                current = named
            }
        }
        return current
    }

    /// Walk an absolute `pathFromRoot` from the root container.
    /// Used by save/restore (rebuilding stack frames) and choice resolution.
    private func navigateAbsolute(_ path: [String]) -> ContainerNode? {
        var current = root
        for component in path {
            if let index = Int(component) {
                guard index < current.children.count,
                      case .container(let child) = current.children[index]
                else { return nil }
                current = child
            } else {
                guard let named = current.namedContent[component] else { return nil }
                current = named
            }
        }
        return current
    }

    /// Resolve a choice target to an absolute dotted-path string suitable for
    /// use as a suppression key in `state.chosenChoiceTargets`. Relative paths
    /// are resolved against the current containerStack; absolute paths are
    /// returned as-is. Returns nil when the path cannot be resolved.
    private func resolveAbsoluteTargetPath(for target: String) -> String? {
        if target.hasPrefix(".") {
            guard let (stackIndex, rest) = parseRelativePath(target),
                  navigate(rest, from: containerStack[stackIndex].container) != nil
            else { return nil }
            let absoluteComponents = containerStack[stackIndex].pathFromRoot + rest
            return absoluteComponents.joined(separator: ".")
        }
        let components = pathComponents(from: target)
        guard navigateAbsolute(components) != nil else { return nil }
        return target
    }

    /// Build a serialisable continuation-stack snapshot for a choice target.
    /// Captures the parent frames at choice-collection time plus a frame for the
    /// continuation container itself. The snapshot is stored inside `ChoiceData`
    /// so chooseChoice can resume even after a save/restore round-trip.
    private func buildContinuationFrames(forTarget target: String) -> [ContainerStackFrame] {
        if target.hasPrefix(".") {
            // Relative path: derive parent frames from the current containerStack
            // and append the continuation. The continuation's pathFromRoot is the
            // parent's pathFromRoot plus the final name component of the target.
            guard let (stackIndex, rest) = parseRelativePath(target),
                  navigate(rest, from: containerStack[stackIndex].container) != nil
            else { return [] }
            let parentSnapshots = containerStack[0...stackIndex].map {
                ContainerStackFrame(pathFromRoot: $0.pathFromRoot, executionIndex: $0.index)
            }
            let parentPath = containerStack[stackIndex].pathFromRoot
            let continuationPath = parentPath + rest
            return parentSnapshots + [ContainerStackFrame(pathFromRoot: continuationPath, executionIndex: 0)]
        }
        // Absolute path: continuation is a top-level lookup; no parent frames.
        let components = pathComponents(from: target)
        guard navigateAbsolute(components) != nil else { return [] }
        return [ContainerStackFrame(pathFromRoot: components, executionIndex: 0)]
    }

    /// Resolve a relative path during execution (used by applyDivert).
    private func resolveRelativePath(_ path: String) -> (container: ContainerNode, path: [String])? {
        guard let (stackIndex, rest) = parseRelativePath(path) else { return nil }
        guard let container = navigate(rest, from: containerStack[stackIndex].container) else { return nil }
        let resolvedPath = containerStack[stackIndex].pathFromRoot + rest
        return (container, resolvedPath)
    }

    // MARK: - Divert handling

    /// Resolve an anchor path whose last component starts with "$".
    /// Splits the path into prefix (resolved via resolveNamedPath) and anchor component,
    /// scans the resolved parent container's children for a sub-container whose .name
    /// equals the anchor component, and returns (parentContainer, anchorChildIndex + 1).
    private func resolveAnchor(inPath components: [String]) -> (ContainerNode, Int)? {
        guard let anchorComponent = components.last, anchorComponent.hasPrefix("$") else { return nil }
        let prefixComponents = Array(components.dropLast())
        guard let parentContainer = resolveNamedPath(prefixComponents) else { return nil }
        for (i, child) in parentContainer.children.enumerated() {
            if case .container(let sub) = child, sub.name == anchorComponent {
                return (parentContainer, i + 1)
            }
        }
        return nil
    }

    private func applyDivert(target: String) {
        // Relative path (starts with ".").
        // Only pure-ancestor gotos (all-caret paths like ".^.^") are resolved here;
        // paths with further navigation after the carets (e.g. ".^.s", ".^.^.12.s")
        // are call/return choice-text mechanisms — leave them as no-ops so the
        // namedContent["s"] fallback in choice collection continues to work.
        if target.hasPrefix(".") {
            let parts = target.split(separator: ".").map(String.init)
            let isPureAncestorGoto = !parts.isEmpty && parts.allSatisfy { $0 == "^" }
            if isPureAncestorGoto, let resolved = resolveRelativePath(target) {
                containerStack = [ContainerFrame(container: resolved.container, index: 0, pathFromRoot: resolved.path)]
                state.pointer.containerPath = resolved.path
            }
            // Non-pure-caret or unresolvable: leave stack as-is (silent no-op)
            return
        }
        let components = pathComponents(from: target)
        if components.last?.hasPrefix("$") == true {
            let prefixComponents = Array(components.dropLast())
            if let (parentContainer, startIndex) = resolveAnchor(inPath: components) {
                containerStack = [ContainerFrame(container: parentContainer, index: startIndex, pathFromRoot: prefixComponents)]
                state.pointer.containerPath = prefixComponents
            }
            // If unresolvable, leave stack as-is (silent no-op)
        } else if let container = navigateAbsolute(components) {
            containerStack = [ContainerFrame(container: container, index: 0, pathFromRoot: components)]
            state.pointer.containerPath = components
        }
        // If unresolvable, leave stack as-is (will exhaust and stop)
    }

    // MARK: - Choice handling

    func chooseChoice(at index: Int) throws {
        guard index >= 0 && index < state.currentChoices.count else {
            throw StoryError.invalidChoiceIndex(index)
        }
        let choice = state.currentChoices[index]
        if (choice.flags & 0x10) != 0 {
            // Record the absolute path of the chosen target so the suppression
            // check in stepToNextLine can match it reliably across contexts.
            // The continuation frames' last entry holds the resolved absolute path.
            if let absolutePath = choice.continuationFrames.last?.pathFromRoot.joined(separator: ".") {
                state.chosenChoiceTargets.insert(absolutePath)
            }
        }
        state.currentChoices = []
        state.currentTags = []
        state.isEnded = false

        // Install the continuation stack snapshot captured at choice-collection time.
        // Falls back to absolute-path lookup of targetPath for hand-crafted/legacy JSON
        // fixtures that may not have populated continuationFrames.
        let frames: [ContainerStackFrame]
        if !choice.continuationFrames.isEmpty {
            frames = choice.continuationFrames
        } else if navigateAbsolute(pathComponents(from: choice.targetPath)) != nil {
            frames = [ContainerStackFrame(pathFromRoot: pathComponents(from: choice.targetPath), executionIndex: 0)]
        } else {
            frames = []
        }
        var rebuilt = framesFromSnapshots(frames)
        if !rebuilt.isEmpty {
            // Mark the top frame as the callstack root for this choice. When the
            // continuation exhausts, the engine stops instead of popping into the
            // parent and re-generating the outer choices.
            rebuilt[rebuilt.count - 1].isChoiceContinuationRoot = true
            containerStack = rebuilt
            state.pointer.containerPath = rebuilt.last?.pathFromRoot ?? []
            state.pointer.index = 0
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

    /// Snapshot the current containerStack as serialisable frames. Each frame's
    /// pathFromRoot is preserved as-is so restoration can walk it from root.
    private func buildStackFrameSnapshot() -> [ContainerStackFrame] {
        return containerStack.map { frame in
            ContainerStackFrame(
                pathFromRoot: frame.pathFromRoot,
                executionIndex: frame.index,
                isChoiceContinuationRoot: frame.isChoiceContinuationRoot
            )
        }
    }

    func restoreState(_ data: Data) throws {
        do {
            state = try JSONDecoder().decode(StoryState.self, from: data)
        } catch {
            throw StoryError.invalidStateData
        }
        lastCompletedLine = state.lastCompletedLine
        rebuildContainerStack()
    }

    /// Rebuild containerStack from state.stackFrames after a state restore.
    /// Falls back to a single frame derived from state.pointer for restored
    /// states with no stackFrames (e.g. legacy fixtures or fresh defaults).
    private func rebuildContainerStack() {
        if state.stackFrames.isEmpty {
            let baseContainer = legacyRestoredContainer()
            containerStack = [ContainerFrame(
                container: baseContainer,
                index: state.pointer.index,
                pathFromRoot: state.pointer.containerPath
            )]
            return
        }
        containerStack = framesFromSnapshots(state.stackFrames)
    }

    /// Resolve a single container from `state.pointer.containerPath`, used as
    /// the legacy fallback when no stackFrames are present.
    private func legacyRestoredContainer() -> ContainerNode {
        guard !state.pointer.containerPath.isEmpty else { return root }
        return navigateAbsolute(state.pointer.containerPath) ?? root
    }

    /// Walk each stack-frame snapshot's pathFromRoot from root to rebuild the
    /// in-memory ContainerFrame stack. Frames that fail to resolve truncate
    /// the stack at that depth.
    private func framesFromSnapshots(_ snapshots: [ContainerStackFrame]) -> [ContainerFrame] {
        var rebuilt: [ContainerFrame] = []
        for snapshot in snapshots {
            guard let container = navigateAbsolute(snapshot.pathFromRoot) else { break }
            rebuilt.append(ContainerFrame(
                container: container,
                index: snapshot.executionIndex,
                pathFromRoot: snapshot.pathFromRoot,
                isChoiceContinuationRoot: snapshot.isChoiceContinuationRoot
            ))
        }
        return rebuilt.isEmpty ? [ContainerFrame(container: root, index: 0, pathFromRoot: [])] : rebuilt
    }
}
