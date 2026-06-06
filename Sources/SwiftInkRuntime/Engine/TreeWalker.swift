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
            if state.suppressNextNewline {
                state.suppressNextNewline = false
            } else {
                state.outputStream.append("\n")
            }

        case .controlCommand(let cmd):
            handleControlCommand(cmd, state: &state)

        case .divert(let target, _, _):
            handleDivert(target: target, state: &state)

        case .pushDivertTarget(let path):
            // Push a divert-target value onto the evaluation stack (not the return stack).
            // The caller (ev…/ev block) stores it in a temp variable via {temp=: "$r"};
            // later, a variable divert {->: "$r", var: true} looks it up and jumps there.
            state.evalStack.append(.string(path))

        case .choicePoint:
            break  // handled by InkEngine before dispatchNode is reached

        case .tunnelDivert:
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

        case .readCount(let key):
            // CNT? keys may be relative (starting with "."). Resolve them against the
            // current container path so they match the absolute keys in visitCounts.
            let resolvedKey = resolveReadCountPath(key, relativeTo: state.pointer.containerPath)
            state.evalStack.append(.int(state.visitCounts[resolvedKey] ?? 0))

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
            state.outputStream.append(string)
            // Once text has been appended to the output stream, any pending glue
            // suppression (<>) has already done its job of joining the preceding text.
            // The next \n will be a real line-ending, not a glue-adjacent separator.
            state.suppressNextNewline = false
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
                // Suppress the void sentinel pushed by implicit function returns
                guard case .string(let s) = top, s == "void" else {
                    state.outputStream.append(top.asString)
                    break
                }
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

        case "du":
            if let top = state.evalStack.last {
                state.evalStack.append(top)
            }

        case "pop":
            _ = state.evalStack.popLast()

        case "done", "end":
            state.isEnded = true
            state.pointer.index = Int.max

        case "<>":
            // Glue: remove any trailing newlines already in the output stream AND
            // suppress the next newline that gets appended. This joins the preceding
            // text with whatever follows the glue marker — even when the `\n` comes
            // after the `<>` node in the JSON (e.g. `"text " <> \n -> next_section`).
            while state.outputStream.last == "\n" {
                state.outputStream.removeLast()
            }
            state.suppressNextNewline = true

        case "nop":
            // Trim trailing whitespace from the output stream.
            // In inklecate, `nop` is emitted as the "else" path for inline conditionals
            // so that `{condition: then} rest` does not produce a double space when the
            // condition is false: the space that the text before the `{...}` contributed
            // is consumed here, leaving a single space before the continuation text.
            if let last = state.outputStream.last, last.last == " " {
                let trimmed = String(last.dropLast())
                state.outputStream.removeLast()
                if !trimmed.isEmpty {
                    state.outputStream.append(trimmed)
                }
            }

        case "visit":
            // Push the 0-based visit index for the current container onto the eval stack.
            // The visit count is incremented when the container is first entered (in enterContainer
            // or applyDivert); "visit" reports count-1 so the first visit yields index 0.
            let pathKey = state.pointer.containerPath.joined(separator: ".")
            let visitCount = state.visitCounts[pathKey] ?? 1
            state.evalStack.append(.int(max(0, visitCount - 1)))

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
        guard let value = state.evalStack.popLast() else { return }
        // If the existing variable holds a pointer, write through to the pointed-to global
        if case .variablePointer(let pointedName, _) = state.variablesState[name] {
            state.variablesState[pointedName] = value
        } else {
            state.variablesState[name] = value
        }
    }

    private func handleVariableReference(name: String, state: inout StoryState) {
        guard let value = state.variablesState[name] else { return }
        // If the variable holds a pointer, dereference it to get the pointed-to value
        if case .variablePointer(let pointedName, _) = value {
            let resolved = state.variablesState[pointedName] ?? .int(0)
            state.evalStack.append(resolved)
        } else {
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
                return .bool(!value.asBool)
            }
        case "&&":  applyBinaryOp(state: &state) { .bool($0.asBool && $1.asBool) }
        case "||":  applyBinaryOp(state: &state) { .bool($0.asBool || $1.asBool) }
        case "MIN":     applyBinaryOp(state: &state) { $0.asDouble <= $1.asDouble ? $0 : $1 }
        case "MAX":     applyBinaryOp(state: &state) { $0.asDouble >= $1.asDouble ? $0 : $1 }
        case "srnd":    _ = state.evalStack.popLast()  // pop seed; result is implementation-defined
        case "floor":   applyUnaryOp(state: &state) { $0.floored }
        case "ceiling": applyUnaryOp(state: &state) { $0.ceiled }
        case "int":     applyUnaryOp(state: &state) { $0.toInt }
        case "float":   applyUnaryOp(state: &state) { $0.toFloat }
        default:    break  // unsupported native functions are no-ops
        }
    }

    // MARK: - CNT? path resolution

    /// Resolve a relative CNT? key against the current container path.
    /// Relative keys start with "." and use "^" to navigate up the path hierarchy.
    /// Returns the absolute dot-joined path string suitable for visitCounts lookup.
    ///
    /// Inklecate emits caret counts relative to the NAMED container hierarchy,
    /// which does NOT count anonymous numeric-index containers (e.g. "0").
    /// To match, we strip anonymous (numeric) components from the base path when
    /// counting upward — they are transparent in inklecate's caret model.
    private func resolveReadCountPath(_ key: String, relativeTo containerPath: [String]) -> String {
        guard key.hasPrefix(".") else { return key }
        var components = key.split(separator: ".").map(String.init)
        // Build a "named-only" base path by filtering out anonymous numeric segments.
        var namedBasePath = containerPath.filter { Int($0) == nil }
        while components.first == "^" {
            components.removeFirst()
            if !namedBasePath.isEmpty { namedBasePath.removeLast() }
        }
        // The resolved key is used against visitCounts which uses FULL absolute paths
        // (including numeric segments). We need to find the real path by looking up
        // which visitCounts keys start with the named prefix + the target name.
        // For simplicity, try the named-path resolution and also try inserting a "0":
        let namedResult = (namedBasePath + components).joined(separator: ".")
        return namedResult
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
