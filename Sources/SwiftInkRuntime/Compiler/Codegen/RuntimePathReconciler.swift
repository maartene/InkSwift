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
        var containerPaths: Set<String> = []
        collectContainerPaths(root, prefix: [], into: &containerPaths)
        var rewrites: [String: String] = [:]
        for key in danglingReadCountKeys(in: root, existing: containerPaths) {
            if let resolved = reconciledPath(for: key, among: containerPaths) {
                rewrites[key] = resolved
            }
        }
        guard rewrites.isEmpty == false else { return root }
        return rewritingReadCounts(root, rewrites: rewrites)
    }

    /// The dot-joined absolute path of every named container in the tree (the set of
    /// real read-count-addressable targets). Numeric children are never named targets.
    private static func collectContainerPaths(
        _ container: ContainerNode, prefix: [String], into paths: inout Set<String>
    ) {
        for (key, child) in container.namedContent {
            let path = prefix + [key]
            paths.insert(path.joined(separator: "."))
            collectContainerPaths(child, prefix: path, into: &paths)
        }
        for child in container.children {
            if case .container(let nested) = child {
                collectContainerPaths(nested, prefix: prefix, into: &paths)
            }
        }
    }

    /// Every `.readCount` key in the tree that does NOT match an existing container.
    private static func danglingReadCountKeys(
        in container: ContainerNode, existing: Set<String>
    ) -> Set<String> {
        var keys: Set<String> = []
        collectReadCountPaths(container, into: &keys)
        return keys.subtracting(existing)
    }

    /// The unique real container whose path ends with `key`'s final label segment and
    /// shares `key`'s leading knot segment, else `nil` (no match or ambiguous).
    private static func reconciledPath(for key: String, among paths: Set<String>) -> String? {
        let segments = key.split(separator: ".").map(String.init)
        guard let label = segments.last, let knot = segments.first else { return nil }
        let suffix = ".\(label)"
        let candidates = paths.filter { candidate in
            candidate != key
                && candidate.hasSuffix(suffix)
                && candidate.hasPrefix("\(knot).")
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    /// Rebuild the tree replacing each `.readCount(key)` whose key is in `rewrites`
    /// with the reconciled path; all other nodes are preserved verbatim.
    private static func rewritingReadCounts(
        _ container: ContainerNode, rewrites: [String: String]
    ) -> ContainerNode {
        let children = container.children.map { child -> NodeKind in
            switch child {
            case .readCount(let key):
                return .readCount(rewrites[key] ?? key)
            case .container(let nested):
                return .container(rewritingReadCounts(nested, rewrites: rewrites))
            default:
                return child
            }
        }
        var rebuiltNamed: [String: ContainerNode] = [:]
        for (key, child) in container.namedContent {
            rebuiltNamed[key] = rewritingReadCounts(child, rewrites: rewrites)
        }
        return ContainerNode(
            children: children, namedContent: rebuiltNamed, flags: container.flags, name: container.name
        )
    }

    // MARK: - Divert-target path reconciliation

    /// Rewrite every `.divert` whose ABSOLUTE target names no existing container
    /// to the actually-emitted container path, when a unique reconciling target
    /// exists. Mirrors `reconcilingReadCountPaths`: the reconciliation target is a
    /// container whose absolute path ENDS with the dangling target's final label
    /// segment AND shares its leading knot segment; uniqueness within that knot
    /// prevents cross-scope mis-resolution. Only absolute, non-END,
    /// non-function-call, currently-dangling targets are considered — a relative
    /// (`.^.`), END, function (`f():`), or already-resolving target is untouched.
    private static func reconcilingDivertPaths(_ root: ContainerNode) -> ContainerNode {
        var containerPaths: Set<String> = []
        collectContainerPaths(root, prefix: [], into: &containerPaths)
        var rewrites: [String: String] = [:]
        for target in danglingDivertTargets(in: root, existing: containerPaths) {
            if let resolved = reconciledPath(for: target, among: containerPaths) {
                rewrites[target] = resolved
            }
        }
        guard rewrites.isEmpty == false else { return root }
        return rewritingDivertTargets(root, rewrites: rewrites)
    }

    /// Every `.divert` target eligible for reconciliation that does NOT match an
    /// existing container: absolute (no leading `.`), not `END`, not a
    /// function-call (`f():`) target, and currently dangling.
    private static func danglingDivertTargets(
        in container: ContainerNode, existing: Set<String>
    ) -> Set<String> {
        var targets: Set<String> = []
        collectDivertTargets(container, into: &targets)
        return targets
            .filter { isReconcilableDivertTarget($0) }
            .subtracting(existing)
    }

    /// True when a divert target is a candidate for path reconciliation: it must
    /// be absolute (no leading `.` relative form), not the `END` sentinel, and not
    /// a function-call target (which the runtime intercepts by its `f():` prefix).
    private static func isReconcilableDivertTarget(_ target: String) -> Bool {
        target.hasPrefix(".") == false
            && target != "END"
            && target.hasPrefix(RuntimeObjectEmitter.functionCallTargetPrefix) == false
    }

    /// Collect every `.divert` target anywhere in the tree. `.choicePoint` targets
    /// are deliberately excluded — they are already emitted correctly.
    private static func collectDivertTargets(_ container: ContainerNode, into targets: inout Set<String>) {
        for child in container.children {
            if case .divert(let target, _, _) = child { targets.insert(target) }
            if case .container(let nested) = child { collectDivertTargets(nested, into: &targets) }
        }
        for nested in container.namedContent.values {
            collectDivertTargets(nested, into: &targets)
        }
    }

    /// Rebuild the tree replacing each `.divert` whose target is in `rewrites` with
    /// the reconciled target (preserving its `isConditional`/`isVariable` flags);
    /// all other nodes — including `.choicePoint` — are preserved verbatim.
    private static func rewritingDivertTargets(
        _ container: ContainerNode, rewrites: [String: String]
    ) -> ContainerNode {
        let children = container.children.map { child -> NodeKind in
            switch child {
            case .divert(let target, let isConditional, let isVariable):
                return .divert(
                    target: rewrites[target] ?? target,
                    isConditional: isConditional, isVariable: isVariable
                )
            case .container(let nested):
                return .container(rewritingDivertTargets(nested, rewrites: rewrites))
            default:
                return child
            }
        }
        var rebuiltNamed: [String: ContainerNode] = [:]
        for (key, child) in container.namedContent {
            rebuiltNamed[key] = rewritingDivertTargets(child, rewrites: rewrites)
        }
        return ContainerNode(
            children: children, namedContent: rebuiltNamed, flags: container.flags, name: container.name
        )
    }

    // MARK: - CountVisits flagging

    /// Collect the absolute namedContent path (dot-joined) of every `.readCount`
    /// node anywhere in the tree — the exact set of read-count-referenced targets.
    /// Each `.readCount` key is the resolved container path emitted at 02-03.
    private static func referencedReadCountPaths(in container: ContainerNode) -> Set<String> {
        var paths: Set<String> = []
        collectReadCountPaths(container, into: &paths)
        return paths
    }

    private static func collectReadCountPaths(_ container: ContainerNode, into paths: inout Set<String>) {
        for child in container.children {
            if case .readCount(let key) = child { paths.insert(key) }
            if case .container(let nested) = child { collectReadCountPaths(nested, into: &paths) }
        }
        for nested in container.namedContent.values {
            collectReadCountPaths(nested, into: &paths)
        }
    }

    /// Rebuild the tree setting the 0x1 CountVisits flag on every container whose
    /// absolute namedContent path is in `flaggedPaths`. Children numeric-indexed
    /// containers are never named read-count targets, so only namedContent entries
    /// extend the path; the root carries no path of its own.
    private static func flaggingCountVisits(
        _ container: ContainerNode,
        atPaths flaggedPaths: Set<String>,
        prefix: [String] = []
    ) -> ContainerNode {
        var rebuiltNamed: [String: ContainerNode] = [:]
        for (key, child) in container.namedContent {
            rebuiltNamed[key] = flaggingCountVisits(child, atPaths: flaggedPaths, prefix: prefix + [key])
        }
        let path = prefix.joined(separator: ".")
        let flags = flaggedPaths.contains(path) ? container.flags | countVisitsFlag : container.flags
        return ContainerNode(
            children: container.children, namedContent: rebuiltNamed, flags: flags, name: container.name
        )
    }

    /// The runtime's `#f` bit 0 — tracks a flagged container's visits into
    /// `state.visitCounts`, which a `.readCount(absolutePath)` node reads back.
    private static let countVisitsFlag = 0x1
}
