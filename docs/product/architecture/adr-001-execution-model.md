# ADR-001: Execution Model — Tree-Walker vs Stack Machine

**Status**: Accepted  
**Date**: 2026-06-01  
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)  
**Feature**: native-runtime

---

## Context

The `SwiftInkRuntime` module must execute Ink stories from their compiled `.ink.json` format. The format is a recursive container tree where each node is one of: text, control command, divert, choice point, variable operation, or native function call. Two primary execution models exist for tree-structured instruction sets.

**Business drivers for this decision**:
- Debuggability: the author needs to step through story execution and inspect state at any node, especially during development and test authoring.
- Expandability: new node types will be added as the ink spec is extended (e.g., `listDefs`, external functions, variable pointer values). The model must accommodate additions without requiring architectural rework.
- Team size: single developer. Operational complexity of the execution model must be minimal.
- Timeline: exploratory feature. Correctness and understandability rank above raw performance.

**Constraint from spike**: The spike (`docs/feature/native-runtime/spike/findings.md`) proved that the Ink JSON format can be fully modelled with a recursive classifier. Walking the tree directly from parsed nodes is feasible with zero unknowns across a real fixture.

---

## Decision

Adopt the **tree-walker execution model**.

The `TreeWalker` component recursively visits `ContainerNode` and dispatches on `NodeKind`. Control flow (diverts, choice points) is modelled as pointer updates within `StoryState`. Each step is a discrete, inspectable function call.

---

## Alternatives Considered

### Alternative A: Stack Machine / Bytecode Interpreter

Translate the `ContainerNode` tree into a flat sequence of opcodes during decode. Execute opcodes by pushing/popping an evaluation stack.

**Evaluation against requirements**:
- Performance: higher throughput for tight loops (opcode dispatch is O(1) vs tree traversal).
- Debuggability: substantially worse. Opaque bytecode requires a separate disassembler to inspect execution state. Breakpointing at a logical story node requires mapping bytecode offsets back to source positions.
- Expandability: adding a new node kind requires a new opcode, a new compiler pass, and updates to the dispatch table. Three places to change vs one in tree-walker.
- Complexity: the compilation pass from tree to bytecode adds a component with no user-visible benefit at this scale.

**Rejection rationale**: The performance benefit is irrelevant at the scale of interactive fiction (human-paced, paragraph-by-paragraph). The debuggability and expandability costs are directly contrary to the primary drivers. No requirement justifies the added complexity.

### Alternative B: Continuation-Passing / Trampoline

Model execution as a sequence of continuations, avoiding deep recursion for very long stories.

**Evaluation against requirements**:
- Stack depth: Ink stories are shallow in practice. The recursive container nesting depth in real fixtures is low (spike observed no pathological nesting).
- Complexity: continuation-passing style in Swift is unidiomatic and significantly harder to read and maintain for a single-developer project.
- Debuggability: similar to stack machine — execution state is distributed across closures, not inspectable as a single `StoryState` struct.

**Rejection rationale**: The problem it solves (stack overflow in deep recursion) does not occur in practice for Ink JSON. The complexity cost is unjustified.

---

## Consequences

**Positive**:
- Every execution step is a named Swift function call. Test failure output identifies the exact node type being processed.
- Adding a new `NodeKind` case requires adding one `switch` branch in `TreeWalker`. No compilation pass, no opcode table.
- `StoryState` is a plain struct that can be printed, diffed, and snapshotted at any point. This directly enables the save/restore feature (Decision 5).
- The oracle testing pattern (compare tree-walker output against inkjs step by step) is natural: both run against the same input and the walker can pause after every step.

**Negative**:
- For stories with extremely long chains of text nodes (thousands of lines), recursive traversal will be slower than opcode dispatch. This is an accepted trade-off: interactive fiction is not a tight loop.
- Deep mutual recursion in pathological Ink programs (e.g., deeply nested tunnels) could exhaust the Swift call stack. Mitigation: the spike showed real fixtures are shallow; a depth limit guard in `TreeWalker` can be added as a safety measure without architectural change.
