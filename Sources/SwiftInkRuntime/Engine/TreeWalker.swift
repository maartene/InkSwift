import Foundation

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

        case .divert(let target, _):
            handleDivert(target: target, state: &state)

        case .choicePoint(let target, let flags):
            handleChoicePoint(target: target, flags: flags, state: &state)

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
            // Pop top of eval stack, convert to string, append to outputStream
            if let top = state.evalStack.popLast() {
                state.outputStream.append(inkValueToString(top))
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

    // MARK: - Choice point handling

    private func handleChoicePoint(target: String, flags: Int, state: inout StoryState) {
        // Collect current outputStream content as choice label
        let choiceText = state.outputStream.filter { $0 != "\n" }.joined()
        let choiceIndex = state.currentChoices.count
        let choice = ChoiceData(text: choiceText, targetPath: target, index: choiceIndex)
        state.currentChoices.append(choice)
        // Clear accumulated output that was used as choice text
        state.outputStream.removeAll { $0 != "\n" }
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
        case "+":
            applyBinaryOp(state: &state) { lhs, rhs in addInkValues(lhs, rhs) }
        case "-":
            applyBinaryOp(state: &state) { lhs, rhs in subtractInkValues(lhs, rhs) }
        case "*":
            applyBinaryOp(state: &state) { lhs, rhs in multiplyInkValues(lhs, rhs) }
        case "/":
            applyBinaryOp(state: &state) { lhs, rhs in divideInkValues(lhs, rhs) }
        case "%":
            applyBinaryOp(state: &state) { lhs, rhs in moduloInkValues(lhs, rhs) }
        case "==":
            applyBinaryOp(state: &state) { lhs, rhs in .bool(lhs == rhs) }
        case "!=":
            applyBinaryOp(state: &state) { lhs, rhs in .bool(lhs != rhs) }
        case ">":
            applyBinaryOp(state: &state) { lhs, rhs in compareInkValues(lhs, rhs, op: >) }
        case "<":
            applyBinaryOp(state: &state) { lhs, rhs in compareInkValues(lhs, rhs, op: <) }
        case ">=":
            applyBinaryOp(state: &state) { lhs, rhs in compareInkValues(lhs, rhs, op: >=) }
        case "<=":
            applyBinaryOp(state: &state) { lhs, rhs in compareInkValues(lhs, rhs, op: <=) }
        case "!":
            if let top = state.evalStack.popLast(), case .bool(let b) = top {
                state.evalStack.append(.bool(!b))
            }
        case "&&":
            applyBinaryOp(state: &state) { lhs, rhs in
                .bool(inkValueToBool(lhs) && inkValueToBool(rhs))
            }
        case "||":
            applyBinaryOp(state: &state) { lhs, rhs in
                .bool(inkValueToBool(lhs) || inkValueToBool(rhs))
            }
        case "srnd":
            _ = state.evalStack.popLast()  // pop seed, result is implementation-defined
        case "floor":
            if let top = state.evalStack.popLast() {
                state.evalStack.append(floorInkValue(top))
            }
        case "ceiling":
            if let top = state.evalStack.popLast() {
                state.evalStack.append(ceilingInkValue(top))
            }
        case "int":
            if let top = state.evalStack.popLast() {
                state.evalStack.append(toIntInkValue(top))
            }
        case "float":
            if let top = state.evalStack.popLast() {
                state.evalStack.append(toFloatInkValue(top))
            }
        default:
            break  // unsupported native functions are no-ops for this implementation
        }
    }

    // MARK: - Helpers

    private func inkValueToString(_ value: InkValue) -> String {
        switch value {
        case .int(let n): return String(n)
        case .float(let f): return String(f)
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        }
    }

    private func inkValueToBool(_ value: InkValue) -> Bool {
        switch value {
        case .bool(let b): return b
        case .int(let n): return n != 0
        case .float(let f): return f != 0.0
        case .string(let s): return !s.isEmpty
        }
    }

    private func inkValueToDouble(_ value: InkValue) -> Double {
        switch value {
        case .int(let n): return Double(n)
        case .float(let f): return f
        case .bool(let b): return b ? 1.0 : 0.0
        case .string: return 0.0
        }
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

    // MARK: - Arithmetic helpers

    private func addInkValues(_ lhs: InkValue, _ rhs: InkValue) -> InkValue {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return .int(a + b)
        case (.string(let a), .string(let b)): return .string(a + b)
        default: return .float(inkValueToDouble(lhs) + inkValueToDouble(rhs))
        }
    }

    private func subtractInkValues(_ lhs: InkValue, _ rhs: InkValue) -> InkValue {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return .int(a - b)
        default: return .float(inkValueToDouble(lhs) - inkValueToDouble(rhs))
        }
    }

    private func multiplyInkValues(_ lhs: InkValue, _ rhs: InkValue) -> InkValue {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return .int(a * b)
        default: return .float(inkValueToDouble(lhs) * inkValueToDouble(rhs))
        }
    }

    private func divideInkValues(_ lhs: InkValue, _ rhs: InkValue) -> InkValue {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)) where b != 0: return .int(a / b)
        default:
            let denominator = inkValueToDouble(rhs)
            guard denominator != 0.0 else { return .float(0.0) }
            return .float(inkValueToDouble(lhs) / denominator)
        }
    }

    private func moduloInkValues(_ lhs: InkValue, _ rhs: InkValue) -> InkValue {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)) where b != 0: return .int(a % b)
        default:
            let denominator = inkValueToDouble(rhs)
            guard denominator != 0.0 else { return .float(0.0) }
            return .float(inkValueToDouble(lhs).truncatingRemainder(dividingBy: denominator))
        }
    }

    private func compareInkValues(
        _ lhs: InkValue,
        _ rhs: InkValue,
        op: (Double, Double) -> Bool
    ) -> InkValue {
        return .bool(op(inkValueToDouble(lhs), inkValueToDouble(rhs)))
    }

    private func floorInkValue(_ value: InkValue) -> InkValue {
        switch value {
        case .int: return value
        case .float(let f): return .int(Int(Foundation.floor(f)))
        default: return value
        }
    }

    private func ceilingInkValue(_ value: InkValue) -> InkValue {
        switch value {
        case .int: return value
        case .float(let f): return .int(Int(Foundation.ceil(f)))
        default: return value
        }
    }

    private func toIntInkValue(_ value: InkValue) -> InkValue {
        switch value {
        case .int: return value
        case .float(let f): return .int(Int(f))
        case .bool(let b): return .int(b ? 1 : 0)
        case .string(let s): return .int(Int(s) ?? 0)
        }
    }

    private func toFloatInkValue(_ value: InkValue) -> InkValue {
        switch value {
        case .float: return value
        case .int(let n): return .float(Double(n))
        case .bool(let b): return .float(b ? 1.0 : 0.0)
        case .string(let s): return .float(Double(s) ?? 0.0)
        }
    }
}
