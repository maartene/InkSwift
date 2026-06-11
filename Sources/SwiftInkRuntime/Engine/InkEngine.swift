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
        initializeGlobalVariables()
    }

    /// Execute the `global decl` named container (if present) to initialize global variables.
    /// Ink stories store variable declarations as executable sequences: ev / value / /ev / VAR=
    /// in a special named container that runs before the story starts.
    private func initializeGlobalVariables() {
        guard let globalDecl = root.namedContent["global decl"] else { return }
        let walker = TreeWalker()
        // Run the global decl container sequentially, collecting variable assignments.
        var idx = 0
        while idx < globalDecl.children.count {
            let child = globalDecl.children[idx]
            idx += 1
            // Dispatch the node to process control commands, values, and assignments.
            // We re-use the same state so VAR= nodes write directly into variablesState.
            walker.dispatchNode(child, state: &state)
        }
        // Reset the eval stack after global initialization — the decl block may leave
        // interim values pushed by ev/value//ev sequences that were consumed by VAR=.
        state.evalStack.removeAll()
        // Reset output stream — global decl may append text from string-mode operations.
        state.outputStream.removeAll()
        // Reset end-of-story flags that the decl's trailing "end"/"done" control command
        // set via TreeWalker.handleControlCommand. Without this reset, a freshly-constructed
        // engine appears terminated to the facade — canContinue short-circuits to false and
        // chooseChoice raises invalidChoiceIndex. Real inklecate-compiled stories always end
        // `global decl` with `"end"` so this reset restores the contract that a fresh engine
        // is ready to run the main story body.
        state.isEnded = false
        state.pointer.index = 0
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
        // Track visit counts for containers that have the Visits flag (#f bit 0).
        // This mirrors C# VisitContainer(container, atStart:true) for sequential entry.
        if container.flags & Self.containerFlagCountVisits != 0 {
            let pathKey = path.joined(separator: ".")
            state.visitCounts[pathKey, default: 0] += 1
        }
    }

    private func popContainer() {
        containerStack.removeLast()
    }

    // MARK: - Computed properties

    var canContinue: Bool {
        // Choices pending — user must choose, can't continue.
        guard state.currentChoices.isEmpty else { return false }
        // Buffered complete lines (text + \n) are still drainable via continue()
        // even after the story has ended. The step loop defers some flushes
        // (e.g. inside eval blocks) and may accumulate more than one line before
        // hitting `end` / `done`; allow the caller to consume them one at a time
        // through subsequent continue() calls.
        if state.outputStream.contains("\n") { return true }
        guard !state.isEnded else { return false }
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
        // After a divert fires, the destination may start with glue (<>) that removes
        // a trailing \n from the output stream. Suppress consumeNextLine for the rest
        // of the current evaluation block (ev…/ev) following a divert so the glue has
        // a chance to fire before we return the buffered line.
        var suppressConsumeAfterDivert = false
        // Track depth inside ev/.../ev blocks. While > 0, defer line flushing: the
        // eval block may contain a function-call divert whose return + a downstream
        // divert can land on a destination that starts with `<>` glue (removing the
        // pending newline). Flushing inside the eval block would yield a line that
        // should have been glued away.
        // Matches the canonical C# runtime semantic where Continue() steps until
        // outputStreamEndsInNewline is stable (see ink-engine-runtime/Story.cs:462).
        var evalBlockDepth = 0
        while !state.isEnded {
            guard let top = containerStack.last else { break }

            if top.index >= top.container.children.count {
                if top.isChoiceContinuationRoot {
                    // Before stopping, check for a pending invisible default that should fire
                    // now that all visible choices have been exhausted. This allows the
                    // auto-continuation pattern (`+ [] -> target`) to work inside a choice
                    // continuation (e.g., after "Ask about the shop." is exhausted).
                    if state.currentChoices.isEmpty, let autoPath = pendingInvisibleDefaultPath {
                        popContainer()
                        pendingInvisibleDefaultPath = nil
                        applyDivert(target: autoPath.joined(separator: "."))
                        continue
                    }
                    break
                }
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

            // ->t->: tunnel entry — push return address and jump to tunnel target.
            // The return address encodes the current container path and the next
            // execution index (already incremented past the ->t-> node).
            if case .tunnelDivert(let target) = currentChild {
                let returnAddr = buildTunnelReturnAddress()
                state.returnStack.append(returnAddr)
                applyDivert(target: target)
                suppressConsumeAfterDivert = state.outputStream.last == "\n"
                continue
            }

            // ->->: tunnel return — pop return address and resume at that position.
            if case .controlCommand("->->") = currentChild {
                if let returnAddr = state.returnStack.popLast() {
                    applyDivert(target: returnAddr)
                }
                suppressConsumeAfterDivert = state.outputStream.last == "\n"
                continue
            }

            // Keep state.pointer.containerPath in sync with the actual current frame so
            // the `visit` control command reads the correct container's visit count.
            state.pointer.containerPath = containerStack.last?.pathFromRoot ?? []

            // Intercept readCount before dispatching to TreeWalker so we can resolve
            // relative CNT? paths using the actual containerStack frame paths.
            if case .readCount(let key) = currentChild {
                let resolvedKey = resolveReadCountKey(key)
                state.evalStack.append(.int(state.visitCounts[resolvedKey] ?? 0))
                continue
            }

            walker.dispatchNode(currentChild, state: &state)

            if case .divert(let target, let isConditional, let isVariable) = currentChild {
                if target.hasPrefix("f():") {
                    applyFunctionCall(target: String(target.dropFirst(4)))
                    suppressConsumeAfterDivert = state.outputStream.last == "\n"
                    continue
                }
                let (shouldReturn, line) = handleDivertNode(target: target, isConditional: isConditional, isVariable: isVariable)
                if shouldReturn { return line }
                suppressConsumeAfterDivert = state.outputStream.last == "\n"
                continue
            }

            if state.isEnded { break }

            // Track ev/.../ev depth so we can defer flushes inside eval blocks.
            // The block may contain a function-call divert whose return is followed
            // by a divert to a glued destination, and a flush at the block boundary
            // would emit a line that should have been glued.
            if case .controlCommand(let cmd) = currentChild {
                if cmd == "ev" { evalBlockDepth += 1 }
                if cmd == "/ev" { evalBlockDepth = max(0, evalBlockDepth - 1) }
            }

            // Clear the post-divert suppression when we encounter a glue (<>) node,
            // since glue either removes the pending \n or confirms it won't be removed.
            if case .controlCommand(let cmd) = currentChild, cmd == "<>" {
                suppressConsumeAfterDivert = false
            }
            // Also clear when we encounter a text node — at that point any earlier \n
            // is part of a completed line that's safe to return on the next iteration.
            if case .text = currentChild {
                suppressConsumeAfterDivert = false
            }

            // Only check for a completed line after nodes that don't add newlines,
            // aren't suppressed by a recent divert, and aren't inside an eval block.
            // After a .newline node we defer the check so that a subsequent glue
            // (<>) has a chance to remove the newline before we return. The line
            // will be flushed on a later iteration (after the next text/glue node).
            // Defer flush across a multi-choice cluster: once a choicePoint
            // has been collected (`currentChoices` non-empty), continue stepping
            // through the rest of the cluster's choicePoints + their eval blocks
            // in the same stepToNextLine call. Otherwise a buffered line
            // (e.g. a gather text emitted just before the cluster) flushes at
            // the first /ev boundary AFTER c-0, returning early and leaving
            // c-1, c-2, ... unvisited. This matches the canonical C# runtime:
            // `state.canContinue` depends on pointer position, NOT on
            // currentChoices, so its Continue() loop keeps stepping past
            // choicePoints until the container exhausts. Any pending line
            // here will be returned by `flushRemainingOutput` when the loop
            // exits (with a single line at a time per the consumeNextLine
            // semantic).
            // After /ev, peek at the next node: if it is a VAR= assignment, defer
            // the flush so that the assignment executes before the buffered line is
            // returned. This matches the C# runtime where Continue() keeps stepping
            // past /ev when the immediately-following node is a pure side-effect
            // (writes to variablesState, no output). A VAR= node after /ev is
            // semantically part of the same Ink statement as the preceding eval block.
            let nextIsAssignment: Bool = {
                guard case .controlCommand("/ev") = currentChild,
                      evalBlockDepth == 0,
                      let nextTop = containerStack.last,
                      nextTop.index < nextTop.container.children.count,
                      case .variableAssignment = nextTop.container.children[nextTop.index]
                else { return false }
                return true
            }()
            if case .newline = currentChild { }
            else if suppressConsumeAfterDivert { }
            else if evalBlockDepth > 0 { }
            else if nextIsAssignment { }
            else if !state.currentChoices.isEmpty { }
            else {
                if let line = consumeNextLine() { return line }
            }
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
        // Any pending str/text/str string on the evalStack must be popped to
        // keep the stack balanced, since we skip resolveChoiceText() for these.
        guard !flags.contains(.isInvisibleDefault) else {
            discardPendingChoiceTextFromEvalStack()
            return
        }

        // Invisible default predicate: none of the visible-choice bits are set.
        // inklecate v0.9 compiles `+ [] -> target` as flg:0, so isInvisibleDefault
        // alone is insufficient. Resolve the path NOW while the current container
        // is still on the stack, then store for auto-divert after exhaustion.
        if flags.intersection(.visibleChoiceMask).isEmpty {
            if pendingInvisibleDefaultPath == nil {
                pendingInvisibleDefaultPath = resolveInvisibleDefaultPath(target)
            }
            discardPendingChoiceTextFromEvalStack()
            return
        }

        // hasCondition: a preceding ev.../ev block has left a boolean on the
        // evalStack. Pop it unconditionally to keep the stack balanced;
        // skip this choice if the result is false.
        if flags.contains(.hasCondition) {
            let conditionResult = state.evalStack.popLast() ?? .bool(false)
            guard conditionResult.asBool else {
                // Also pop any pending choice text string to keep the stack balanced.
                discardPendingChoiceTextFromEvalStack()
                return
            }
        }

        // isOnceOnly: suppress if already chosen.
        // Use the resolved absolute path as the suppression key so that
        // identically-named relative paths in different containers do not
        // incorrectly collide.
        if flags.contains(.isOnceOnly) {
            if let absolutePath = resolveAbsoluteTargetPath(for: target),
               state.chosenChoiceTargets.contains(absolutePath) {
                // Pop any pending choice text string to keep the stack balanced.
                discardPendingChoiceTextFromEvalStack()
                return
            }
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
    }

    /// Discard a pending choice-text string from the evalStack without consuming it.
    /// Called when a choice is skipped (condition false, once-only suppressed, or
    /// invisible-default) so that the str/text/str-accumulated string does not linger
    /// on the evalStack and corrupt later conditional evaluations.
    private func discardPendingChoiceTextFromEvalStack() {
        if case .string(_) = state.evalStack.last {
            state.evalStack.removeLast()
        }
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
        // Do NOT flush the output stream before the divert. The divert destination
        // may begin with a glue (<>) node that removes a pending \n from the stream —
        // flushing here would return the line before the glue has a chance to join it
        // with the continuation text (e.g. "Awkward, I reply" + glue + ", sipping...").

        if isConditional {
            // Conditional diverts pop a bool from the eval stack; false = skip divert.
            let condition = state.evalStack.popLast() ?? .bool(false)
            guard condition.asBool else {
                return (shouldReturn: false, line: nil)
            }
            applyConditionalBranch(target: target)
            return (shouldReturn: false, line: nil)
        }

        if isVariable {
            // Variable divert: look up the target variable in variablesState.
            // The variable holds a divert-target path stored as a string value
            // (placed there by the {^->: "path"} + {temp=: "$varName"} mechanism).
            if let varValue = state.variablesState[target],
               case .string(let path) = varValue {
                applyDivert(target: path)
            }
        } else {
            applyDivert(target: target)
        }
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
    ///
    /// If the buffer still contains a complete line (text followed by `\n`),
    /// return JUST that line — anything beyond stays in `outputStream` for the
    /// next `continue()` call. This preserves line boundaries when the loop
    /// has accumulated more than one complete line before exiting (e.g. when
    /// the step loop deferred flushes inside an eval block and then ended at
    /// a choicePoint or story end).
    ///
    /// If the buffer has no `\n`, return the remaining text as the final line.
    private func flushRemainingOutput() -> String? {
        guard !state.outputStream.isEmpty else { return nil }
        if let line = consumeNextLine() { return line }
        // No newline left — return remaining text as the trailing line.
        let remaining = state.outputStream.joined()
        state.outputStream.removeAll()
        return remaining.isEmpty ? nil : remaining + "\n"
    }

    // MARK: - Function call / return

    /// Build a return-address string for tunnel entry.
    /// Format: "path.N" where path is the dot-joined containerStack pathFromRoot
    /// and N is the current execution index (already incremented past the ->t-> node).
    /// This format is resolved by applyDivert via the numeric-last-component path.
    private func buildTunnelReturnAddress() -> String {
        guard let top = containerStack.last else { return "0" }
        let pathStr = top.pathFromRoot.joined(separator: ".")
        if pathStr.isEmpty {
            return "\(top.index)"
        }
        return "\(pathStr).\(top.index)"
    }

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

    /// Push a function return address for the current execution position and
    /// divert to the function body. Called when a divert node's target is
    /// `f():`-prefixed (an Ink function call rather than a plain goto).
    private func applyFunctionCall(target: String) {
        state.returnStack.append(buildFunctionReturnAddress())
        // Push a new empty per-frame temp-variable scope so `temp= x` declarations
        // inside the function body don't leak into `variablesState` (or get
        // confused with the caller's locals with the same name).
        state.callFrameVariables.append([:])
        applyDivert(target: target)
    }

    /// Restore execution to the position encoded in a function return address.
    /// Expected format: "fnret:path|index" where path is the dot-joined
    /// containerStack pathFromRoot and index is the execution index after the call.
    private func applyFunctionReturn(returnAddr: String) {
        // Pop the function's per-frame temp-variable scope. Local `temp= x`
        // declarations made inside the function body are discarded here.
        if !state.callFrameVariables.isEmpty {
            state.callFrameVariables.removeLast()
        }
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
            // Always rebuild the full ancestor stack so relative diverts in the caller
            // body (e.g. ".^.^.^.g-3") can find their anchor container at the correct
            // depth. A single-frame stack would make those caret counts fail.
            if let container = navigateAbsolute(components) {
                rebuildFullStack(to: components, container: container, targetIndex: targetIndex)
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

    /// Parse a relative Ink path into (anchorPath, remainingComponents).
    /// Returns nil when the caret count would push the anchor above the root.
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
    /// anchor is computed from the top frame's `pathFromRoot.dropLast(caretCount - 1)`
    /// — never from `containerStack.count`.
    private func parseRelativePath(_ path: String) -> (anchorPath: [String], components: [String])? {
        var components = path.split(separator: ".").map(String.init)
        var caretCount = 0
        while components.first == "^" {
            caretCount += 1
            components.removeFirst()
        }
        let topPath = containerStack.last?.pathFromRoot ?? []
        // First caret steps Object → container (no path drop); each subsequent
        // caret drops one path component. Zero carets is also tolerated (treated
        // as "anchor is the current container") for symmetry with the C# model
        // when the runtime is already at a container Object.
        let dropCount = max(0, caretCount - 1)
        guard dropCount <= topPath.count else { return nil }
        let anchorPath = Array(topPath.dropLast(dropCount))
        return (anchorPath: anchorPath, components: components)
    }

    /// Replace `containerStack` with a frame at `destPath` (starting at
    /// `startIndex` within `destContainer`), preserving existing frames whose
    /// `pathFromRoot` is a **strict** prefix of `destPath`. Any discarded frame's
    /// `isChoiceContinuationRoot` marker propagates to the new top frame so
    /// the engine still stops at the choice continuation boundary when its
    /// new execution context exhausts.
    ///
    /// "Strict" prefix means: a frame at exactly `destPath` is treated as
    /// discarded so we install a fresh restart-frame (index 0 or `startIndex`)
    /// rather than resume from the prior frame's index.
    private func installDestinationFrame(
        destPath: [String],
        destContainer: ContainerNode,
        startIndex: Int = 0
    ) {
        var ancestors: [ContainerFrame] = []
        var discardedRoot = false
        for frame in containerStack {
            if frame.pathFromRoot.count < destPath.count &&
               destPath.starts(with: frame.pathFromRoot) {
                ancestors.append(frame)
            } else if frame.isChoiceContinuationRoot {
                discardedRoot = true
            }
        }
        containerStack = ancestors + [
            ContainerFrame(
                container: destContainer,
                index: startIndex,
                pathFromRoot: destPath,
                isChoiceContinuationRoot: discardedRoot
            )
        ]
        state.pointer.containerPath = destPath
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

    /// Attempt to navigate `components` from `anchorContainer`, returning both the
    /// destination container and the ACTUAL resolved path components (which may include
    /// an extra "0" segment if the anchor's named content is stored in an anonymous
    /// sequential child — the inklecate "knot namespace flattening" convention).
    private func navigateWithActualPath(
        _ components: [String],
        from anchorContainer: ContainerNode,
        anchorPath: [String]
    ) -> (container: ContainerNode, path: [String])? {
        // First try direct navigation (works when namedContent is in the anchor itself)
        if let destination = navigate(components, from: anchorContainer) {
            return (destination, anchorPath + components)
        }
        // Fallthrough: in inklecate, knot stitches are stored in an anonymous container
        // at index 0 of the knot. Try navigating from anchorContainer.children[0].
        if !anchorContainer.children.isEmpty,
           case .container(let firstChild) = anchorContainer.children[0],
           let destination = navigate(components, from: firstChild) {
            return (destination, anchorPath + ["0"] + components)
        }
        return nil
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
            guard let (anchorPath, rest) = parseRelativePath(target) else { return nil }
            if rest.isEmpty { return anchorPath }
            guard let anchor = navigateAbsolute(anchorPath),
                  let (_, resolvedPath) = navigateWithActualPath(
                      rest, from: anchor, anchorPath: anchorPath
                  )
            else { return nil }
            return resolvedPath
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
            // and append the continuation. The continuation's pathFromRoot uses the
            // ACTUAL resolved path (which may include a "0" segment for knot stitches).
            // Parent snapshots are the current frames whose pathFromRoot is a STRICT
            // prefix of the continuation path — same rule as installDestinationFrame.
            guard let (anchorPath, rest) = parseRelativePath(target) else { return [] }
            let continuationPath: [String]
            if rest.isEmpty {
                continuationPath = anchorPath
            } else {
                guard let anchor = navigateAbsolute(anchorPath),
                      let (_, resolved) = navigateWithActualPath(rest, from: anchor, anchorPath: anchorPath)
                else { return [] }
                continuationPath = resolved
            }
            let parentSnapshots = containerStack.compactMap { frame -> ContainerStackFrame? in
                guard frame.pathFromRoot.count < continuationPath.count,
                      continuationPath.starts(with: frame.pathFromRoot) else { return nil }
                return ContainerStackFrame(pathFromRoot: frame.pathFromRoot, executionIndex: frame.index)
            }
            return parentSnapshots + [ContainerStackFrame(pathFromRoot: continuationPath, executionIndex: 0)]
        }
        // Absolute path: continuation is a top-level lookup; no parent frames.
        let components = pathComponents(from: target)
        guard navigateAbsolute(components) != nil else { return [] }
        return [ContainerStackFrame(pathFromRoot: components, executionIndex: 0)]
    }

    /// Resolve a CNT? path key to an absolute dot-joined string suitable for visitCounts lookup.
    /// Absolute keys (no leading ".") are returned as-is.
    /// Relative keys use the same caret semantic as parseRelativePath — carets
    /// count compiled path-component depth, not stack-frame depth.
    private func resolveReadCountKey(_ key: String) -> String {
        guard key.hasPrefix(".") else { return key }
        guard let (anchorPath, components) = parseRelativePath(key) else { return key }
        if components.isEmpty {
            return anchorPath.joined(separator: ".")
        }
        guard let anchor = navigateAbsolute(anchorPath) else {
            return (anchorPath + components).joined(separator: ".")
        }
        if let (_, resolvedPath) = navigateWithActualPath(
            components, from: anchor, anchorPath: anchorPath
        ) {
            return resolvedPath.joined(separator: ".")
        }
        // Fallback: plain concatenation
        return (anchorPath + components).joined(separator: ".")
    }

    /// Resolve a relative path during execution (used by applyDivert).
    private func resolveRelativePath(_ path: String) -> (container: ContainerNode, path: [String])? {
        guard let (anchorPath, rest) = parseRelativePath(path),
              let anchor = navigateAbsolute(anchorPath) else { return nil }
        if rest.isEmpty {
            return (anchor, anchorPath)
        }
        guard let destination = navigate(rest, from: anchor) else { return nil }
        return (destination, anchorPath + rest)
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
            guard let (anchorPath, rest) = parseRelativePath(target),
                  let anchor = navigateAbsolute(anchorPath) else { return }
            if rest.isEmpty {
                installDestinationFrame(destPath: anchorPath, destContainer: anchor)
                return
            }
            if let (destination, resolvedPath) = navigateWithActualPath(
                rest,
                from: anchor,
                anchorPath: anchorPath
            ) {
                installDestinationFrame(destPath: resolvedPath, destContainer: destination)
                return
            }
            // Numeric-index relative divert (e.g. ".^.^.^.7"):
            // The last rest component is an execution-start index into the anchor,
            // not a container name. Restart the anchor at that index.
            if rest.count == 1, let startIndex = Int(rest[0]) {
                installDestinationFrame(destPath: anchorPath, destContainer: anchor, startIndex: startIndex)
            }
            return
        }
        // Absolute target: delegate to standard divert resolution
        applyDivert(target: target)
    }

    private func applyDivert(target: String) {
        // Relative path (starts with ".").
        // Resolution follows the canonical C# runtime semantic: carets count
        // compiled path-component depth, not execution-stack frame depth. See
        // parseRelativePath for the full reference. `installDestinationFrame`
        // preserves frames whose pathFromRoot is a strict prefix of the
        // destination and propagates any discarded choice-continuation-root
        // marker to the new top frame.
        if target.hasPrefix(".") {
            guard let (anchorPath, rest) = parseRelativePath(target),
                  let anchor = navigateAbsolute(anchorPath) else { return }
            if rest.isEmpty {
                // Pure ancestor goto: restart the anchor at index 0.
                installDestinationFrame(destPath: anchorPath, destContainer: anchor)
                return
            }
            if let (destination, resolvedPath) = navigateWithActualPath(
                rest,
                from: anchor,
                anchorPath: anchorPath
            ) {
                installDestinationFrame(destPath: resolvedPath, destContainer: destination)
                return
            }
            // Numeric execution-position divert: last component is a child index,
            // not a container name. Jump to that execution position in the anchor.
            if rest.count == 1, let startIndex = Int(rest[0]) {
                installDestinationFrame(destPath: anchorPath, destContainer: anchor, startIndex: startIndex)
            }
            // Unresolvable: leave stack as-is
            return
        }
        let components = pathComponents(from: target)
        if components.last?.hasPrefix("$") == true {
            // Anchor divert: jump to the position just after the named anchor marker,
            // rebuilding the full ancestor stack so relative diverts remain resolvable.
            let prefixComponents = Array(components.dropLast())
            if let (parentContainer, startIndex) = resolveAnchor(inPath: components) {
                rebuildStackForParentPath(prefixComponents, container: parentContainer, startIndex: startIndex)
                state.pointer.containerPath = prefixComponents
            }
            // If unresolvable, leave stack as-is (silent no-op)
        } else if let container = navigateAbsolute(components) {
            let pathKey = components.joined(separator: ".")
            containerStack = [ContainerFrame(container: container, index: 0, pathFromRoot: components)]
            state.pointer.containerPath = components
            if container.flags & Self.containerFlagCountVisits != 0 {
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

    /// Rebuild the full container stack for a return to a known container, preserving
    /// all ancestor frames so that relative diverts inside the target body resolve correctly.
    /// `fullPath` is the absolute path of the target container; `container` is its node.
    private func rebuildFullStack(to fullPath: [String], container: ContainerNode, targetIndex: Int) {
        rebuildStackForParentPath(Array(fullPath.dropLast()), container: container, startIndex: targetIndex)
        // rebuildStackForParentPath ends with a frame that has pathFromRoot: parentPath.
        // Overwrite the final frame's pathFromRoot with the full path so callers see
        // the correct container path (e.g. "start.waited.0.g-2.c-7", not "start.waited.0.g-2").
        if !containerStack.isEmpty {
            containerStack[containerStack.count - 1].pathFromRoot = fullPath
            state.pointer.containerPath = fullPath
        }
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
            // Track visit counts for the choice body container if it has the countVisits flag.
            // This mirrors what applyDivert does for absolute-path targets and enterContainer
            // does for sequentially-entered containers. Choice bodies entered via chooseChoice
            // do not go through either path, so we track them explicitly here.
            let topFrame = rebuilt[rebuilt.count - 1]
            if topFrame.container.flags & Self.containerFlagCountVisits != 0 {
                let pathKey = topFrame.pathFromRoot.joined(separator: ".")
                state.visitCounts[pathKey, default: 0] += 1
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

    // MARK: - Variable access

    /// Write a Swift native value to a global variable by name.
    /// No-op when the key does not already exist (design decision OQ-1).
    /// Bool is checked before Int to prevent coercion to .int via integer literal conformance.
    func setVariable(_ name: String, to value: some Any) {
        guard state.variablesState[name] != nil else { return }
        if let b = value as? Bool {
            state.variablesState[name] = .bool(b)
        } else if let n = value as? Int {
            state.variablesState[name] = .int(n)
        } else if let d = value as? Double {
            state.variablesState[name] = .float(d)
        } else if let f = value as? Float {
            state.variablesState[name] = .float(Double(f))
        } else if let s = value as? String {
            state.variablesState[name] = .string(s)
        }
        // Unknown type: pure no-op
    }

    /// Read a global variable by name and bridge its InkValue to a Swift native type.
    /// Returns Int, Double, String, or Bool. Returns nil for absent keys and .variablePointer.
    func getVariable(_ name: String) -> Any? {
        guard let value = state.variablesState[name] else { return nil }
        switch value {
        case .int(let n):    return n
        case .float(let f):  return f
        case .string(let s): return s
        case .bool(let b):   return b
        case .variablePointer: return nil
        }
    }

    // MARK: - Visit count access

    /// Return the visit count for a knot by name. Returns 0 for unknown knots.
    func visitCount(forKnot name: String) -> Int {
        state.visitCounts[name] ?? 0
    }

    /// Set the visit count for a knot by name.
    /// Pure no-op when the knot does not exist in the story structure.
    func setVisitCount(forKnot name: String, to count: Int) {
        guard root.namedContent[name] != nil else { return }
        state.visitCounts[name] = count
    }

    func moveToKnot(_ knot: String, stitch: String? = nil) throws {
        // D3: resolve ALL paths before ANY state mutation
        guard let knotContainer = root.namedContent[knot] else {
            throw StoryError.knotNotFound(knot)
        }
        let targetPath: String
        if let stitch = stitch {
            guard knotContainer.namedContent[stitch] != nil else {
                throw StoryError.knotNotFound("\(knot).\(stitch)")
            }
            targetPath = "\(knot).\(stitch)"
        } else {
            targetPath = knot
        }
        // D1: reset 12 StoryState fields (RD-01); stackFrames intentionally NOT cleared
        state.returnStack = []
        state.evalStack = []
        state.currentChoices = []
        state.outputStream = []
        state.callFrameVariables = []
        state.suppressNextNewline = false
        state.isEnded = false
        state.inTagMode = false
        state.tagAccumulator = ""
        state.inStringMode = false
        state.stringAccumulator = ""
        // D4: delegate stack installation to applyDivert
        applyDivert(target: targetPath)
    }
}
