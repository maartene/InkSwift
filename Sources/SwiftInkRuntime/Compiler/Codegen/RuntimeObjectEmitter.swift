// Codegen stage of the native compile pipeline (DDD-10): lower the typed AST
// (a flat `[InkStatement]` stream from `InkParser`) into the runtime tree (a
// root `ContainerNode`) the existing runtime plays directly — no JSON
// round-trip (D3). It builds `Decoder/` node types only and never references
// the `Engine/` layer (boundary rule R5).
//
// S1 lowering (knots, stitches, diverts, glue, `-> END`):
//   - The pre-knot body becomes the root container's ordered children, ending
//     in `.controlCommand("done")`.
//   - Each knot becomes a `namedContent` entry on the root keyed by its name.
//     The knot's own body lines are the knot container's children; each stitch
//     becomes a `namedContent` entry NESTED under its knot container, keyed by
//     the stitch name with `.name` set.
//   - Diverts emit `.divert(target:, isConditional:false, isVariable:false)`
//     carrying the unresolved path string verbatim — the runtime resolves
//     absolute (`intro`), qualified (`investigation.arrival`), and relative
//     (`.^.arrival`) forms by named/relative navigation (no tree-shape parity
//     with inklecate's anonymous-0 nesting required).
//   - Glue emits `.controlCommand("<>")`; a text line immediately followed by
//     glue keeps its trailing space (the parser trims it) so the runtime joins
//     the glued segments exactly as the oracle does.
//   - `-> END` lowers to `.controlCommand("end")` (the runtime's end control).

import Foundation

enum RuntimeObjectEmitter {

    /// Build the runnable root container from the parsed statement stream.
    static func emitRoot(statements: [InkStatement]) -> ContainerNode {
        let (rootBody, knots) = partitionTopLevel(statements)

        var rootChildren = lowerBody(rootBody)
        rootChildren.append(.controlCommand("done"))

        var namedContent: [String: ContainerNode] = [:]
        for knot in knots {
            namedContent[knot.name] = emitKnot(knot)
        }
        return ContainerNode(children: rootChildren, namedContent: namedContent, flags: 0, name: nil)
    }

    // MARK: - Expression lowering

    /// Lower an inline-printed expression `{ <expr> }` into the runtime nodes
    /// that evaluate it and emit the result, matching the committed oracle
    /// token order for `{2 + 3 * 4}`: `ev, 2, 3, 4, *, +, out, /ev`. The
    /// expression body is lowered to POSTFIX (RPN) so it drives the runtime's
    /// evaluation stack directly; `out` pops the result and prints it.
    static func lowerInlineExpression(_ expression: InkExpression) -> [NodeKind] {
        var nodes: [NodeKind] = [.controlCommand("ev")]
        nodes.append(contentsOf: lowerExpression(expression))
        nodes.append(.controlCommand("out"))
        nodes.append(.controlCommand("/ev"))
        return nodes
    }

    /// Lower an expression to POSTFIX runtime nodes: operands depth-first, then
    /// the operator. `a OP b` becomes `<lower a> <lower b> .nativeFunction(OP)`.
    /// Int/float literals lower to `.intValue`/`.floatValue`; the
    /// variable-reference placeholder lowers to `.variableReference` (wired up
    /// fully in 02-02).
    static func lowerExpression(_ expression: InkExpression) -> [NodeKind] {
        switch expression {
        case .intLiteral(let value):
            return [.intValue(value)]
        case .floatLiteral(let value):
            return [.floatValue(value)]
        case .variableReference(let name):
            return [.variableReference(name: name)]
        case .binary(let oper, let left, let right):
            var nodes = lowerExpression(left)
            nodes.append(contentsOf: lowerExpression(right))
            nodes.append(.nativeFunction(oper))
            return nodes
        }
    }

    // MARK: - Grouping

    /// A knot and its body, plus the stitches declared inside it.
    private struct KnotGroup {
        let name: String
        let body: [InkStatement]
        let stitches: [StitchGroup]
    }

    /// A stitch and its body.
    private struct StitchGroup {
        let name: String
        let body: [InkStatement]
    }

    /// Split the flat stream into the pre-knot root body and the ordered knots.
    private static func partitionTopLevel(
        _ statements: [InkStatement]
    ) -> (rootBody: [InkStatement], knots: [KnotGroup]) {
        var rootBody: [InkStatement] = []
        var knots: [KnotGroup] = []
        var index = 0
        while index < statements.count {
            guard case .knot(let name) = statements[index].kind else {
                rootBody.append(statements[index])
                index += 1
                continue
            }
            let (knot, nextIndex) = readKnot(named: name, after: index, in: statements)
            knots.append(knot)
            index = nextIndex
        }
        return (rootBody, knots)
    }

    /// Read one knot starting just after its header at `headerIndex`, consuming
    /// statements up to (but not including) the next knot header.
    private static func readKnot(
        named name: String,
        after headerIndex: Int,
        in statements: [InkStatement]
    ) -> (knot: KnotGroup, nextIndex: Int) {
        var body: [InkStatement] = []
        var stitches: [StitchGroup] = []
        var index = headerIndex + 1
        var pendingStitch: (name: String, body: [InkStatement])?

        while index < statements.count {
            let kind = statements[index].kind
            if case .knot = kind {
                break
            }
            if case .stitch(let stitchName) = kind {
                appendStitch(pendingStitch, into: &stitches)
                pendingStitch = (stitchName, [])
                index += 1
                continue
            }
            if pendingStitch != nil {
                pendingStitch?.body.append(statements[index])
            } else {
                body.append(statements[index])
            }
            index += 1
        }
        appendStitch(pendingStitch, into: &stitches)
        return (KnotGroup(name: name, body: body, stitches: stitches), index)
    }

    private static func appendStitch(
        _ pending: (name: String, body: [InkStatement])?,
        into stitches: inout [StitchGroup]
    ) {
        guard let pending else { return }
        stitches.append(StitchGroup(name: pending.name, body: pending.body))
    }

    // MARK: - Lowering

    private static func emitKnot(_ knot: KnotGroup) -> ContainerNode {
        var named: [String: ContainerNode] = [:]
        for stitch in knot.stitches {
            named[stitch.name] = ContainerNode(
                children: lowerBody(stitch.body),
                namedContent: [:],
                flags: 0,
                name: stitch.name
            )
        }
        return ContainerNode(
            children: lowerBody(knot.body),
            namedContent: named,
            flags: 0,
            name: knot.name
        )
    }

    /// Lower an ordered statement body into runtime nodes. A text line directly
    /// followed by glue keeps its trailing space so the runtime joins segments
    /// exactly as the oracle does (the parser trims the space off the text).
    private static func lowerBody(_ statements: [InkStatement]) -> [NodeKind] {
        var children: [NodeKind] = []
        for (offset, statement) in statements.enumerated() {
            let nextIsGlue = isGlue(statements, at: offset + 1)
            children.append(contentsOf: lower(statement, gluedToNext: nextIsGlue))
        }
        return children
    }

    private static func lower(_ statement: InkStatement, gluedToNext: Bool) -> [NodeKind] {
        switch statement.kind {
        case .text(let value):
            let text = gluedToNext ? value + " " : value
            return [.text(text), .newline]
        case .divert(let target):
            return [.divert(target: target, isConditional: false, isVariable: false)]
        case .end:
            return [.controlCommand("end")]
        case .glue:
            return [.controlCommand("<>")]
        case .knot, .stitch:
            // Headers are consumed during grouping and never reach lowering.
            return []
        }
    }

    private static func isGlue(_ statements: [InkStatement], at index: Int) -> Bool {
        guard index < statements.count else { return false }
        if case .glue = statements[index].kind {
            return true
        }
        return false
    }
}
