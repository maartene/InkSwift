// WHY-NEW-FILE: Sources/SwiftInkRuntime/Compiler/Codegen/VariableTextEmitter.swift
//   CLOSEST-EXISTING: Sources/SwiftInkRuntime/Compiler/Codegen/ConditionalEmitter.swift
//   EXTENSION-COST: ConditionalEmitter owns the `cond{N}-*` arm/end namespace and a
//     guard-evaluation + conditional-divert algorithm keyed on a boolean condition;
//     variable-text dispatch is a DIFFERENT algorithm — a visit-indexed clamp/wrap
//     over N stages with its own `seq{N}-*` namespace and a `#f:5` visited dispatch
//     container — so folding it in would push ConditionalEmitter past the
//     Calisthenics small-entity rule and entangle two unrelated dispatch shapes.
//   PARALLEL-RATIONALE: VariableTextEmitter owns a DISTINCT `seq{N}-s{i}`/`-end`
//     container namespace (so a mixed body cannot collide with conditional's
//     `cond{N}-*` — DESIGN OQ-3, true by construction) and is invoked by lowerBody
//     ONLY when a content line carries a `.variableText` segment, mirroring the
//     boundary ConditionalEmitter already established for inline conditionals.
//
// VARIABLE-TEXT LOWERING (DELIVER slice-01 / matrix rows 25-27, ADR-010): lower the
// deterministic alternatives `{a|b|c}` (sequence), `{&a|b}` (cycle), `{!a|b}` (once)
// onto the runtime's EXISTING visit-count + native-arithmetic + conditional-divert
// machinery (zero runtime change — `visit`/`du`/`MIN`/`%`/`nop`/`pop`/`==` + `#f`
// flag all proven by the engine). Shuffle `{~a|b}` never reaches here — it is
// rejected upstream by UnsupportedConstructDetector.
//
// SHAPE (verified vs inklecate): each form lowers to a visited dispatch container
// flagged `#f:5` (Visits | CountStartOnly, so `visit` reports the 0-based own-entry
// read count). The container computes a clamped/wrapped stage index, then dispatches
// to a per-stage container via duplicate-and-compare:
//
//   ev visit BOUND OP /ev               ← clamped/wrapped index (BOUND int, OP native fn)
//   ev du 0 == /ev {"->":"seqN-s0","c":true}   ← du copies the index; == tests; divert when equal
//   …one per stage…
//   nop
//   namedContent:
//     seqN-s0: [ pop, <text0 if non-empty>, -> seqN-end ]   ← EMPTY stage omits the text node
//     …
//     #f = 5
//   seqN-end: [ <continuation: line suffix + rest of enclosing body> ]
//
// Per-form arithmetic:
//   sequence {a|b|c}  OP=MIN BOUND=S-1   clamp at last stage
//   cycle    {&a|b}   OP=%   BOUND=S     wrap modulo stage count
//   once     {!a|b}   OP=MIN BOUND=S     append ONE empty stage, advance then blank

import Foundation

enum VariableTextEmitter {

    /// Lowers a continuation body under its qualified key-prefix into a private
    /// named collector, returning the body nodes (mirrors ConditionalEmitter's
    /// BranchLowerer so the same lowerBody closure drives both emitters).
    typealias ContinuationLowerer = (
        _ body: [InkStatement],
        _ keyPrefix: [String],
        _ named: inout [String: ContainerNode]
    ) -> [NodeKind]

    /// Lower a variable-text alternative. `mode` selects the dispatch arithmetic;
    /// `stages` are the raw `|`-split stage texts. `continuation` is the statements
    /// that follow the alternative in the enclosing body — they become the shared
    /// `-end` rejoin container. The dispatch and stage containers are registered in
    /// `named` under `keyPrefix`; the returned nodes divert the enclosing body into
    /// the visited dispatch container.
    static func lower(
        mode: VariableTextMode,
        stages: [String],
        continuation: [InkStatement],
        keyPrefix: [String],
        named: inout [String: ContainerNode],
        lowerContinuation: ContinuationLowerer
    ) -> [NodeKind] {
        let ordinal = nextOrdinal(in: named)
        let dispatchKey = key(ordinal, "d")
        let endKey = key(ordinal, "end")
        let endPath = path(keyPrefix, endKey)

        let effectiveStages = stagesFor(mode: mode, stages: stages)
        let dispatchPrefix = keyPrefix + [dispatchKey]

        var dispatchChildren = indexNodes(mode: mode, stageCount: effectiveStages.count)
        var stageContainers: [String: ContainerNode] = [:]
        for (index, text) in effectiveStages.enumerated() {
            let stageKey = key(ordinal, "s\(index)")
            dispatchChildren.append(contentsOf: dispatchTest(
                index: index, stagePath: path(dispatchPrefix, stageKey)
            ))
            stageContainers[stageKey] = stageContainer(stageKey, text: text, endPath: endPath)
        }
        dispatchChildren.append(.controlCommand("nop"))

        named[dispatchKey] = ContainerNode(
            children: dispatchChildren, namedContent: stageContainers,
            flags: visitedFlag, name: dispatchKey
        )
        registerContinuation(
            continuation, endKey: endKey, keyPrefix: keyPrefix,
            named: &named, lowerContinuation: lowerContinuation
        )
        return [unconditionalDivert(to: path(keyPrefix, dispatchKey))]
    }

    // MARK: - Stage shaping

    /// The stages the dispatch indexes over: once appends ONE empty stage (advance
    /// through each source stage exactly once, then blank); sequence/cycle index
    /// the source stages verbatim.
    private static func stagesFor(mode: VariableTextMode, stages: [String]) -> [String] {
        switch mode {
        case .once:
            return stages + [""]
        case .sequence, .cycle:
            return stages
        }
    }

    // MARK: - Dispatch nodes

    /// The `ev visit BOUND OP /ev` group computing the clamped/wrapped stage index:
    /// sequence/once clamp via `MIN` against the last index; cycle wraps via `%`
    /// against the stage count.
    private static func indexNodes(mode: VariableTextMode, stageCount: Int) -> [NodeKind] {
        let bound = mode == .cycle ? stageCount : stageCount - 1
        let op = mode == .cycle ? "%" : "MIN"
        return [
            .controlCommand("ev"),
            .controlCommand("visit"),
            .intValue(bound),
            .nativeFunction(op),
            .controlCommand("/ev"),
        ]
    }

    /// The `ev du I == /ev {"->":stage,"c":true}` test for one stage: duplicate the
    /// surviving index, compare against this stage's ordinal, divert when equal.
    private static func dispatchTest(index: Int, stagePath: [String]) -> [NodeKind] {
        [
            .controlCommand("ev"),
            .controlCommand("du"),
            .intValue(index),
            .nativeFunction("=="),
            .controlCommand("/ev"),
            conditionalDivert(to: stagePath),
        ]
    }

    /// One stage container: `pop` discards the surviving index copy, the stage text
    /// renders (an EMPTY stage omits the text node), then divert to the shared end.
    private static func stageContainer(_ stageKey: String, text: String, endPath: [String]) -> ContainerNode {
        var children: [NodeKind] = [.controlCommand("pop")]
        if text.isEmpty == false {
            children.append(.text(text))
        }
        children.append(unconditionalDivert(to: endPath))
        return ContainerNode(children: children, namedContent: [:], flags: 0, name: stageKey)
    }

    /// Register the shared `-end` continuation container: lower the post-alternative
    /// statements under the continuation's own key-prefix, then promote any nested
    /// containers they declared into the parent collector so rejoin targets resolve
    /// from root (mirrors ConditionalEmitter.registerContinuation).
    private static func registerContinuation(
        _ continuation: [InkStatement],
        endKey: String,
        keyPrefix: [String],
        named: inout [String: ContainerNode],
        lowerContinuation: ContinuationLowerer
    ) {
        var endNamed: [String: ContainerNode] = [:]
        let children = lowerContinuation(continuation, keyPrefix + [endKey], &endNamed)
        for (innerKey, container) in endNamed {
            named[innerKey] = container
        }
        named[endKey] = ContainerNode(children: children, namedContent: [:], flags: 0, name: endKey)
    }

    // MARK: - Divert nodes

    private static func conditionalDivert(to path: [String]) -> NodeKind {
        .divert(target: path.joined(separator: "."), isConditional: true, isVariable: false)
    }

    private static func unconditionalDivert(to path: [String]) -> NodeKind {
        .divert(target: path.joined(separator: "."), isConditional: false, isVariable: false)
    }

    // MARK: - Helpers

    /// `#f = 5` = Visits (bit 0) | CountStartOnly (bit 2): the dispatch container
    /// tracks its own visit count so `visit` reports the 0-based entry index.
    private static let visitedFlag = 5

    private static func key(_ ordinal: Int, _ label: String) -> String {
        "seq\(ordinal)-\(label)"
    }

    private static func path(_ prefix: [String], _ key: String) -> [String] {
        prefix + [key]
    }

    /// The next variable-text ordinal for this container: the count of alternatives
    /// already registered in `named` (each contributes one `seq{N}-end` key). This
    /// is deterministic and free of shared mutable state, so sibling alternatives in
    /// one body get distinct, stable container keys across compiles.
    private static func nextOrdinal(in named: [String: ContainerNode]) -> Int {
        named.keys.filter { $0.hasPrefix("seq") && $0.hasSuffix("-end") }.count
    }
}
