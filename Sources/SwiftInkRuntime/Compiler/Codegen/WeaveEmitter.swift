// WHY-NEW-FILE: Sources/SwiftInkRuntime/Compiler/Codegen/WeaveEmitter.swift
//   CLOSEST-EXISTING: Sources/SwiftInkRuntime/Compiler/Codegen/RuntimeObjectEmitter.swift
//   EXTENSION-COST: RuntimeObjectEmitter already handles knot/stitch/divert/glue/
//     expr lowering; weave resolution (level partitioning, c-N/g-N keying,
//     loose-end resolution) is a distinct multi-step algorithm that would push it
//     past the Calisthenics small-entity rule.
//   PARALLEL-RATIONALE: WeaveEmitter has a different lifecycle — invoked by
//     lowerBody ONLY when a body contains choices, returns a (children, named)
//     pair the emitter splices in, and owns the c-N/g-N namespace; isolating it
//     keeps RuntimeObjectEmitter a flat-stream lowerer and quarantines the S3
//     algorithm DELIVER will extend to nested levels.
//
// WALKING SKELETON SCOPE (SPIKE Phase 3 / ADR-008): this resolves ONLY the FLAT
// single-level weave proven by the probe — bracketed once-only choices and one
// trailing gather whose loose end the choice bodies fall into, ending in
// `-> END`. The container-construction template is the probe's validated form:
// per choice `ev,str,^label,/str,/ev, choicePoint(target: c-N, flags: 0x14)` in
// the parent children; a sibling namedContent map of `c-N` outcome containers
// (each diverting to the gather) and the gather container `g-N` (ending in
// `end`). Targets are absolute-qualified from root (`c-0`, `c-1`, `g-0`).
//
// Out-of-scope constructs (nested multi-level weaves, sticky `+`, plain-label
// echo, labeled / multiple gathers, conditional choices) are DELIVER S3 and are
// rejected with a `.scaffold` error rather than silently miscompiled.

import Foundation

enum WeaveEmitter {

    /// Choice flag `0x14` = hasChoiceOnlyContent (0x4) | isOnceOnly (0x10).
    private static let bracketedOnceOnly = ChoiceFlags(rawValue: 0x14)

    /// Does this body contain at least one weave choice (and so must lower
    /// through the weave resolver rather than the flat statement lowerer)?
    static func containsWeave(_ statements: [InkStatement]) -> Bool {
        statements.contains { statement in
            if case .choice = statement.kind { return true }
            return false
        }
    }

    /// Lower a body containing a flat single-level weave into the runtime tree:
    /// the leading prose + per-choice label/choicePoint nodes go into `children`;
    /// the outcome containers `c-N` and the gather `g-N` go into `named`.
    /// `trailing` carries the post-gather statements (e.g. `-> END`) so the
    /// gather container can terminate exactly as the oracle does.
    static func lower(
        _ statements: [InkStatement],
        lowerStatement: ([InkStatement]) -> [NodeKind]
    ) throws -> (children: [NodeKind], named: [String: ContainerNode]) {
        let parts = try split(statements)

        var children = lowerStatement(parts.lead)
        for (offset, choice) in parts.choices.enumerated() {
            children.append(contentsOf: labelNodes(choice.label))
            children.append(.choicePoint(target: "c-\(offset)", flags: bracketedOnceOnly))
        }
        children.append(.controlCommand("done"))

        var named: [String: ContainerNode] = [:]
        for (offset, choice) in parts.choices.enumerated() {
            named["c-\(offset)"] = outcomeContainer(choice, key: "c-\(offset)")
        }
        named["g-0"] = gatherContainer(parts.gather, trailing: parts.trailing, lowerStatement: lowerStatement)
        return (children, named)
    }

    // MARK: - Parsing the weave into its parts

    private struct Choice {
        let label: String
        let body: String
    }

    private struct WeaveParts {
        let lead: [InkStatement]
        let choices: [Choice]
        let gather: InkStatement
        let trailing: [InkStatement]
    }

    /// Split a flat-weave body into: leading prose, the choices, the single
    /// trailing gather, and the post-gather statements. Rejects every construct
    /// beyond the walking-skeleton's flat slice with a `.scaffold` error.
    private static func split(_ statements: [InkStatement]) throws -> WeaveParts {
        var lead: [InkStatement] = []
        var choices: [Choice] = []
        var gather: InkStatement?
        var trailing: [InkStatement] = []

        for statement in statements {
            switch statement.kind {
            case .choice(let level, let isSticky, let choiceOnlyLabel, let body):
                try requireFlatChoice(level: level, isSticky: isSticky, label: choiceOnlyLabel, at: statement.position)
                choices.append(Choice(label: choiceOnlyLabel ?? body, body: body))
            case .gather(let level, let label, let outcome):
                try requireFlatGather(level: level, label: label, existing: gather, at: statement.position)
                gather = InkStatement(kind: .text(outcome), position: statement.position)
            default:
                if gather == nil {
                    lead.append(statement)
                } else {
                    trailing.append(statement)
                }
            }
        }

        guard let resolvedGather = gather else {
            throw scaffold(
                "flat weave without a trailing gather is not yet supported",
                at: statements.first?.position
            )
        }
        return WeaveParts(lead: lead, choices: choices, gather: resolvedGather, trailing: trailing)
    }

    private static func requireFlatChoice(
        level: Int,
        isSticky: Bool,
        label: String?,
        at position: SourcePosition
    ) throws {
        guard level == 1 else {
            throw scaffold("nested multi-level weaves are not yet supported", at: position)
        }
        guard isSticky == false else {
            throw scaffold("sticky choices (+) are not yet supported", at: position)
        }
        guard label != nil else {
            throw scaffold("plain-label (non-bracketed) choices are not yet supported", at: position)
        }
    }

    private static func requireFlatGather(
        level: Int,
        label: String?,
        existing: InkStatement?,
        at position: SourcePosition
    ) throws {
        guard level == 1 else {
            throw scaffold("nested-level gathers are not yet supported", at: position)
        }
        guard label == nil else {
            throw scaffold("labeled gathers are not yet supported", at: position)
        }
        guard existing == nil else {
            throw scaffold("multiple gathers are not yet supported", at: position)
        }
    }

    // MARK: - Container construction (probe-validated template)

    /// `ev str ^label /str /ev` — push the choice label for the engine's
    /// `resolveChoiceText()` strategy #1.
    private static func labelNodes(_ label: String) -> [NodeKind] {
        [.controlCommand("ev"), .controlCommand("str"), .text(label),
         .controlCommand("/str"), .controlCommand("/ev")]
    }

    /// A bracketed choice's outcome container: its body (no label echo) followed
    /// by a divert into the gather `g-0`. A leading space preserves the oracle's
    /// `^ You went left …` rendering after the once-only choice is taken.
    private static func outcomeContainer(_ choice: Choice, key: String) -> ContainerNode {
        ContainerNode(
            children: [.text(" " + choice.body), .newline, divert("g-0")],
            namedContent: [:],
            flags: 0,
            name: key
        )
    }

    /// The gather container `g-0`: its outcome text, then the lowered trailing
    /// statements (`-> END` lowers to `end`).
    private static func gatherContainer(
        _ gather: InkStatement,
        trailing: [InkStatement],
        lowerStatement: ([InkStatement]) -> [NodeKind]
    ) -> ContainerNode {
        var children = lowerStatement([gather])
        children.append(contentsOf: lowerStatement(trailing))
        return ContainerNode(children: children, namedContent: [:], flags: 0, name: "g-0")
    }

    private static func divert(_ target: String) -> NodeKind {
        .divert(target: target, isConditional: false, isVariable: false)
    }

    private static func scaffold(_ message: String, at position: SourcePosition?) -> CompileError {
        CompileError(
            kind: .scaffold,
            message: message,
            line: position?.line ?? 0,
            column: position?.column ?? 0
        )
    }
}
