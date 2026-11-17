// WHY-NEW-FILE: Sources/SwiftInkRuntime/Compiler/Codegen/RuntimePathReconciler.swift
//   CLOSEST-EXISTING: Sources/SwiftInkRuntime/Compiler/Codegen/RuntimeObjectEmitter.swift
//   EXTENSION-COST: these passes lived in RuntimeObjectEmitter, pushing it past
//     1,400 lines. They share nothing with AST lowering: each takes the finished
//     runtime tree and returns a rewritten one.
//   PARALLEL-RATIONALE: RuntimePathReconciler is invoked once, by
//     RuntimeObjectEmitter.emitRoot, on the fully built root. It reads and
//     writes `ContainerNode`/`NodeKind` only — no `InkStatement`, no lowering
//     context — so it can be reasoned about (and tested) as a pure tree rewrite.
//
// POST-LOWERING PATH RECONCILIATION: the discovery pre-pass predicts weave-label
// container paths from the weave structure alone, but conditional / variable-text
// continuations can nest a label deeper than predicted. These passes reconcile
// read-count keys and divert targets against the containers actually emitted,
// then set the CountVisits flag on exactly the read-count-referenced containers.

import Foundation

enum RuntimePathReconciler {

    /// Reconcile read-count keys and divert targets against the emitted tree,
    /// then flag every read-count-referenced container for visit counting.
    static func reconcile(_ builtRoot: ContainerNode) -> ContainerNode {
        // Read-count path reconciliation (step 01-06): the discovery pre-pass predicts
        // a label's compiled path from the WEAVE structure alone, but a labelled choice
        // that trails an inline-conditional / variable-text gather lead is physically
        // nested under that line's `cond{N}-end` continuation container(s) — e.g. the
        // `(disagree)` choice after `… {lift_up_cup:he|Harris} begins{forceful<=0:,sternly}.`
        // compiles to `start.waited.cond2-end.cond0-end.disagree`, not the flat
        // `start.waited.disagree` discovery recorded. A `.readCount("start.waited.disagree")`
        // guard (`{not disagree}`) then reads a non-existent container → always 0 → the
        // `[Smile]` choice is never suppressed. Reconcile each `.readCount` key that
        // names no real container against the actually-emitted container whose path
        // ends with that label inside the same knot, when exactly one such container
        // exists (uniqueness avoids cross-scope mis-resolution).
        // Divert-target path reconciliation (Cass softlock fix): a bare named
        // weave-point divert (`-> cass_ask_what_he_needs_information_gathering`)
        // is emitted by `qualifiedDivertTarget` using the discovery pre-pass's
        // PREDICTED FLAT path. When the enclosing knot opens with block
        // conditionals, the whole weave is physically nested under that line's
        // `cond{N}-end` continuation container(s), so the real container path
        // (`cass.cond0-end.cond0-end.cass_opening.…`) does not match the flat
        // predicted path — the runtime's absolute-from-root navigation dead-ends
        // and the choice stack exhausts (softlock). Reconcile each `.divert`
        // whose absolute target names no real container against the unique
        // actually-emitted container whose path ends with that label inside the
        // same knot, exactly as the read-count reconciler does. choicePoint
        // targets are already correct and are left untouched.
        let root = reconcilingDivertPaths(reconcilingReadCountPaths(builtRoot))
        // CountVisits flagging (ADR-011 EXTEND, generalised WL-D4): set the runtime's
        // 0x1 CountVisits flag on EXACTLY the read-count-referenced targets — labelled
        // weave containers AND referenced knots/stitches. The set of referenced
        // absolute paths is the SET of `.readCount` keys already emitted into the tree
        // (02-03 resolved each referenced target to its container path; the keys are
        // the single source of path truth, never re-derived). Flagging only those
        // matches inklecate (VariableReference.cs:101 flags a container only when a
        // reference resolves to it; countAllVisits is OFF) — no over-flagging.
        return flaggingCountVisits(root, atPaths: referencedReadCountPaths(in: root))
    }

    // MARK: - Read-count path reconciliation

    /// Rewrite every `.readCount(key)` whose key names no existing container to the
    /// actually-emitted container path, when a unique reconciling target exists. The
    /// reconciliation target is a container whose absolute path ENDS with the same
    /// final label segment as the dangling key AND shares its leading knot segment;
    /// uniqueness within that knot prevents cross-scope mis-resolution. A key that
    /// already resolves (or whose label is ambiguous) is left untouched.
    private static func reconcilingReadCountPaths(_ root: ContainerNode) -> ContainerNode {
        let rewrites = reconciliations(of: referencedReadCountPaths(in: root), in: root)
        guard rewrites.isEmpty == false else { return root }
        return mappingNodes(in: root) { node in
            guard case .readCount(.absolute(let key)) = node, let rewrite = rewrites[key] else { return node }
            return .readCount(.absolute(rewrite))
        }
    }

    // MARK: - Divert-target path reconciliation

    /// Rewrite every `.divert` whose ABSOLUTE target names no existing container
    /// to the actually-emitted container path, when a unique reconciling target
    /// exists. Mirrors `reconcilingReadCountPaths`: the reconciliation target is a
    /// container whose absolute path ENDS with the dangling target's final label
    /// segment AND shares its leading knot segment; uniqueness within that knot
    /// prevents cross-scope mis-resolution. Only absolute, non-END,
    /// currently-dangling path targets are considered — a relative (`.^.`), END,
    /// variable, or already-resolving target is untouched, and a `.functionCall`
    /// is not a `.divert` at all, so its target is never reconciled.
    /// `.choicePoint` targets are deliberately excluded — they are already emitted
    /// correctly — and preserved verbatim.
    private static func reconcilingDivertPaths(_ root: ContainerNode) -> ContainerNode {
        let candidates = collecting(in: root, reconcilableDivertPath(of:))
        let rewrites = reconciliations(of: candidates, in: root)
        guard rewrites.isEmpty == false else { return root }
        return mappingNodes(in: root) { node in
            guard case .divert(_, let isConditional) = node,
                  let path = reconcilableDivertPath(of: node),
                  let rewrite = rewrites[path] else { return node }
            return .divert(target: .path(.absolute(rewrite)), isConditional: isConditional)
        }
    }

    /// The target of a divert that is a candidate for path reconciliation: an
    /// absolute path target other than the `END` sentinel, else nil.
    private static func reconcilableDivertPath(of node: NodeKind) -> ContainerPath? {
        guard case .divert(.path(.absolute(let path)), _) = node,
              path.description != "END" else { return nil }
        return path
    }

    // MARK: - Shared reconciliation

    /// For each referenced path that names no existing container, the unique real
    /// container it reconciles to (see `reconciledPath`). References that already
    /// resolve, or that reconcile to nothing or to several containers, are omitted.
    private static func reconciliations(
        of references: Set<ContainerPath>, in root: ContainerNode
    ) -> [ContainerPath: ContainerPath] {
        var containerPaths: Set<ContainerPath> = []
        collectContainerPaths(root, prefix: [], into: &containerPaths)
        var rewrites: [ContainerPath: ContainerPath] = [:]
        for reference in references.subtracting(containerPaths) {
            rewrites[reference] = reconciledPath(for: reference, among: containerPaths)
        }
        return rewrites
    }

    /// The absolute path of every named container in the tree (the set of real
    /// read-count-addressable targets). Numeric children are never named targets.
    private static func collectContainerPaths(
        _ container: ContainerNode, prefix: [PathComponent], into paths: inout Set<ContainerPath>
    ) {
        for (key, child) in container.namedContent {
            let path = prefix + [PathComponent(parsing: key)]
            paths.insert(ContainerPath(components: path))
            collectContainerPaths(child, prefix: path, into: &paths)
        }
        for child in container.children {
            if case .container(let nested) = child {
                collectContainerPaths(nested, prefix: prefix, into: &paths)
            }
        }
    }

    /// The unique real container whose path ends with `key`'s final label component
    /// and shares `key`'s leading knot component, else `nil` (no match or ambiguous).
    /// A candidate needs at least two components: the knot and, below it, the label.
    private static func reconciledPath(for key: ContainerPath, among paths: Set<ContainerPath>) -> ContainerPath? {
        guard let label = key.components.last, let knot = key.components.first else { return nil }
        let candidates = paths.filter { candidate in
            candidate != key
                && candidate.components.count >= 2
                && candidate.components.last == label
                && candidate.components.first == knot
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    // MARK: - Tree traversal

    /// Every value `extract` yields for a node anywhere in the tree, in children
    /// and named content alike.
    private static func collecting<Value: Hashable>(
        in container: ContainerNode,
        _ extract: (NodeKind) -> Value?
    ) -> Set<Value> {
        var values: Set<Value> = []
        for child in container.children {
            if let value = extract(child) { values.insert(value) }
            if case .container(let nested) = child { values.formUnion(collecting(in: nested, extract)) }
        }
        for nested in container.namedContent.values {
            values.formUnion(collecting(in: nested, extract))
        }
        return values
    }

    /// Rebuild the tree with `transform` applied to every non-container node, in
    /// children and named content alike; containers and flags are preserved.
    private static func mappingNodes(
        in container: ContainerNode,
        _ transform: (NodeKind) -> NodeKind
    ) -> ContainerNode {
        let children = container.children.map { child -> NodeKind in
            if case .container(let nested) = child {
                return .container(mappingNodes(in: nested, transform))
            }
            return transform(child)
        }
        var rebuiltNamed: [String: ContainerNode] = [:]
        for (key, child) in container.namedContent {
            rebuiltNamed[key] = mappingNodes(in: child, transform)
        }
        return ContainerNode(
            children: children, namedContent: rebuiltNamed, flags: container.flags, name: container.name
        )
    }

    // MARK: - CountVisits flagging

    /// Collect the absolute namedContent path of every `.readCount` node anywhere in
    /// the tree — the exact set of read-count-referenced targets. The compiler emits
    /// every key absolute (the resolved container path); a relative key could only
    /// come from elsewhere and names no namedContent path, so it is not collected.
    private static func referencedReadCountPaths(in container: ContainerNode) -> Set<ContainerPath> {
        collecting(in: container) { node -> ContainerPath? in
            guard case .readCount(.absolute(let key)) = node else { return nil }
            return key
        }
    }

    /// Rebuild the tree setting the 0x1 CountVisits flag on every container whose
    /// absolute namedContent path is in `flaggedPaths`. Children numeric-indexed
    /// containers are never named read-count targets, so only namedContent entries
    /// extend the path; the root carries no path of its own.
    private static func flaggingCountVisits(
        _ container: ContainerNode,
        atPaths flaggedPaths: Set<ContainerPath>,
        prefix: [PathComponent] = []
    ) -> ContainerNode {
        var rebuiltNamed: [String: ContainerNode] = [:]
        for (key, child) in container.namedContent {
            rebuiltNamed[key] = flaggingCountVisits(
                child, atPaths: flaggedPaths, prefix: prefix + [PathComponent(parsing: key)]
            )
        }
        let path = ContainerPath(components: prefix)
        let flags = flaggedPaths.contains(path) ? container.flags | countVisitsFlag : container.flags
        return ContainerNode(
            children: container.children, namedContent: rebuiltNamed, flags: flags, name: container.name
        )
    }

    /// The runtime's `#f` bit 0 — tracks a flagged container's visits into
    /// `state.visitCounts`, which a `.readCount(absolutePath)` node reads back.
    private static let countVisitsFlag = 0x1
}
