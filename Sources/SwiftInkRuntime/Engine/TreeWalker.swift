struct TreeWalker {

    // MARK: - Public API

    /// Advance execution by one node, updating `state` in place.
    /// Returns the NodeKind that was processed, or nil when the container is exhausted.
    func step(in container: ContainerNode, state: inout StoryState) -> NodeKind? {
        guard state.pointer.index < container.children.count else { return nil }
        let child = container.children[state.pointer.index]
        state.pointer.index += 1
        dispatch(child, state: &state)
        return child
    }

    // MARK: - Dispatch (internal entry point for InkEngine)

    func dispatchNode(_ node: NodeKind, state: inout StoryState) {
        dispatch(node, state: &state)
    }

    // MARK: - Private dispatch

    private func dispatch(_ node: NodeKind, state: inout StoryState) {
        switch node {
        case .text(let string):
            handleText(string, state: &state)

        case .newline:
            state.outputStream.append("\n")

        case .controlCommand(let cmd):
            handleControlCommand(cmd, state: &state)

        case .divert(let target, _, _):
            handleDivert(target: target, state: &state)

        case .pushDivertTarget(let path):
            state.returnStack.append(path)

        case .choicePoint:
            break  // handled by InkEngine before dispatchNode is reached

        case .variableAssignment(let name, _):
            handleVariableAssignment(name: name, state: &state)

        case .variableReference(let name):
            handleVariableReference(name: name, state: &state)

        case .intValue(let value):
            state.evalStack.append(.int(value))

        case .floatValue(let value):
            state.evalStack.append(.float(value))

        case .tagOpen:
            state.inTagMode = true
            state.tagAccumulator = ""

        case .tagClose:
            state.currentTags.append(state.tagAccumulator)
            state.inTagMode = false
            state.tagAccumulator = ""

        case .nativeFunction(let fn):
            handleNativeFunction(fn, state: &state)

        case .voidValue:
            break  // no-op

        case .container:
            break  // inline sub-containers handled by InkEngine via path resolution
        }
    }

    // MARK: - Text handling

    private func handleText(_ string: String, state: inout StoryState) {
        if state.inTagMode {
            state.tagAccumulator += string
        } else if state.inStringMode {
            state.stringAccumulator += string
        } else {
            state.outputStream.append(string)
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
                state.outputStream.append(top.asString)
            }

        case "str":
            // Begin string accumulation mode
            state.inStringMode = true
            state.stringAccumulator = ""

        case "/str":
            // End string mode, push accumulated string onto eval stack
            let accumulated = state.stringAccumulator
            state.inStringMode = false
            state.stringAccumulator = ""
            state.evalStack.append(.string(accumulated))

        case "pop":
            _ = state.evalStack.popLast()

        case "done", "end":
            state.isEnded = true
            state.pointer.index = Int.max

        case "nop":
            break  // no-op

        case "visit":
            // Record visit count for current container
            let pathKey = state.pointer.containerPath.joined(separator: ".")
            state.visitCounts[pathKey, default: 0] += 1

        case "#n":
            break  // anonymous named-container reference marker — no-op at walk time

        default:
            break  // unknown control commands are no-ops
        }
    }

    // MARK: - Divert handling

    private func handleDivert(target: String, state: inout StoryState) {
        // Split dotted path into components
        let components = target.split(separator: ".").map(String.init)
        state.pointer.containerPath = components
        state.pointer.index = 0
    }

    // MARK: - Variable handling

    private func handleVariableAssignment(name: String, state: inout StoryState) {
        if let value = state.evalStack.popLast() {
            state.variablesState[name] = value
        }
    }

    private func handleVariableReference(name: String, state: inout StoryState) {
        if let value = state.variablesState[name] {
            state.evalStack.append(value)
        }
    }

    // MARK: - Native function handling

    private func handleNativeFunction(_ fn: String, state: inout StoryState) {
        switch fn {
        case "+":   applyBinaryOp(state: &state) { $0.adding($1) }
        case "-":   applyBinaryOp(state: &state) { $0.subtracting($1) }
        case "*":   applyBinaryOp(state: &state) { $0.multiplying($1) }
        case "/":   applyBinaryOp(state: &state) { $0.dividing(by: $1) }
        case "%":   applyBinaryOp(state: &state) { $0.modulo($1) }
        case "==":  applyBinaryOp(state: &state) { .bool($0 == $1) }
        case "!=":  applyBinaryOp(state: &state) { .bool($0 != $1) }
        case ">":   applyBinaryOp(state: &state) { $0.comparing(to: $1, using: >) }
        case "<":   applyBinaryOp(state: &state) { $0.comparing(to: $1, using: <) }
        case ">=":  applyBinaryOp(state: &state) { $0.comparing(to: $1, using: >=) }
        case "<=":  applyBinaryOp(state: &state) { $0.comparing(to: $1, using: <=) }
        case "!":
            applyUnaryOp(state: &state) { value in
                guard case .bool(let b) = value else { return value }
                return .bool(!b)
            }
        case "&&":  applyBinaryOp(state: &state) { .bool($0.asBool && $1.asBool) }
        case "||":  applyBinaryOp(state: &state) { .bool($0.asBool || $1.asBool) }
        case "srnd":    _ = state.evalStack.popLast()  // pop seed; result is implementation-defined
        case "floor":   applyUnaryOp(state: &state) { $0.floored }
        case "ceiling": applyUnaryOp(state: &state) { $0.ceiled }
        case "int":     applyUnaryOp(state: &state) { $0.toInt }
        case "float":   applyUnaryOp(state: &state) { $0.toFloat }
        default:    break  // unsupported native functions are no-ops
        }
    }

    // MARK: - Stack operation helpers

    private func applyUnaryOp(state: inout StoryState, op: (InkValue) -> InkValue) {
        guard let top = state.evalStack.popLast() else { return }
        state.evalStack.append(op(top))
    }

    private func applyBinaryOp(
        state: inout StoryState,
        op: (InkValue, InkValue) -> InkValue
    ) {
        guard state.evalStack.count >= 2 else { return }
        let rhs = state.evalStack.removeLast()
        let lhs = state.evalStack.removeLast()
        state.evalStack.append(op(lhs, rhs))
    }
}
