struct TreeWalker {

    // MARK: - Public API

    /// Advance execution by one node, updating `state` in place.
    /// Returns the NodeKind that was processed, or nil when the container is exhausted.
    func step(in container: ContainerNode, state: inout StoryState) throws(InkRuntimeError) -> NodeKind? {
        guard state.pointer.index < container.children.count else { return nil }
        let child = container.children[state.pointer.index]
        state.pointer.index += 1
        try dispatch(child, state: &state)
        return child
    }

    // MARK: - Dispatch (internal entry point for InkEngine)

    /// Throws the runtime error a native function raises (ADR-017); the
    /// engine reports it and ends the flow.
    func dispatchNode(_ node: NodeKind, state: inout StoryState) throws(InkRuntimeError) {
        try dispatch(node, state: &state)
    }

    // MARK: - Private dispatch

    private func dispatch(_ node: NodeKind, state: inout StoryState) throws(InkRuntimeError) {
        switch node {
        case .text(let string):
            handleText(string, state: &state)

        case .newline:
            appendNewline(state: &state)

        case .controlCommand(let cmd):
            handleControlCommand(cmd, state: &state)

        case .divert, .functionCall:
            break  // resolved and followed by InkEngine, which owns the container stack

        case .pushDivertTarget(let path):
            // Push a divert-target value onto the evaluation stack (not the return stack).
            // The caller (ev…/ev block) stores it in a temp variable via {temp=: "$r"};
            // later, a variable divert {->: "$r", var: true} looks it up and jumps there.
            // The value stays a string (the variablesState wire format); the variable
            // divert parses it back in `InkEngine.applyDivert(target:)` — the one
            // runtime parse of a path string.
            state.evalStack.append(.string(path.description))

        case .choicePoint:
            break  // handled by InkEngine before dispatchNode is reached

        case .tunnelDivert:
            break  // handled by InkEngine before dispatchNode is reached

        case .variableAssignment(let name, let isGlobal):
            handleVariableAssignment(name: name, isGlobal: isGlobal, state: &state)

        case .variableReference(let name):
            handleVariableReference(name: name, state: &state)

        case .intValue(let value):
            state.evalStack.append(.int(value))

        case .floatValue(let value):
            state.evalStack.append(.float(value))

        case .boolValue(let value):
            state.evalStack.append(.bool(value))

        case .tagOpen:
            state.inTagMode = true
            state.tagAccumulator = ""

        case .tagClose:
            // A tag closed WHILE `inStringMode` is true is choice-level markup
            // (`* [Text # tag]`, only ever emitted inside a `str`/`/str` span —
            // see `StoryState.stringModeTags`), not a content-line tag: route it
            // there instead of the output stream so it does not leak into "tags
            // of the current output line". A content tag becomes a tag item at
            // its position in the stream (ADR-020 §1).
            //
            // The accumulated text is whitespace-cleaned and an empty tag is
            // dropped, matching the reference runtime: every tag added by
            // `StoryState.currentTags` goes through `CleanOutputWhitespace` and is
            // added only when non-empty, and a choice tag is built the same way in
            // `Story.cs`'s EndTag string-evaluation branch.
            //
            // Cleaning means BOTH trimming the edges and collapsing each internal
            // run of spaces/tabs to one space — verified against inklecate 1.2.1:
            // the source tag `#  spaced   tag  ` compiles to the json text
            // `"^spaced   tag"` (edges trimmed by the compiler, the internal run
            // kept) and the official player then reports `# tags: spaced tag`.
            // Trimming alone would leave the run intact and diverge.
            //
            // Doing it here covers both paths: a natively compiled story emits
            // `.tagOpen/.text/.tagClose` and is read back through this same case,
            // so compiler-side and json-side tags are cleaned identically.
            let tagText = state.tagAccumulator
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .joined(separator: " ")
            if tagText.isEmpty == false {
                if state.inStringMode {
                    state.stringModeTags.append(tagText)
                } else {
                    appendTag(tagText, state: &state)
                }
            }
            state.inTagMode = false
            state.tagAccumulator = ""

        case .nativeFunction(let fn):
            try handleNativeFunction(fn, state: &state)

        case .voidValue:
            break  // no-op

        case .container:
            break  // inline sub-containers handled by InkEngine via path resolution

        case .readCount:
            break  // handled by InkEngine before dispatchNode is reached

        case .variablePointer(let name, let contextIndex):
            state.evalStack.append(.variablePointer(name: name, contextIndex: contextIndex))
        }
    }

    // MARK: - Text handling

    private func handleText(_ string: String, state: inout StoryState) {
        if state.inTagMode {
            state.tagAccumulator += string
        } else if state.inStringMode {
            state.stringAccumulator += string
        } else {
            appendToOutput(string, state: &state)
        }
    }

    // MARK: - Control command handling

    private func handleControlCommand(_ cmd: String, state: inout StoryState) {
        switch cmd {
        case "ev":
            break  // begin evaluation mode — stack frames managed externally for now

        case "/ev":
            break  // end evaluation mode

        case "out":
            if let top = state.evalStack.popLast() {
                // Suppress the void sentinel pushed by implicit function returns.
                // A printed value is text like any other: inside a string or tag
                // span it belongs to that span (Story.cs EndString/EndTag collect
                // every StringValue back to the span's start).
                guard case .string(let s) = top, s == "void" else {
                    handleText(top.asString, state: &state)
                    break
                }
            }

        case "str":
            // Begin string accumulation mode. Reset stringModeTags here (not on
            // "/str") so any choice-level tag closed inside THIS span is still
            // readable by InkEngine.resolveChoiceTextAndTags after "/str" fires.
            state.inStringMode = true
            state.stringAccumulator = ""
            state.stringModeTags = []

        case "/str":
            // End string mode, push accumulated string onto eval stack
            let accumulated = state.stringAccumulator
            state.inStringMode = false
            state.stringAccumulator = ""
            state.evalStack.append(.string(accumulated))

        case "du":
            if let top = state.evalStack.last {
                state.evalStack.append(top)
            }

        case "pop":
            _ = state.evalStack.popLast()

        // The step loop never reaches these: InkEngine.executeFlowNode handles
        // `done` and `end` itself, because `end` is the engine's forceEnd()
        // (ADR-020 §4). They are reachable only from the standalone dispatch of
        // `global decl` (InkEngine.initializeGlobalVariables), which inklecate
        // closes with `end`.
        case "done", "end":
            state.isEnded = true
            state.pointer.index = Int.max

        case "<>":
            applyGlue(state: &state)

        case "nop":
            trimTrailingSpace(state: &state)

        case "#n":
            break  // anonymous named-container reference marker — no-op at walk time

        default:
            // Unknown control commands are no-ops. `visit` never gets here from
            // the step loop: InkEngine.executeVisitCountNode consumes it first,
            // because the engine owns the visit counter.
            break
        }
    }

    // MARK: - Variable handling

    private func handleVariableAssignment(name: String, isGlobal: Bool, state: inout StoryState) {
        // An empty stack is reachable from well-formed inklecate JSON, so this is
        // not a precondition: reading a temp whose declaration was skipped
        // (`{flag: ~ temp y = 1}`, then `~ temp z = y`) pushes nothing in
        // handleVariableReference, where C# warns and pushes 0.
        guard let value = state.evalStack.popLast() else { return }

        // VAR= (global): always write to variablesState, with pointer write-through
        // if the existing global is a variable pointer.
        if isGlobal {
            if case .variablePointer(let pointedName, _) = state.variablesState[name] {
                state.variablesState[pointedName] = value
            } else {
                state.variablesState[name] = value
            }
            return
        }

        // temp= (function-local): if we're inside a function call, write to the
        // top call-frame's local scope (creating it if absent). If the LOCAL slot
        // already holds a variable pointer (the ref-param pattern: caller pushes
        // pointer, function body's `temp= x` declares the param), write THROUGH
        // the pointer instead of overwriting it — this is how `~ x = x + 1`
        // inside `raise(ref x)` mutates the caller's variable.
        if !state.callFrameVariables.isEmpty {
            let frameIdx = state.callFrameVariables.count - 1
            if case .variablePointer(let pointedName, _) = state.callFrameVariables[frameIdx][name] {
                state.variablesState[pointedName] = value
            } else {
                state.callFrameVariables[frameIdx][name] = value
            }
            return
        }

        // temp= outside any function call (knot-level temp or pre-function declaration):
        // fall back to globals — same as the old single-scope behaviour.
        if case .variablePointer(let pointedName, _) = state.variablesState[name] {
            state.variablesState[pointedName] = value
        } else {
            state.variablesState[name] = value
        }
    }

    private func handleVariableReference(name: String, state: inout StoryState) {
        // Resolution order: top call-frame local (if any) → globals.
        let value: InkValue?
        if !state.callFrameVariables.isEmpty,
           let local = state.callFrameVariables[state.callFrameVariables.count - 1][name] {
            value = local
        } else {
            value = state.variablesState[name]
        }
        guard let v = value else { return }
        // If the variable holds a pointer, dereference it to the pointed-to global.
        // Ref-param pointers always point into globals (the caller's variable).
        if case .variablePointer(let pointedName, _) = v {
            let resolved = state.variablesState[pointedName] ?? .int(0)
            state.evalStack.append(resolved)
        } else {
            state.evalStack.append(v)
        }
    }

    // MARK: - Native function handling

    /// Binary natives coerce their operands to one type first (C#
    /// `CoerceValuesToSingleType`), see `BinaryNativeFunction`; one with no
    /// string form throws the reference's error on string operands. The switch
    /// is exhaustive over the catalog, so a new native cannot be silently ignored.
    private func handleNativeFunction(_ fn: NativeFunction, state: inout StoryState) throws(InkRuntimeError) {
        switch fn {
        case .add, .subtract, .multiply, .divide, .modulo, .equal, .notEqual, .greater, .less,
             .greaterOrEqual, .lessOrEqual, .and, .or, .min, .max, .pow, .has, .hasnt:
            try applyBinaryOp(fn, state: &state)
        case .not:
            applyUnaryOp(state: &state) { value in
                return .bool(!value.asBool)
            }
        // Arithmetic negation. The reference names this `_` to keep it distinct
        // from binary `-` subtraction (`NativeFunctionCall.Negate`) and defines it
        // for int and float only — `AddIntUnaryOp(Negate, x => -x)` and its float
        // counterpart, with no bool or string form. Any other value is therefore
        // left untouched rather than coerced into a number it never had.
        case .negate:
            applyUnaryOp(state: &state) { value in
                switch value {
                case .int(let number): return .int(-number)
                case .float(let number): return .float(-number)
                default: return value
                }
            }
        // The seed is popped and void pushed, as C# `Story` does, so the `pop`
        // compiled for the discarded call removes the void and nothing below it.
        // With RANDOM refused, a seed has no observable effect.
        case .seedRandom:
            _ = state.evalStack.popLast()
            state.evalStack.append(.string("void"))
        case .floor:      applyUnaryOp(state: &state) { $0.floored }
        case .ceiling:    applyUnaryOp(state: &state) { $0.ceiled }
        case .int:        applyUnaryOp(state: &state) { $0.toInt }
        case .float:      applyUnaryOp(state: &state) { $0.toFloat }
        }
    }

    // MARK: - Stack operation helpers

    /// An empty stack is reachable from well-formed JSON, see
    /// `handleVariableAssignment`; the operation is then skipped.
    private func applyUnaryOp(state: inout StoryState, op: (InkValue) -> InkValue) {
        guard let top = state.evalStack.popLast() else { return }
        state.evalStack.append(op(top))
    }

    /// Fewer than two operands is reachable from well-formed JSON, see
    /// `handleVariableAssignment`; the operation is then skipped.
    private func applyBinaryOp(_ fn: NativeFunction, state: inout StoryState) throws(InkRuntimeError) {
        guard let operation = BinaryNativeFunction.byFunction[fn], state.evalStack.count >= 2 else { return }
        let rhs = state.evalStack.removeLast()
        let lhs = state.evalStack.removeLast()
        state.evalStack.append(try operation(lhs, rhs))
    }
}
