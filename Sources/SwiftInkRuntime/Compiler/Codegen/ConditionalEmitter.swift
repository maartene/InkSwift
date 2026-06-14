// WHY-NEW-FILE: Sources/SwiftInkRuntime/Compiler/Codegen/ConditionalEmitter.swift
//   CLOSEST-EXISTING: Sources/SwiftInkRuntime/Compiler/Codegen/RuntimeObjectEmitter.swift
//   EXTENSION-COST: RuntimeObjectEmitter already lowers knot/stitch/divert/expr/
//     weave-spliced bodies; conditional resolution (per-arm guard evaluation, the
//     branch/continuation container namespace, switch `subject == label` lowering)
//     is a distinct multi-step algorithm that would push RuntimeObjectEmitter past
//     the Calisthenics small-entity rule.
//   PARALLEL-RATIONALE: ConditionalEmitter owns its own `cond{N}-b{i}`/`-else`/
//     `-end` container namespace and is invoked by lowerBody ONLY when a body
//     contains a block/switch or inline conditional, returning dispatch nodes plus
//     registering branch containers into the caller's named collector — the same
//     boundary WeaveEmitter already established for the c-N/g-N weave namespace.
//
// CONDITIONAL LOWERING (DELIVER S4 / row 22-24): lower inline `{c:a|b}`, block
// `{c: ... - else: ...}`, and switch `{v: -1: ... -2: ...}` onto the runtime's
// EXISTING isConditional-divert pathway (`{"->":path,"c":true}` — pop a bool from
// the eval stack, divert only when true). Codegen has full freedom over tree
// shape; only PLAY/line equivalence matters (D5 Level-1 correctness), so this
// emitter uses absolute-qualified NAMED branch containers (no fragile numeric
// relative `.^.` arithmetic) the engine navigates from root.
//
// SHAPE: per conditional, the body emits guard-evaluation + conditional diverts to
// per-arm branch containers; a trailing unconditional divert routes the no-match
// case to the `else` arm (when present) or straight to the continuation. Every
// branch container ends by diverting to the shared `-end` continuation container,
// which holds the statements that followed the conditional — so both arms rejoin
// exactly as the inklecate oracle's `b → check.5` rejoin does.

import Foundation

enum ConditionalEmitter {

    /// Lowers an arm body under its qualified key-prefix into a private named
    /// collector, returning the body nodes (the collector captures nested
    /// conditionals declared inside the arm).
    typealias BranchLowerer = (
        _ body: [InkStatement],
        _ keyPrefix: [String],
        _ named: inout [String: ContainerNode]
    ) -> [NodeKind]

    /// Lowers a guard/subject/label expression to postfix runtime nodes.
    typealias ExpressionLowerer = (InkExpression) -> [NodeKind]

    /// Lower a block/switch conditional. `subject` is the switch value (compared
    /// `== match` per arm) when `isSwitch`; otherwise each arm's `match` is its own
    /// boolean guard. `continuation` is the statements that follow the conditional
    /// in the enclosing body — they become the shared rejoin container. Branch and
    /// continuation containers are registered in `named` under `keyPrefix`.
    static func lower(
        subject: InkExpression,
        isSwitch: Bool,
        branches: [ConditionalBranch],
        continuation: [InkStatement],
        keyPrefix: [String],
        named: inout [String: ContainerNode],
        lowerBranch: BranchLowerer,
        lowerExpression: ExpressionLowerer
    ) -> [NodeKind] {
        let ordinal = nextOrdinal(in: named)
        let endKey = key(ordinal, "end")
        let endPath = path(keyPrefix, endKey)

        var dispatch: [NodeKind] = []
        var elseKey: String?

        for (index, branch) in branches.enumerated() {
            guard let match = branch.match else {
                elseKey = registerArm(
                    branch, ordinal: ordinal, index: index, label: "else",
                    endPath: endPath, keyPrefix: keyPrefix, named: &named, lowerBranch: lowerBranch
                )
                continue
            }
            let branchKey = registerArm(
                branch, ordinal: ordinal, index: index, label: "b\(index)",
                endPath: endPath, keyPrefix: keyPrefix, named: &named, lowerBranch: lowerBranch
            )
            dispatch.append(contentsOf: guardNodes(
                subject: subject, match: match, isSwitch: isSwitch, lowerExpression: lowerExpression
            ))
            dispatch.append(conditionalDivert(to: path(keyPrefix, branchKey)))
        }

        dispatch.append(unconditionalDivert(to: elseKey.map { path(keyPrefix, $0) } ?? endPath))
        named[endKey] = ContainerNode(
            children: continuationChildren(continuation, keyPrefix: keyPrefix + [endKey], lowerBranch: lowerBranch, named: &named, endKey: endKey),
            namedContent: [:], flags: 0, name: endKey
        )
        return dispatch
    }

    /// Lower an inline conditional `{ c: a|b }`: `a`/`b` are plain branch texts
    /// (no trailing newline — the continuation carries the line's newline). The
    /// branches rejoin the `-end` continuation exactly like the block form.
    static func lowerInline(
        condition: InkExpression,
        trueText: String,
        falseText: String,
        continuation: [InkStatement],
        keyPrefix: [String],
        named: inout [String: ContainerNode],
        lowerBranch: BranchLowerer,
        lowerExpression: ExpressionLowerer
    ) -> [NodeKind] {
        let ordinal = nextOrdinal(in: named)
        let endKey = key(ordinal, "end")
        let endPath = path(keyPrefix, endKey)
        let trueKey = key(ordinal, "b0")
        let falseKey = key(ordinal, "b1")

        named[trueKey] = inlineBranchContainer(trueText, key: trueKey, endPath: endPath)
        named[falseKey] = inlineBranchContainer(falseText, key: falseKey, endPath: endPath)

        var dispatch: [NodeKind] = [.controlCommand("ev")]
        dispatch.append(contentsOf: lowerExpression(condition))
        dispatch.append(.controlCommand("/ev"))
        dispatch.append(conditionalDivert(to: path(keyPrefix, trueKey)))
        dispatch.append(unconditionalDivert(to: path(keyPrefix, falseKey)))

        var endNamed: [String: ContainerNode] = [:]
        let endChildren = lowerBranch(continuation, keyPrefix + [endKey], &endNamed)
        named[endKey] = ContainerNode(children: endChildren, namedContent: endNamed, flags: 0, name: endKey)
        return dispatch
    }

    // MARK: - Arm registration

    /// Register one arm container (`b{i}` or `else`) holding the arm body plus a
    /// trailing divert to the shared continuation (unless the body already diverts
    /// away). Returns the arm's key.
    private static func registerArm(
        _ branch: ConditionalBranch,
        ordinal: Int,
        index: Int,
        label: String,
        endPath: [String],
        keyPrefix: [String],
        named: inout [String: ContainerNode],
        lowerBranch: BranchLowerer
    ) -> String {
        let armKey = key(ordinal, label)
        var armNamed: [String: ContainerNode] = [:]
        var children = lowerBranch(branch.body, keyPrefix + [armKey], &armNamed)
        if endsWithControlFlow(branch.body) == false {
            children.append(unconditionalDivert(to: endPath))
        }
        named[armKey] = ContainerNode(children: children, namedContent: armNamed, flags: 0, name: armKey)
        return armKey
    }

    /// Children of the continuation container: the post-conditional statements,
    /// lowered under the continuation's own key-prefix into the shared collector.
    private static func continuationChildren(
        _ continuation: [InkStatement],
        keyPrefix: [String],
        lowerBranch: BranchLowerer,
        named: inout [String: ContainerNode],
        endKey: String
    ) -> [NodeKind] {
        var endNamed: [String: ContainerNode] = [:]
        let children = lowerBranch(continuation, keyPrefix, &endNamed)
        for (innerKey, container) in endNamed {
            named[innerKey] = container
        }
        return children
    }

    private static func inlineBranchContainer(_ text: String, key: String, endPath: [String]) -> ContainerNode {
        var children: [NodeKind] = []
        if text.isEmpty == false {
            children.append(.text(text))
        }
        children.append(unconditionalDivert(to: endPath))
        return ContainerNode(children: children, namedContent: [:], flags: 0, name: key)
    }

    // MARK: - Guard / divert nodes

    /// Guard-evaluation nodes pushing a bool onto the eval stack. A switch arm
    /// pushes `subject == match`; a guarded arm pushes the arm's boolean `match`.
    private static func guardNodes(
        subject: InkExpression,
        match: InkExpression,
        isSwitch: Bool,
        lowerExpression: ExpressionLowerer
    ) -> [NodeKind] {
        var nodes: [NodeKind] = [.controlCommand("ev")]
        if isSwitch {
            nodes.append(contentsOf: lowerExpression(subject))
            nodes.append(contentsOf: lowerExpression(match))
            nodes.append(.nativeFunction("=="))
        } else {
            nodes.append(contentsOf: lowerExpression(match))
        }
        nodes.append(.controlCommand("/ev"))
        return nodes
    }

    private static func conditionalDivert(to path: [String]) -> NodeKind {
        .divert(target: path.joined(separator: "."), isConditional: true, isVariable: false)
    }

    private static func unconditionalDivert(to path: [String]) -> NodeKind {
        .divert(target: path.joined(separator: "."), isConditional: false, isVariable: false)
    }

    // MARK: - Helpers

    private static func endsWithControlFlow(_ statements: [InkStatement]) -> Bool {
        switch statements.last?.kind {
        case .divert, .end:
            return true
        default:
            return false
        }
    }

    private static func key(_ ordinal: Int, _ label: String) -> String {
        "cond\(ordinal)-\(label)"
    }

    private static func path(_ prefix: [String], _ key: String) -> [String] {
        prefix + [key]
    }

    /// The next conditional ordinal for this container: the count of conditionals
    /// already registered in `named` (each contributes one `cond{N}-end` key). This
    /// is deterministic and free of shared mutable state, so sibling conditionals
    /// in one body still get distinct, stable container keys across compiles.
    private static func nextOrdinal(in named: [String: ContainerNode]) -> Int {
        named.keys.filter { $0.hasPrefix("cond") && $0.hasSuffix("-end") }.count
    }
}
