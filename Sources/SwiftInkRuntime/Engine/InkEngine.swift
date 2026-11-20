import Foundation

final class InkEngine {

    var state: StoryState
    let root: ContainerNode
    private let resolver: ContainerPathResolver
    private let visitCounter: VisitCounter
    private var lastCompletedLine: String = ""

    // Container execution stack. Each frame tracks a container, its execution
    // index, and its absolute path from root. Anonymous sub-containers are
    // pushed as additional frames during execution.
    private var containerStack: [ContainerFrame] = []

    /// `containerStack.count` at the moment each in-flight function call installed
    /// its body frame — one entry per pending call, popped by `applyFunctionReturn`.
    /// Used to tell the function's own body container (whose exhaustion IS the
    /// implicit void return) from a nested sub-container inside it (whose
    /// exhaustion must merely pop one level). Not persisted: a function call never
    /// spans a `continue()` boundary, because its output is produced inside an
    /// `ev`/`/ev` block whose flush is deferred, so no save can land mid-call.
    private var functionRootDepths: [Int] = []

    /// Runtime errors of the current flow (ADR-017). In memory only, never part
    /// of `StoryState`, so never saved: a story cannot recover from one, and
    /// `restoreState` / `moveToKnot` clear them (they start somewhere else).
    private var errors: [String] = []

    /// How the flow stopped in the current `continue()` (ADR-020 §4), or nil
    /// while it has not stopped. Transient: reset by the `step()` prologue,
    /// never part of `StoryState`, so never saved.
    ///
    /// A ran-out stop deliberately does NOT set `isEnded` (a deviation from
    /// ADR-020 §4): an ordinary stop at a choice point is a ran-out stop, so
    /// setting it would persist `isEnded = true` in every save taken at a choice.
    /// `isEnded` stays the flag for done / end / a forced end only.
    enum FlowStop: Equatable {
        /// `done`, `end` or a forced end (C# `didSafeExit`).
        case safeExit
        /// The container stack exhausted with no invisible default to fire.
        case ranOut
    }

    private(set) var stopReason: FlowStop?

    /// C# `didSafeExit`: the flow stopped through `done`, `end` or a forced end.
    var didSafeExit: Bool {
        stopReason == .safeExit
    }

    init(root: ContainerNode) {
        self.root = root
        self.resolver = ContainerPathResolver(root: root)
        self.visitCounter = VisitCounter(resolver: resolver)
        self.state = StoryState()
        containerStack = [ContainerFrame(container: root, index: 0, pathFromRoot: .root)]
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
            do {
                try walker.dispatchNode(child, state: &state)
            } catch {
                return reportRuntimeError(error)
            }
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
        // index or a name from the parent's namedContent.
        // Used for save/restore so any frame can be rebuilt by walking the path.
        var pathFromRoot: ContainerPath
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
        let parentPath = containerStack.last?.pathFromRoot ?? .root
        let entryIndex = (containerStack.last?.index ?? 0) - 1
        let path = parentPath.appending(.index(entryIndex))
        containerStack.append(ContainerFrame(container: container, index: 0, pathFromRoot: path))
        // This mirrors C# VisitContainer(container, atStart:true) for sequential entry.
        recordVisit(to: container, at: path)
    }

    /// Count a visit to `container` when it has the CountVisits flag (#f bit 0).
    /// Called where execution enters one container at its start: sequential
    /// descent, a variable divert's target, and a chosen choice's continuation.
    private func recordVisit(to container: ContainerNode, at path: ContainerPath) {
        visitCounter.recordVisit(to: container, at: path, in: &state)
    }

    /// Count every container a divert entered, from inside `previous` to the
    /// top frame's position (C# `VisitChangedContainersDueToDivert`).
    private func recordDivertEntries(from previous: ContainerPath?) {
        guard let top = containerStack.last else { return }
        visitCounter.recordDivert(from: previous, landingAt: top.index, in: top.pathFromRoot, state: &state)
    }

    /// A chosen choice's body: its frame is on top, entered at its start.
    private func recordVisitToTopFrame() {
        guard let top = containerStack.last else { return }
        recordVisit(to: top.container, at: top.pathFromRoot)
    }

    private func popContainer() {
        containerStack.removeLast()
    }

    // MARK: - Computed properties

    var canContinue: Bool {
        // Buffered complete lines (text + \n) are still drainable via continue()
        // even after the story has ended or reached its choices. The step loop
        // defers some flushes (e.g. inside eval blocks, or past a choice point)
        // and may accumulate more than one line before stopping; allow the
        // caller to consume them one at a time through subsequent continue()
        // calls.
        if hasBufferedLine { return true }
        // Choices pending — user must choose, can't continue.
        guard state.currentChoices.isEmpty else { return false }
        guard !state.isEnded else { return false }
        guard let top = containerStack.last else { return false }
        return top.index < top.container.children.count
    }

    var currentText: String {
        return lastCompletedLine
    }

    /// A complete line is still waiting in the output stream.
    private var hasBufferedLine: Bool {
        state.outputStream.contains(.newline)
    }

    /// The choices on offer: none while a buffered line is still to be returned.
    /// C# rewinds a Continue that ran past a newline into more text, choice
    /// points included, so a choice is offered only with the last line before
    /// it; collected early, it stays hidden until that line is returned.
    private var offeredChoices: [ChoiceData] {
        hasBufferedLine ? [] : state.currentChoices
    }

    var currentChoices: [Choice] {
        return offeredChoices.map { data in
            Choice(text: data.text, index: data.index, tags: data.tags)
        }
    }

    var currentTags: [String] {
        return state.currentTags
    }

    var globalTags: [String] {
        return []
    }

    var currentErrors: [String] {
        return errors
    }

    // MARK: - Step loop

    /// Loop-local bookkeeping of one `stepToNextLine` call.
    private struct StepContext {
        /// Resolved absolute path of an invisible default target. Set
        /// while the choice-collection container is still on the stack (so relative
        /// path resolution succeeds), checked after the container exhausts.
        var pendingInvisibleDefaultPath: ContainerPath?
        /// After a divert fires, the destination may start with glue (<>) that removes
        /// a trailing \n from the output stream. Suppress consumeNextLine for the rest
        /// of the current evaluation block (ev…/ev) following a divert so the glue has
        /// a chance to fire before we return the buffered line.
        var suppressConsumeAfterDivert = false
        /// Depth inside ev/.../ev blocks. While > 0, defer line flushing: the
        /// eval block may contain a function-call divert whose return + a downstream
        /// divert can land on a destination that starts with `<>` glue (removing the
        /// pending newline). Flushing inside the eval block would yield a line that
        /// should have been glued away.
        /// Matches the canonical C# runtime semantic where Continue() steps until
        /// outputStreamEndsInNewline is stable (see ink-engine-runtime/Story.cs:462).
        var evalBlockDepth = 0

        mutating func noteDivert(outputEndsInNewline: Bool) {
            suppressConsumeAfterDivert = outputEndsInNewline
        }

        /// Update the flush bookkeeping for a node that was just dispatched.
        mutating func track(_ node: NodeKind) {
            switch node {
            case .controlCommand("ev"):
                evalBlockDepth += 1
            case .controlCommand("/ev"):
                evalBlockDepth = max(0, evalBlockDepth - 1)
            // Glue either removes the pending \n or confirms it won't be removed;
            // a text node means any earlier \n ends a completed line that's safe
            // to return on the next iteration. Either way the post-divert
            // suppression is over.
            case .controlCommand("<>"), .text:
                suppressConsumeAfterDivert = false
            default:
                break
            }
        }
    }

    /// What the step loop does after one step.
    private enum StepOutcome {
        /// Keep stepping.
        case proceed
        /// Leave the loop and flush whatever output remains.
        case stop
        /// Return this value from `stepToNextLine` immediately.
        case returnLine(String?)
    }

    /// Advance the walker until a complete line of output is ready, then return it.
    /// Returns nil when there is no more output to produce.
    func stepToNextLine() -> String? {
        let walker = TreeWalker()
        var context = StepContext()
        stepping: while !state.isEnded {
            guard let top = containerStack.last else { break }
            let outcome = top.index >= top.container.children.count
                ? stepOutOfExhaustedContainer(top, context: &context)
                : executeNextChild(of: top, walker: walker, context: &context)
            switch outcome {
            case .proceed:
                continue
            case .stop:
                break stepping
            case .returnLine(let line):
                return line
            }
        }
        return flushRemainingOutput()
    }

    /// The top frame has no children left: fire a pending invisible default,
    /// return from a function body, or pop back into the parent.
    private func stepOutOfExhaustedContainer(_ top: ContainerFrame, context: inout StepContext) -> StepOutcome {
        if top.isChoiceContinuationRoot {
            // Before stopping, check for a pending invisible default that should fire
            // now that all visible choices have been exhausted. This allows the
            // auto-continuation pattern (`+ [] -> target`) to work inside a choice
            // continuation (e.g., after "Ask about the shop." is exhausted).
            return firePendingInvisibleDefault(context: &context, poppingFrame: true) ? .proceed : ranOut()
        }
        if returnFromExhaustedFunctionBody() {
            return .proceed
        }
        popContainer()
        if firePendingInvisibleDefault(context: &context, poppingFrame: false) {
            return .proceed
        }
        return containerStack.isEmpty ? ranOut() : .proceed
    }

    /// The container stack exhausted with no invisible default to fire: the
    /// root frame popped empty, or a choice-continuation root ran out (the C#
    /// named-container null-pointer case). Not a safe exit (ADR-020 §4).
    private func ranOut() -> StepOutcome {
        stopReason = .ranOut
        return .stop
    }

    /// Divert to the pending invisible default once no visible choice remains.
    /// Returns whether it fired.
    private func firePendingInvisibleDefault(context: inout StepContext, poppingFrame: Bool) -> Bool {
        guard state.currentChoices.isEmpty, let autoPath = context.pendingInvisibleDefaultPath else {
            return false
        }
        if poppingFrame {
            popContainer()
        }
        context.pendingInvisibleDefaultPath = nil
        applyAbsoluteDivert(autoPath)
        recordVisitToTopFrame()
        return true
    }

    /// Implicit void return: the function's OWN BODY container exhausted
    /// with a function element on top of the return stack.
    /// Push void (C# `Runtime.Void`, Story.cs ~2685-2691) so the caller's `out`,
    /// `pop` or assignment has a result to consume.
    ///
    /// The depth test matters: a nested sub-container inside the body must
    /// pop one level, NOT end the function. An inline conditional lowers to
    /// two sibling sub-containers (a conditional divert into the true
    /// branch, then an unconditional divert into the else branch), so
    /// without this test a FALSE condition exhausted the first sub-container
    /// and was mistaken for the body finishing — returning to the caller and
    /// skipping the else branch plus everything after it.
    ///
    /// `functionRootDepths` records `containerStack.count` immediately after
    /// the call's divert installed the body frame; deeper frames are nested.
    /// With no depth recorded (a state restored mid-function, which the step
    /// loop does not otherwise produce) the guard falls back to the previous
    /// always-return behaviour rather than stranding the call.
    private func returnFromExhaustedFunctionBody() -> Bool {
        guard containerStack.count <= (functionRootDepths.last ?? Int.max),
              let element = state.returnStack.pop(.function) else {
            return false
        }
        state.evalStack.append(.void)
        applyFunctionReturn(to: element)
        return true
    }

    /// Execute the top frame's next child and decide whether a line is ready.
    private func executeNextChild(
        of top: ContainerFrame,
        walker: TreeWalker,
        context: inout StepContext
    ) -> StepOutcome {
        let currentChild = top.container.children[top.index]
        containerStack[containerStack.count - 1].index += 1

        if case .container(let sub) = currentChild {
            enterContainer(sub)
            return .proceed
        }
        if executeFlowNode(currentChild, context: &context) {
            return .proceed
        }

        // Keep state.pointer.containerPath in sync with the actual current frame so
        // the `visit` control command reads the correct container's visit count.
        state.pointer.containerPath = currentPath

        if executeVisitCountNode(currentChild) {
            return .proceed
        }

        do {
            try walker.dispatchNode(currentChild, state: &state)
        } catch {
            reportRuntimeError(error)
            return .stop
        }

        switch currentChild {
        case .divert(let target, let isConditional):
            followPlainDivert(target: target, isConditional: isConditional)
        case .functionCall(let target):
            applyFunctionCall(target: target)
        default:
            return settleLine(after: currentChild, context: &context)
        }
        context.noteDivert(outputEndsInNewline: state.outputStream.last == .newline)
        return .proceed
    }

    /// After an ordinary node has been dispatched: stop if it ended the story,
    /// otherwise update the flush bookkeeping and return a completed line if
    /// one may be returned now.
    private func settleLine(after node: NodeKind, context: inout StepContext) -> StepOutcome {
        if state.isEnded {
            return .stop
        }
        context.track(node)
        if mayFlushLine(after: node, context: context), let line = consumeNextLine() {
            return .returnLine(line)
        }
        return .proceed
    }

    /// Choice points, flow ends, function returns and tunnels: nodes the engine
    /// handles itself rather than dispatching to the TreeWalker. Returns whether
    /// the node was one of them.
    private func executeFlowNode(_ node: NodeKind, context: inout StepContext) -> Bool {
        switch node {
        // end: C# `ForceEnd` — the pending choices go too (#28).
        case .controlCommand("end"):
            forceEnd()
        // done: stop here, keeping the choices already generated (Story.cs ~1544-1566).
        case .controlCommand("done"):
            endFlow()
        case .choicePoint(let target, let flags):
            collectChoicePoint(
                target: target, flags: flags, pendingInvisibleDefaultPath: &context.pendingInvisibleDefaultPath)
        case .controlCommand("~ret"):
            returnFromFunction()
        // ->t->: tunnel entry — push a tunnel element for the current position
        // (index already incremented past the ->t-> node) and jump to the target.
        case .tunnelDivert(let target):
            state.returnStack.append(returnElement(.tunnel))
            followDivert(to: target)
            context.noteDivert(outputEndsInNewline: state.outputStream.last == .newline)
        case .controlCommand("->->"):
            returnFromTunnel()
            context.noteDivert(outputEndsInNewline: state.outputStream.last == .newline)
        default:
            return false
        }
        return true
    }

    /// ~ret: pop the function element and jump back to the caller. Any other
    /// element on top, or none, refuses the pop and ends the flow.
    private func returnFromFunction() {
        guard let element = state.returnStack.pop(.function) else {
            return refusePop(.function)
        }
        applyFunctionReturn(to: element)
    }

    /// ->->: pop the tunnel element and resume at its position. Any other
    /// element on top, or none, refuses the pop and ends the flow.
    /// `->->` pops the void its `ev void /ev` pushed, as C# does before it
    /// pops the call stack (Story.cs ~1263-1270).
    private func returnFromTunnel() {
        _ = state.evalStack.popLast()
        guard let element = state.returnStack.pop(.tunnel) else {
            return refusePop(.tunnel)
        }
        applyAbsoluteDivert(element.returnPath.appending(.index(element.returnIndex)))
    }

    /// A `->->` or `~ret` whose element is missing or of the other kind: report
    /// the reference's error and end the flow, as C# `AddError` → `ForceEnd`
    /// (Story.cs ~2838-2857) resets the call stack and drops the choices.
    private func refusePop(_ kind: CallKind) {
        errors.append(state.returnStack.popRefusal(kind))
        forceEnd()
    }

    /// A native function's runtime error: C# `AddError` → `ForceEnd`, as for
    /// a refused pop. The forced end is a safe exit, so no end-of-content
    /// error follows it.
    private func reportRuntimeError(_ error: InkRuntimeError) {
        errors.append(error.message)
        forceEnd()
    }

    /// C# `StoryState.ForceEnd` (StoryState.cs ~1185-1195), shared by `end`
    /// and every runtime error: reset the return stack, drop the choices and
    /// stop the flow with a safe exit (ADR-020 §4).
    private func forceEnd() {
        state.returnStack = []
        state.currentChoices = []
        endFlow()
    }

    /// Stop the flow with a safe exit (`done`), keeping the choices.
    private func endFlow() {
        state.isEnded = true
        state.pointer.index = Int.max
        stopReason = .safeExit
    }

    /// Whether a completed line may be returned after `node`.
    ///
    /// Only check for a completed line after nodes that don't add newlines,
    /// aren't suppressed by a recent divert, and aren't inside an eval block.
    /// After a .newline node we defer the check so that a subsequent glue
    /// (<>) has a chance to remove the newline before we return. The line
    /// will be flushed on a later iteration (after the next text/glue node).
    ///
    /// Defer flush across a multi-choice cluster: once a choicePoint
    /// has been collected (`currentChoices` non-empty), continue stepping
    /// through the rest of the cluster's choicePoints + their eval blocks
    /// in the same stepToNextLine call. Otherwise a buffered line
    /// (e.g. a gather text emitted just before the cluster) flushes at
    /// the first /ev boundary AFTER c-0, returning early and leaving
    /// c-1, c-2, ... unvisited. This matches the canonical C# runtime:
    /// `state.canContinue` depends on pointer position, NOT on
    /// currentChoices, so its Continue() loop keeps stepping past
    /// choicePoints until the container exhausts. Any pending line
    /// here will be returned by `flushRemainingOutput` when the loop
    /// exits (with a single line at a time per the consumeNextLine
    /// semantic).
    private func mayFlushLine(after node: NodeKind, context: StepContext) -> Bool {
        if case .newline = node {
            return false
        }
        if context.suppressConsumeAfterDivert {
            return false
        }
        if context.evalBlockDepth > 0 {
            return false
        }
        if stepWithoutOutputFollowsEvalBlock(endingWith: node) {
            return false
        }
        return state.currentChoices.isEmpty
    }

    /// After /ev, peek at the next node: if it is a VAR= assignment or a choice
    /// point, defer the flush so that it executes before the buffered line is
    /// returned. This matches the C# runtime where Continue() keeps stepping
    /// past /ev when the immediately-following node adds no output. A VAR= node
    /// after /ev is part of the same Ink statement as the preceding eval block;
    /// a choice point after it is the choice that block built, so the line
    /// before a choice is returned with that choice already offered, as C#
    /// returns it (Continue steps on until the pointer runs out at the choices).
    private func stepWithoutOutputFollowsEvalBlock(endingWith node: NodeKind) -> Bool {
        guard case .controlCommand("/ev") = node,
              let nextTop = containerStack.last,
              nextTop.index < nextTop.container.children.count
        else { return false }
        switch nextTop.container.children[nextTop.index] {
        case .variableAssignment, .choicePoint:
            return true
        default:
            return false
        }
    }

    /// Process a `.choicePoint` node encountered during step execution.
    /// Updates `state.currentChoices` if the choice passes all filters,
    /// or captures the invisible-default path for later auto-divert.
    private func collectChoicePoint(
        target: PathReference,
        flags: ChoiceFlags,
        pendingInvisibleDefaultPath: inout ContainerPath?
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
            pendingInvisibleDefaultPath = pendingInvisibleDefaultPath ?? resolveAbsoluteTargetPath(for: target)
            discardPendingChoiceTextFromEvalStack()
            return
        }

        guard isChoiceOffered(target: target, flags: flags) else {
            // Pop any pending choice text string to keep the stack balanced.
            discardPendingChoiceTextFromEvalStack()
            return
        }

        let (choiceText, choiceTags) = resolveChoiceTextAndTags()
        let index = state.currentChoices.count
        // Capture the continuation stack NOW while containerStack still
        // has the choice-collection context. This snapshot survives
        // save/restore and lets chooseChoice resume even on a fresh engine.
        let continuationFrames = buildContinuationFrames(forTarget: target)
        state.currentChoices.append(
            ChoiceData(
                text: choiceText,
                targetPath: target.description,
                continuationFrames: continuationFrames,
                index: index,
                flags: flags,
                tags: choiceTags
            )
        )
    }

    /// Whether a visible choice point passes its filters.
    ///
    /// hasCondition: a preceding ev.../ev block has left a boolean on the
    /// evalStack. Pop it unconditionally to keep the stack balanced; the
    /// choice is skipped if the result is false.
    ///
    /// isOnceOnly: suppressed if already chosen. The resolved absolute path is
    /// the suppression key so that identically-named relative paths in
    /// different containers do not incorrectly collide.
    private func isChoiceOffered(target: PathReference, flags: ChoiceFlags) -> Bool {
        if flags.contains(.hasCondition), (state.evalStack.popLast() ?? .bool(false)).asBool == false {
            return false
        }
        guard flags.contains(.isOnceOnly), let absolutePath = resolveAbsoluteTargetPath(for: target) else {
            return true
        }
        return state.chosenChoiceTargets.contains(absolutePath) == false
    }

    /// Discard a pending choice-text string from the evalStack without consuming it.
    /// Called when a choice is skipped (condition false, once-only suppressed, or
    /// invisible-default) so that the str/text/str-accumulated string does not linger
    /// on the evalStack and corrupt later conditional evaluations. Also drops any
    /// choice-level tags accumulated for the skipped choice — see
    /// `resolveChoiceTextAndTags`.
    private func discardPendingChoiceTextFromEvalStack() {
        if case .string(_) = state.evalStack.last {
            state.evalStack.removeLast()
        }
        state.stringModeTags = []
    }

    /// Resolve the display text AND any choice-level tags (`* [Text # tag]`)
    /// for a choice point. The tags are whatever `state.stringModeTags`
    /// accumulated while the preceding `ev str …/str /ev` block ran (see
    /// `StoryState.stringModeTags`) — drained here regardless of which
    /// `resolveChoiceText()` fallback produced the text, since a tag can only
    /// ever have accumulated when that block actually ran a `str`/`/str` span.
    /// Mirrors the C# reference `Story.PopChoiceStringAndTags`.
    private func resolveChoiceTextAndTags() -> (text: String, tags: [String]) {
        let tags = state.stringModeTags
        state.stringModeTags = []
        return (resolveChoiceText(), tags)
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
        return state.outputStream.joinedText
    }

    /// Follow a `.divert` node encountered during step execution.
    private func followPlainDivert(target: DivertTarget, isConditional: Bool) {
        // Do NOT flush the output stream before the divert. The divert destination
        // may begin with a glue (<>) node that removes a pending \n from the stream —
        // flushing here would return the line before the glue has a chance to join it
        // with the continuation text (e.g. "Awkward, I reply" + glue + ", sipping...").
        if isConditional {
            // Conditional diverts pop a bool from the eval stack; false = skip divert.
            let condition = state.evalStack.popLast() ?? .bool(false)
            guard condition.asBool else { return }
        }
        // As in Story.cs (PerformLogicAndFlowControl): the condition gates the divert,
        // then the target resolves — a variable target too, conditional or not.
        switch target {
        case .path(let reference):
            followDivert(to: reference)
        case .variable(let name):
            // Variable divert: look up the target variable in variablesState.
            // The variable holds a divert-target path stored as a string value
            // (placed there by the {^->: "path"} + {temp=: "$varName"} mechanism).
            if case .string(let path)? = state.variablesState[name] {
                applyDivert(target: path)
                recordVariableDivertTarget(path)
            }
        }
    }

    /// Extract one complete line from the output stream, or nil if no newline is present yet.
    private func consumeNextLine() -> String? {
        guard state.outputStream.contains(.newline) else { return nil }
        return extractLine().text + "\n"
    }

    /// Split the line off the front of the output stream, keeping the remainder:
    /// `currentTags` become that line's tags (ADR-020 §2). A tag the lookahead
    /// collected past the newline stays in the remainder, with the next line.
    private func extractLine() -> OutputLine {
        let line = OutputLine(splitting: state.outputStream)
        state.outputStream = line.remainder
        state.currentTags = line.tags
        return line
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
        let remaining = extractLine().text
        return remaining.isEmpty ? nil : remaining
    }

    // MARK: - Function call / return

    /// A call-stack element returning to the current execution position: the
    /// top frame's path and its execution index (already past the call node).
    private func returnElement(_ kind: CallKind) -> CallStackElement {
        guard let top = containerStack.last else {
            return CallStackElement(kind: kind, returnPath: .root, returnIndex: 0)
        }
        return CallStackElement(kind: kind, returnPath: top.pathFromRoot, returnIndex: top.index)
    }

    /// Push a function return address for the current execution position and
    /// divert to the function body. Called for a `.functionCall` node (an Ink
    /// function call rather than a plain goto).
    private func applyFunctionCall(target: PathReference) {
        state.returnStack.append(returnElement(.function))
        // Push a new empty per-frame temp-variable scope so `temp= x` declarations
        // inside the function body don't leak into `variablesState` (or get
        // confused with the caller's locals with the same name).
        state.callFrameVariables.append([:])
        followDivert(to: target)
        // Record the stack depth of the function's own body frame. Anything deeper
        // is a nested sub-container whose exhaustion must pop one level instead of
        // ending the call — see the implicit-void-return branch in stepToNextLine.
        functionRootDepths.append(containerStack.count)
    }

    /// Restore execution to a function element's return position: the caller's
    /// container path and the execution index after the call.
    private func applyFunctionReturn(to element: CallStackElement) {
        // Pop the function's per-frame temp-variable scope. Local `temp= x`
        // declarations made inside the function body are discarded here.
        if !state.callFrameVariables.isEmpty {
            state.callFrameVariables.removeLast()
        }
        // Pop the matching body-frame depth recorded by `applyFunctionCall`.
        if !functionRootDepths.isEmpty {
            functionRootDepths.removeLast()
        }
        let path = element.returnPath
        let targetIndex = element.returnIndex
        if path == .root {
            // Root container return: rebuild from root at targetIndex
            containerStack = [ContainerFrame(container: root, index: targetIndex, pathFromRoot: .root)]
            state.pointer.containerPath = .root
        } else {
            // Always rebuild the full ancestor stack so relative diverts in the caller
            // body (e.g. ".^.^.^.g-3") can find their anchor container at the correct
            // depth. A single-frame stack would make those caret counts fail.
            if let container = resolver.node(at: path) {
                rebuildFullStack(to: path, container: container, targetIndex: targetIndex)
            } else if case .index(let startIndex)? = path.components.last,
                      let parentContainer = resolver.node(at: path.parent) {
                rebuildStackForParentPath(path.parent, container: parentContainer, startIndex: startIndex)
                containerStack[containerStack.count - 1].index = targetIndex
            }
        }
    }

    /// Advance one line and store the result in lastCompletedLine.
    func step() {
        // Prologue (ADR-020 §3-4, C# ResetOutput): the last line's tags and
        // the last stop reason go.
        state.currentTags = []
        stopReason = nil
        lastCompletedLine = stepToNextLine() ?? ""
        state.lastCompletedLine = lastCompletedLine
        reportEndOfContent()
    }

    /// Epilogue (ADR-020 §5, C# Story.cs ContinueInternal ~502-516): a flow
    /// that ran out without choices reports why. C# also requires that no
    /// temporary evaluation container is active; InkSwift has no
    /// `EvaluateFunction`, so that holds. A future `EvaluateFunction` must
    /// suppress this epilogue while it runs.
    private func reportEndOfContent() {
        let message = FlowEndDiagnosis.message(
            stopReason: stopReason,
            returnStackTop: state.returnStack.last?.kind,
            choicesEmpty: state.currentChoices.isEmpty)
        if let message {
            errors.append(message)
        }
    }

    // MARK: - Path resolution

    /// The top frame's path, typed for the resolver: the anchor of every
    /// relative path the engine resolves.
    private var currentPath: ContainerPath {
        containerStack.last?.pathFromRoot ?? .root
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
        destPath: ContainerPath,
        destContainer: ContainerNode,
        startIndex: Int = 0
    ) {
        var ancestors: [ContainerFrame] = []
        var discardedRoot = false
        for frame in containerStack {
            if frame.pathFromRoot.isStrictPrefix(of: destPath) {
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

    /// Resolve a choice target path (relative or absolute) to its absolute path,
    /// validating that the target container actually exists. Relative paths are
    /// resolved against the current containerStack. The result is also the
    /// suppression key in `state.chosenChoiceTargets`. Returns nil when the path
    /// cannot be resolved or the target does not exist.
    private func resolveAbsoluteTargetPath(for target: PathReference) -> ContainerPath? {
        resolver.absolutePath(of: target, from: currentPath)
    }

    /// Build a serialisable continuation-stack snapshot for a choice target.
    /// Captures the parent frames at choice-collection time plus a frame for the
    /// continuation container itself. The snapshot is stored inside `ChoiceData`
    /// so chooseChoice can resume even after a save/restore round-trip.
    private func buildContinuationFrames(forTarget target: PathReference) -> [ContainerStackFrame] {
        guard let continuationPath = resolveAbsoluteTargetPath(for: target) else { return [] }
        let continuation = ContainerStackFrame(pathFromRoot: continuationPath, executionIndex: 0)
        // Absolute path: continuation is a top-level lookup; no parent frames.
        guard case .relative = target else { return [continuation] }
        // Relative path: derive parent frames from the current containerStack
        // and append the continuation, at its resolved absolute path.
        // Parent snapshots are the current frames whose pathFromRoot is a STRICT
        // prefix of the continuation path — same rule as installDestinationFrame.
        let parentSnapshots = containerStack.compactMap { frame -> ContainerStackFrame? in
            guard frame.pathFromRoot.isStrictPrefix(of: continuationPath) else { return nil }
            return ContainerStackFrame(pathFromRoot: frame.pathFromRoot, executionIndex: frame.index)
        }
        return parentSnapshots + [continuation]
    }

    /// Execute a node that reads a visit count, which TreeWalker cannot: the
    /// counter and the resolver live here. Returns false for any other node.
    ///
    /// - `.readCount` resolves relative CNT? paths against the actual
    ///   containerStack frame paths.
    /// - `visit` pushes the 0-based visit index of the current container: its
    ///   visit was already counted on entry, so the first visit yields 0.
    private func executeVisitCountNode(_ node: NodeKind) -> Bool {
        switch node {
        case .readCount(let key):
            let visitCount = resolveReadCountKey(key).map { visitCounter.count(at: $0, in: state) } ?? 0
            state.evalStack.append(.int(visitCount))
        case .controlCommand("visit"):
            let visitCount = visitCounter.count(at: state.pointer.containerPath, in: state)
            state.evalStack.append(.int(max(0, visitCount - 1)))
        default:
            return false
        }
        return true
    }

    /// Resolve a CNT? path key to the absolute path its visit count is stored under.
    /// Nil for a relative key whose carets climb above the root: it matches no
    /// visit count.
    private func resolveReadCountKey(_ key: PathReference) -> ContainerPath? {
        resolver.readCountKey(for: key, from: currentPath)
    }

    // MARK: - Divert handling

    /// Divert to `target`: relative (`.^.…`) or absolute. Conditional branches
    /// (`{"->":"...","c":true}`) resolve exactly the same way once their condition
    /// holds.
    private func applyDivert(target: String) {
        applyDivert(to: PathReference(parsing: target))
    }

    /// Divert to a target in the story tree (a plain divert, a tunnel, a
    /// function call) and count the containers it entered.
    private func followDivert(to reference: PathReference) {
        let previous = currentPath
        applyDivert(to: reference)
        recordDivertEntries(from: previous)
    }

    /// A variable divert to a container counts only that container: C#
    /// `PointerAtPath` points at the container itself (index -1), so
    /// `VisitChangedContainersDueToDivert` returns early and `Step` counts the
    /// container as it enters it. Its ancestors are not counted.
    private func recordVariableDivertTarget(_ target: String) {
        guard case .absolute(let path) = PathReference(parsing: target),
              let container = resolver.node(at: path) else { return }
        recordVisit(to: container, at: path)
    }

    /// Divert to an already-parsed path reference (a tunnel target from the tree).
    private func applyDivert(to reference: PathReference) {
        switch reference {
        case .relative(let parentSteps, let tail):
            applyRelativeDivert(parentSteps: parentSteps, tail: tail)
        case .absolute(let path):
            applyAbsoluteDivert(path)
        }
        // If unresolvable, the stack is left as-is (it will exhaust and stop).
    }

    /// Resolution follows the canonical C# runtime semantic: carets count
    /// compiled path-component depth, not execution-stack frame depth. See
    /// `ContainerPathResolver.anchorPath` for the full reference.
    /// `installDestinationFrame` preserves frames whose pathFromRoot is a strict
    /// prefix of the destination and propagates any discarded
    /// choice-continuation-root marker to the new top frame.
    private func applyRelativeDivert(parentSteps: Int, tail: [PathComponent]) {
        guard let anchorPath = resolver.anchorPath(parentSteps: parentSteps, from: currentPath),
              let anchor = resolver.node(at: anchorPath) else { return }
        if tail.isEmpty {
            // Pure ancestor goto: restart the anchor at index 0.
            installDestinationFrame(destPath: anchorPath, destContainer: anchor)
            return
        }
        if let (destination, resolvedPath) = resolver.destination(of: tail, from: anchorPath) {
            installDestinationFrame(destPath: resolvedPath, destContainer: destination)
            return
        }
        // Numeric execution-position divert (e.g. ".^.^.^.7"): the last component
        // is a child index, not a container name. Jump to that execution position
        // in the anchor.
        if tail.count == 1, case .index(let startIndex) = tail[0] {
            installDestinationFrame(destPath: anchorPath, destContainer: anchor, startIndex: startIndex)
        }
    }

    private func applyAbsoluteDivert(_ path: ContainerPath) {
        if path.components.last?.isAnchor == true {
            applyAnchorDivert(path)
            return
        }
        if let container = resolver.node(at: path) {
            let ancestors = resolver.contentAncestors(of: path).map { ancestor in
                ContainerFrame(container: ancestor.container, index: ancestor.resumeIndex, pathFromRoot: ancestor.path)
            }
            containerStack = ancestors + [ContainerFrame(container: container, index: 0, pathFromRoot: path)]
            state.pointer.containerPath = path
            return
        }
        // Path whose last component is a numeric index into the parent container
        // (e.g. "café.0.6" = execute A starting from index 6). The parent container
        // is resolved by dropping the index and the full parent stack is rebuilt.
        let parentPath = path.parent
        if case .index(let startIndex)? = path.components.last, let parentContainer = resolver.node(at: parentPath) {
            rebuildStackForParentPath(parentPath, container: parentContainer, startIndex: startIndex)
        }
    }

    /// Anchor divert: jump to the position just after the named anchor marker,
    /// rebuilding the full ancestor stack so relative diverts remain resolvable.
    private func applyAnchorDivert(_ path: ContainerPath) {
        guard let (parentContainer, startIndex) = resolver.anchorTarget(of: path) else { return }
        rebuildStackForParentPath(path.parent, container: parentContainer, startIndex: startIndex)
    }

    /// Rebuild the full container stack for a return to a known container, preserving
    /// all ancestor frames so that relative diverts inside the target body resolve correctly.
    /// `fullPath` is the absolute path of the target container; `container` is its node.
    private func rebuildFullStack(to fullPath: ContainerPath, container: ContainerNode, targetIndex: Int) {
        rebuildStackForParentPath(fullPath.parent, container: container, startIndex: targetIndex)
        // rebuildStackForParentPath ends with a frame that has pathFromRoot: parentPath.
        // Overwrite the final frame's pathFromRoot with the full path so callers see
        // the correct container path (e.g. "start.waited.0.g-2.c-7", not "start.waited.0.g-2").
        if !containerStack.isEmpty {
            containerStack[containerStack.count - 1].pathFromRoot = fullPath
            state.pointer.containerPath = fullPath
        }
    }

    /// Rebuild the container stack to reflect a jump to `startIndex` within `container`,
    /// reconstructing all ancestor frames from the absolute `parentPath`: each
    /// resumes just past the child it entered (see `ContainerPathResolver.descend`).
    private func rebuildStackForParentPath(_ parentPath: ContainerPath, container: ContainerNode, startIndex: Int) {
        var frames = resolver.ancestors(along: parentPath).map { ancestor in
            ContainerFrame(container: ancestor.container, index: ancestor.resumeIndex, pathFromRoot: ancestor.path)
        }
        // Final frame: the target container at the specified startIndex
        frames.append(ContainerFrame(container: container, index: startIndex, pathFromRoot: parentPath))
        containerStack = frames
        state.pointer.containerPath = parentPath
    }

    // MARK: - Choice handling

    func chooseChoice(at index: Int) throws {
        let offered = offeredChoices
        guard index >= 0 && index < offered.count else {
            throw StoryError.invalidChoiceIndex(index)
        }
        let choice = offered[index]
        if choice.flags.contains(.isOnceOnly) {
            recordChosen(choice)
        }
        state.currentChoices = []
        state.currentTags = []
        state.isEnded = false
        installContinuation(of: choice)
    }

    /// Record the absolute path of a chosen once-only target so the suppression
    /// check in `isChoiceOffered` can match it reliably across contexts. A
    /// once-only `*` choice is ALWAYS suppressed once chosen — including
    /// when its body diverts back to its own enclosing gather (the Cass /
    /// The-Intercept `(think) -> opts` pattern). Sticky `+` choices, which
    /// are meant to remain available on every visit, never carry the
    /// `.isOnceOnly` flag and so never reach this.
    private func recordChosen(_ choice: ChoiceData) {
        if let absolutePath = choice.continuationFrames.last?.pathFromRoot {
            state.chosenChoiceTargets.insert(absolutePath)
        }
    }

    /// Install the continuation stack snapshot captured at choice-collection time.
    private func installContinuation(of choice: ChoiceData) {
        var rebuilt = framesFromSnapshots(continuationSnapshot(of: choice))
        guard let topFrame = rebuilt.last else { return }
        // Mark the top frame as the callstack root for this choice. When the
        // continuation exhausts, the engine stops instead of popping into the
        // parent and re-generating the outer choices.
        rebuilt[rebuilt.count - 1].isChoiceContinuationRoot = true
        containerStack = rebuilt
        state.pointer.containerPath = topFrame.pathFromRoot
        state.pointer.index = 0
        // Choice bodies entered via chooseChoice go through neither sequential
        // descent nor applyDivert, so their visit is counted explicitly here.
        recordVisit(to: topFrame.container, at: topFrame.pathFromRoot)
    }

    /// The choice's continuation frames. Falls back to absolute-path lookup of
    /// targetPath for hand-crafted/legacy JSON fixtures that may not have
    /// populated continuationFrames.
    private func continuationSnapshot(of choice: ChoiceData) -> [ContainerStackFrame] {
        if choice.continuationFrames.isEmpty == false {
            return choice.continuationFrames
        }
        guard case .absolute(let path) = PathReference(parsing: choice.targetPath),
              resolver.node(at: path) != nil else { return [] }
        return [ContainerStackFrame(pathFromRoot: path, executionIndex: 0)]
    }

    // MARK: - Save / restore

    func saveState() throws -> Data {
        // Snapshot the full container execution stack so restore can rebuild it exactly.
        // Each frame records the container's absolute path from the story root
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
        visitCounter.canonicaliseKeys(in: &state)
        lastCompletedLine = state.lastCompletedLine
        errors = []
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
        resolver.node(at: state.pointer.containerPath) ?? root
    }

    /// Walk each stack-frame snapshot's pathFromRoot from root to rebuild the
    /// in-memory ContainerFrame stack. Frames that fail to resolve truncate
    /// the stack at that depth.
    private func framesFromSnapshots(_ snapshots: [ContainerStackFrame]) -> [ContainerFrame] {
        var rebuilt: [ContainerFrame] = []
        for snapshot in snapshots {
            guard let container = resolver.node(at: snapshot.pathFromRoot) else { break }
            rebuilt.append(ContainerFrame(
                container: container,
                index: snapshot.executionIndex,
                pathFromRoot: snapshot.pathFromRoot,
                isChoiceContinuationRoot: snapshot.isChoiceContinuationRoot
            ))
        }
        return rebuilt.isEmpty ? [ContainerFrame(container: root, index: 0, pathFromRoot: .root)] : rebuilt
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
        case .variablePointer, .void: return nil
        }
    }

    // MARK: - Visit count access

    /// Return the visit count for a knot by name. Returns 0 for unknown knots.
    /// The name is read as a saved key, so a dotted `knot.stitch` works too.
    func visitCount(forKnot name: String) -> Int {
        visitCounter.count(at: ContainerPath(savedKey: name), in: state)
    }

    /// Set the visit count for a knot by name.
    /// Pure no-op when the knot does not exist in the story structure.
    func setVisitCount(forKnot name: String, to count: Int) {
        guard root.namedContent[name] != nil else { return }
        visitCounter.setCount(count, at: ContainerPath(savedKey: name), in: &state)
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
        // D1: reset 14 StoryState fields (RD-01); stackFrames intentionally NOT cleared
        state.returnStack = []
        state.evalStack = []
        state.currentChoices = []
        state.outputStream = []
        state.currentTags = []
        state.callFrameVariables = []
        state.suppressNextNewline = false
        state.isEnded = false
        state.inTagMode = false
        state.tagAccumulator = ""
        state.inStringMode = false
        state.stringAccumulator = ""
        state.stringModeTags = []
        errors = []
        // D4: delegate stack installation to applyDivert. C# ChoosePathString
        // resets the callstack first (previous pointer null), so every container
        // on the way in is counted.
        applyDivert(target: targetPath)
        recordDivertEntries(from: nil)
    }
}
