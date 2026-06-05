import Foundation

final class InkEngine {

    /// Bit 0 of a container's `#f` flags: the container tracks visit counts.
    private static let containerFlagCountVisits: Int = 0x1

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
        // Resolved absolute path components for an invisible default target. Set
        // while the choice-collection container is still on the stack (so relative
        // path resolution succeeds), checked after the container exhausts.
        var pendingInvisibleDefaultPath: [String]? = nil
        while !state.isEnded {
            guard let top = containerStack.last else { break }

            if top.index >= top.container.children.count {
                if top.isChoiceContinuationRoot { break }
                // Implicit void return: function body exhausted with a pending function
                // return address (identified by "fnret:" prefix).
                // Push void sentinel so the caller's "out" command has something to consume.
                if let returnAddr = state.returnStack.last, returnAddr.hasPrefix("fnret:") {
                    state.returnStack.removeLast()
                    state.evalStack.append(.string("void"))
                    applyFunctionReturn(returnAddr: returnAddr)
                    continue
                }
                popContainer()
                if state.currentChoices.isEmpty, let autoPath = pendingInvisibleDefaultPath {
                    pendingInvisibleDefaultPath = nil
                    applyDivert(target: autoPath.joined(separator: "."))
                    continue
                }
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
                collectChoicePoint(target: target, flags: flags, pendingInvisibleDefaultPath: &pendingInvisibleDefaultPath)
                continue
            }

            // ~ret: pop function return address (fnret: prefix) and jump back to caller.
            if case .controlCommand("~ret") = currentChild {
                if let returnAddr = state.returnStack.last, returnAddr.hasPrefix("fnret:") {
                    state.returnStack.removeLast()
                    applyFunctionReturn(returnAddr: returnAddr)
                }
                continue
            }

            walker.dispatchNode(currentChild, state: &state)

            if case .divert(let target, let isConditional, let isVariable) = currentChild {
                // f():-prefixed targets are function calls: push return address first.
                if target.hasPrefix("f():") {
                    let actualTarget = String(target.dropFirst(4))
                    let returnAddr = buildFunctionReturnAddress()
                    state.returnStack.append(returnAddr)
                    applyDivert(target: actualTarget)
                    continue
                }
                let (shouldReturn, line) = handleDivertNode(target: target, isConditional: isConditional, isVariable: isVariable)
                if shouldReturn { return line }
                continue
            }

            if state.isEnded { break }

            if let line = consumeNextLine() { return line }
        }

        return flushRemainingOutput()
    }

    /// Process a `.choicePoint` node encountered during step execution.
    /// Updates `state.currentChoices` if the choice passes all filters,
    /// or captures the invisible-default path for later auto-divert.
    private func collectChoicePoint(
        target: String,
        flags: ChoiceFlags,
        pendingInvisibleDefaultPath: inout [String]?
    ) {
        // isInvisibleDefault: gather fallback — never shown to user.
        guard !flags.contains(.isInvisibleDefault) else { return }

        // Invisible default predicate: none of the visible-choice bits are set.
        // inklecate v0.9 compiles `+ [] -> target` as flg:0, so isInvisibleDefault
        // alone is insufficient. Resolve the path NOW while the current container
        // is still on the stack, then store for auto-divert after exhaustion.
        if flags.intersection(.visibleChoiceMask).isEmpty {
            if pendingInvisibleDefaultPath == nil {
                pendingInvisibleDefaultPath = resolveInvisibleDefaultPath(target)
            }
            return
        }

        // hasCondition: a preceding ev.../ev block has left a boolean on the
        // evalStack. Pop it unconditionally to keep the stack balanced;
        // skip this choice if the result is false.
        if flags.contains(.hasCondition) {
            let conditionResult = state.evalStack.popLast() ?? .bool(false)
            guard conditionResult.asBool else { return }
        }

        // isOnceOnly: suppress if already chosen.
        // Use the resolved absolute path as the suppression key so that
        // identically-named relative paths in different containers do not
        // incorrectly collide.
        if flags.contains(.isOnceOnly) {
            if let absolutePath = resolveAbsoluteTargetPath(for: target),
               state.chosenChoiceTargets.contains(absolutePath) { return }
        }

        let choiceText = resolveChoiceText()
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
    }

    /// Resolve the display text for a choice point from (in priority order):
    ///   1. A non-empty string on the evalStack (placed by str/[text]/str sequence).
    ///   2. The namedContent["s"] sub-container of the current container.
    ///   3. The accumulated output stream (legacy JSON fallback).
    private func resolveChoiceText() -> String {
        if case .string(let s) = state.evalStack.last, !s.isEmpty {
            state.evalStack.removeLast()
            return s
        }
        if case .string(_) = state.evalStack.last { state.evalStack.removeLast() }
        if let sContainer = containerStack.last?.container.namedContent["s"] {
            return sContainer.children
                .compactMap { if case .text(let t) = $0 { return t } else { return nil } }
                .joined()
        }
        return state.outputStream.filter { $0 != "\n" }.joined()
    }

    /// Process a `.divert` node encountered during step execution.
    /// Returns `(shouldReturn: true, line)` when the caller should immediately
    /// return `line` from the step loop; returns `(false, nil)` to continue.
    private func handleDivertNode(
        target: String,
        isConditional: Bool,
        isVariable: Bool
    ) -> (shouldReturn: Bool, line: String?) {
        // Flush buffered output BEFORE the divert collapses the stack — Ink
        // commonly emits `text + divert` with the newline after the divert.
        let flushedLine = flushRemainingOutput()

        if isConditional {
            // Conditional diverts pop a bool from the eval stack; false = skip divert.
            let condition = state.evalStack.popLast() ?? .bool(false)
            guard condition.asBool else {
                return (shouldReturn: flushedLine != nil, line: flushedLine)
            }
            if let line = flushedLine { return (shouldReturn: true, line: line) }
            applyConditionalBranch(target: target)
            return (shouldReturn: false, line: nil)
        }

        if isVariable, !state.returnStack.isEmpty {
            applyDivert(target: state.returnStack.removeLast())
        } else if !isVariable {
            applyDivert(target: target)
        }
        if let line = flushedLine { return (shouldReturn: true, line: line) }
        return (shouldReturn: false, line: nil)
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

    // MARK: - Function call / return

    /// Build a return-address string for the current execution position.
    /// Format: "fnret:path|index" where path is the joined containerStack pathFromRoot
    /// and index is the current execution index (already past the call node).
    /// The "fnret:" prefix distinguishes function return addresses from
    /// choice-text push-divert-target entries in the returnStack.
    private func buildFunctionReturnAddress() -> String {
        guard let top = containerStack.last else { return "fnret:|0" }
        let pathStr = top.pathFromRoot.joined(separator: ".")
        return "fnret:\(pathStr)|\(top.index)"
    }

    /// Restore execution to the position encoded in a function return address.
    /// Expected format: "fnret:path|index" where path is the dot-joined
    /// containerStack pathFromRoot and index is the execution index after the call.
    private func applyFunctionReturn(returnAddr: String) {
        // Strip the "fnret:" prefix
        let addr = returnAddr.hasPrefix("fnret:") ? String(returnAddr.dropFirst(6)) : returnAddr
        guard let pipeIdx = addr.lastIndex(of: "|") else {
            applyDivert(target: addr)
            return
        }
        let pathStr = String(addr[addr.startIndex..<pipeIdx])
        let idxStr  = String(addr[addr.index(after: pipeIdx)...])
        let targetIndex = Int(idxStr) ?? 0

        if pathStr.isEmpty {
            // Root container return: rebuild from root at targetIndex
            containerStack = [ContainerFrame(container: root, index: targetIndex, pathFromRoot: [])]
            state.pointer.containerPath = []
        } else {
            let components = pathStr.split(separator: ".").map(String.init)
            if let container = navigateAbsolute(components) {
                containerStack = [ContainerFrame(container: container, index: targetIndex, pathFromRoot: components)]
                state.pointer.containerPath = components
            } else if let startIndex = Int(components.last ?? ""),
                      let parentContainer = navigateAbsolute(Array(components.dropLast())) {
                rebuildStackForParentPath(Array(components.dropLast()), container: parentContainer, startIndex: startIndex)
                containerStack[containerStack.count - 1].index = targetIndex
            }
        }
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

    /// Resolve a choice target path (relative or absolute) to its absolute path
    /// components, validating that the target container actually exists.
    /// Returns nil when the path cannot be resolved or the target does not exist.
    private func resolveToAbsoluteComponents(for target: String) -> [String]? {
        if target.hasPrefix(".") {
            guard let (stackIndex, rest) = parseRelativePath(target),
                  navigate(rest, from: containerStack[stackIndex].container) != nil
            else { return nil }
            return containerStack[stackIndex].pathFromRoot + rest
        }
        let components = pathComponents(from: target)
        guard navigateAbsolute(components) != nil else { return nil }
        return components
    }

    /// Resolve an invisible-default choice target to its absolute path components
    /// while the choice-collection container is still on the stack. Returns nil
    /// when the path cannot be resolved.
    private func resolveInvisibleDefaultPath(_ target: String) -> [String]? {
        return resolveToAbsoluteComponents(for: target)
    }

    /// Resolve a choice target to an absolute dotted-path string suitable for
    /// use as a suppression key in `state.chosenChoiceTargets`. Relative paths
    /// are resolved against the current containerStack; absolute paths are
    /// returned as-is. Returns nil when the path cannot be resolved.
    private func resolveAbsoluteTargetPath(for target: String) -> String? {
        return resolveToAbsoluteComponents(for: target)?.joined(separator: ".")
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

    /// Resolve a conditional branch target (from a `{"->":"...","c":true}` divert).
    /// Unlike `applyDivert`, this method resolves relative paths with named navigation
    /// (e.g. `.^.b`) because conditional branches always jump to their target.
    /// Absolute paths delegate to `applyDivert`.
    private func applyConditionalBranch(target: String) {
        if target.hasPrefix(".") {
            guard let (stackIndex, rest) = parseRelativePath(target) else { return }
            if rest.isEmpty {
                // Pure ancestor goto
                let resolved = containerStack[stackIndex]
                containerStack = [ContainerFrame(container: resolved.container, index: 0, pathFromRoot: resolved.pathFromRoot)]
                state.pointer.containerPath = resolved.pathFromRoot
            } else {
                // Navigate into named content from the anchor frame (e.g. ".^.b")
                guard let destination = navigate(rest, from: containerStack[stackIndex].container) else { return }
                let resolvedPath = containerStack[stackIndex].pathFromRoot + rest
                containerStack = [ContainerFrame(container: destination, index: 0, pathFromRoot: resolvedPath)]
                state.pointer.containerPath = resolvedPath
            }
            return
        }
        // Absolute target: delegate to standard divert resolution
        applyDivert(target: target)
    }

    private func applyDivert(target: String) {
        // Relative path (starts with ".").
        // Pure-ancestor gotos (all-caret paths like ".^.^") jump to an ancestor frame.
        //
        // Named-relative paths (e.g. ".^.b") come in two flavours:
        //  1. Branch jumps: `{"->":".^.b"}` in a conditional-false branch — the `b`
        //     namedContent is the branch body. No return address is on the returnStack.
        //  2. Call/return text mechanisms: `{"->":".^.s"}` and `{"->":".^.^.N.s"}` —
        //     a push-divert-target (`{"^->":"..."}`) always precedes these, so the
        //     returnStack is non-empty. The `s` container uses the return address to
        //     jump back after emitting choice text.
        //
        // Discriminator: only follow a named-relative path when returnStack is EMPTY
        // (branch-jump case). When returnStack is non-empty it is a call/return
        // mechanism — remain a no-op so the existing call/return machinery works.
        if target.hasPrefix(".") {
            guard let (stackIndex, rest) = parseRelativePath(target) else { return }
            if rest.isEmpty {
                // Pure ancestor goto
                let resolved = containerStack[stackIndex]
                containerStack = [ContainerFrame(container: resolved.container, index: 0, pathFromRoot: resolved.pathFromRoot)]
                state.pointer.containerPath = resolved.pathFromRoot
            } else if state.returnStack.isEmpty,
                      let destination = navigate(rest, from: containerStack[stackIndex].container) {
                // Named-relative branch jump (no pending return address): navigate into namedContent
                let resolvedPath = containerStack[stackIndex].pathFromRoot + rest
                containerStack = [ContainerFrame(container: destination, index: 0, pathFromRoot: resolvedPath)]
                state.pointer.containerPath = resolvedPath
            }
            // Call/return relative path (returnStack non-empty) or unresolvable: leave stack as-is
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
            if container.flags & Self.containerFlagCountVisits != 0 {
                let pathKey = components.joined(separator: ".")
                state.visitCounts[pathKey, default: 0] += 1
            }
        } else if let startIndex = Int(components.last ?? ""),
                  let parentContainer = navigateAbsolute(Array(components.dropLast())) {
            // Path whose last component is a numeric index into the parent container
            // (e.g. "café.0.6" = execute A starting from index 6). The parent container
            // is resolved by dropping the index and the full parent stack is rebuilt.
            let parentPath = Array(components.dropLast())
            rebuildStackForParentPath(parentPath, container: parentContainer, startIndex: startIndex)
        }
        // If unresolvable, leave stack as-is (will exhaust and stop)
    }

    /// Rebuild the container stack to reflect a jump to `startIndex` within `container`,
    /// reconstructing all ancestor frames from the absolute `parentPath`.
    private func rebuildStackForParentPath(_ parentPath: [String], container: ContainerNode, startIndex: Int) {
        var frames: [ContainerFrame] = []
        // Walk from root to parent, building frames for each ancestor container.
        var current = root
        var currentPath: [String] = []
        for component in parentPath {
            currentPath.append(component)
            if let index = Int(component) {
                guard index < current.children.count,
                      case .container(let child) = current.children[index] else { break }
                // Parent frame: index is advanced past this child (it was entered)
                frames.append(ContainerFrame(container: current, index: index + 1, pathFromRoot: Array(currentPath.dropLast())))
                current = child
            } else {
                guard let named = current.namedContent[component] else { break }
                frames.append(ContainerFrame(container: current, index: current.children.count, pathFromRoot: Array(currentPath.dropLast())))
                current = named
            }
        }
        // Final frame: the target container at the specified startIndex
        frames.append(ContainerFrame(container: container, index: startIndex, pathFromRoot: parentPath))
        containerStack = frames
        state.pointer.containerPath = parentPath
    }

    // MARK: - Choice handling

    /// Returns true when the choice continuation's first absolute divert targets an
    /// ancestor of the continuation itself (a "loop-back" pattern like `* [Leave] -> café`
    /// inside the `café` knot). Loop-back choices are never tracked in `chosenChoiceTargets`
    /// because they are intended to remain available on every visit.
    private func continuationLoopsBackToAncestor(_ choice: ChoiceData) -> Bool {
        guard let lastFrame = choice.continuationFrames.last,
              let continuationContainer = navigateAbsolute(lastFrame.pathFromRoot) else { return false }
        let continuationPath = lastFrame.pathFromRoot
        for node in continuationContainer.children {
            guard case .divert(let target, _, _) = node else { continue }
            guard !target.hasPrefix(".") else { continue }
            let targetComponents = target.split(separator: ".").map(String.init)
            // A loop-back: targetComponents is a proper prefix of continuationPath
            // (meaning the divert goes to a containing ancestor of this continuation).
            if targetComponents.count < continuationPath.count,
               continuationPath.starts(with: targetComponents) {
                return true
            }
        }
        return false
    }

    func chooseChoice(at index: Int) throws {
        guard index >= 0 && index < state.currentChoices.count else {
            throw StoryError.invalidChoiceIndex(index)
        }
        let choice = state.currentChoices[index]
        if choice.flags.contains(.isOnceOnly) {
            // Record the absolute path of the chosen target so the suppression
            // check in stepToNextLine can match it reliably across contexts.
            // Exception: do NOT track loop-back choices — continuations that divert
            // directly back to an ancestor knot (e.g. `* [Leave] -> café` inside café).
            // Such choices are intended to be available on every visit.
            if let absolutePath = choice.continuationFrames.last?.pathFromRoot.joined(separator: "."),
               !continuationLoopsBackToAncestor(choice) {
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
