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

    /// The runtime named-container key the engine runs at startup to initialise
    /// global variables (matches the inklecate oracle's `"global decl"` key).
    private static let globalDeclKey = "global decl"

    /// Build the runnable root container from the parsed statement stream.
    static func emitRoot(statements: [InkStatement]) throws -> ContainerNode {
        let constants = collectConstants(statements)
        let (rootBody, knots) = partitionTopLevel(statements)

        var namedContent: [String: ContainerNode] = [:]
        let rootChildren = try lowerRootBody(rootBody, constants: constants, named: &namedContent)

        for knot in knots {
            namedContent[knot.name] = emitKnot(knot, constants: constants)
        }
        if let globalDecl = emitGlobalDecl(statements, constants: constants) {
            namedContent[globalDeclKey] = globalDecl
        }
        return ContainerNode(children: rootChildren, namedContent: namedContent, flags: 0, name: nil)
    }

    /// Lower the pre-knot root body. A body containing a weave routes through the
    /// `WeaveEmitter` (which appends its own `done` and contributes the `c-N`/
    /// `g-N` outcome/gather containers into `named`); a plain body lowers flatly
    /// and terminates in `done`.
    private static func lowerRootBody(
        _ rootBody: [InkStatement],
        constants: [String: InkExpression],
        named: inout [String: ContainerNode]
    ) throws -> [NodeKind] {
        guard WeaveEmitter.containsWeave(rootBody) else {
            return lowerBody(rootBody, constants: constants, keyPrefix: [], named: &named)
                + [.controlCommand("done")]
        }
        // Weave choice/gather bodies in the supported set do not themselves open
        // block conditionals (S3 scope), so they lower with a private collector.
        let weave = try WeaveEmitter.lower(rootBody) { statements in
            var weaveNamed: [String: ContainerNode] = [:]
            return lowerBody(statements, constants: constants, keyPrefix: [], named: &weaveNamed)
        }
        for (key, container) in weave.named {
            named[key] = container
        }
        return weave.children
    }

    // MARK: - Declarations

    /// Build the CONST inlining table (D6 / DDD-9): CONSTs never become runtime
    /// variables; references to them are substituted with their literal value at
    /// codegen.
    private static func collectConstants(_ statements: [InkStatement]) -> [String: InkExpression] {
        var constants: [String: InkExpression] = [:]
        for statement in statements {
            guard case .constant(let name, let value) = statement.kind else { continue }
            constants[name] = value
        }
        return constants
    }

    /// Emit the `global decl` container running every `VAR` declaration once at
    /// startup: a single `ev`…`/ev` block of `<value> {VAR=:name}` assignments,
    /// terminated by `end`. Returns `nil` when there are no globals.
    private static func emitGlobalDecl(
        _ statements: [InkStatement],
        constants: [String: InkExpression]
    ) -> ContainerNode? {
        let globals = statements.compactMap { statement -> (name: String, value: InkExpression)? in
            guard case .globalVariable(let name, let value) = statement.kind else { return nil }
            return (name, value)
        }
        guard globals.isEmpty == false else { return nil }

        var children: [NodeKind] = [.controlCommand("ev")]
        for global in globals {
            children.append(contentsOf: lowerValue(global.value, constants: constants))
            children.append(.variableAssignment(name: global.name, isGlobal: true))
        }
        children.append(.controlCommand("/ev"))
        children.append(.controlCommand("end"))
        return ContainerNode(children: children, namedContent: [:], flags: 0, name: nil)
    }

    // MARK: - Expression lowering

    /// Lower an inline-printed expression `{ <expr> }` into the runtime nodes
    /// that evaluate it and emit the result, matching the committed oracle
    /// token order for `{2 + 3 * 4}`: `ev, 2, 3, 4, *, +, out, /ev`. The
    /// expression body is lowered to POSTFIX (RPN) so it drives the runtime's
    /// evaluation stack directly; `out` pops the result and prints it.
    static func lowerInlineExpression(_ expression: InkExpression) -> [NodeKind] {
        lowerInlineExpression(expression, constants: [:])
    }

    private static func lowerInlineExpression(
        _ expression: InkExpression,
        constants: [String: InkExpression]
    ) -> [NodeKind] {
        var nodes: [NodeKind] = [.controlCommand("ev")]
        nodes.append(contentsOf: lowerExpression(expression, constants: constants))
        nodes.append(.controlCommand("out"))
        nodes.append(.controlCommand("/ev"))
        return nodes
    }

    /// Lower an expression to POSTFIX runtime nodes, inlining any CONST
    /// reference to its literal value (D6 / DDD-9). `a OP b` becomes
    /// `<lower a> <lower b> .nativeFunction(OP)`; literals push onto the eval
    /// stack; non-CONST identifiers lower to `.variableReference`; string
    /// literals lower to a `str`/`^text`/`/str` group that pushes the string.
    private static func lowerExpression(
        _ expression: InkExpression,
        constants: [String: InkExpression]
    ) -> [NodeKind] {
        switch expression {
        case .intLiteral(let value):
            return [.intValue(value)]
        case .boolLiteral(let value):
            return [.boolValue(value)]
        case .floatLiteral(let value):
            return [.floatValue(value)]
        case .stringLiteral(let value):
            return [.controlCommand("str"), .text(value), .controlCommand("/str")]
        case .variableReference(let name):
            if let inlined = constants[name] {
                return lowerExpression(inlined, constants: constants)
            }
            return [.variableReference(name: name)]
        case .binary(let oper, let left, let right):
            var nodes = lowerExpression(left, constants: constants)
            nodes.append(contentsOf: lowerExpression(right, constants: constants))
            nodes.append(.nativeFunction(oper))
            return nodes
        }
    }

    /// Lower a declaration/assignment RHS value (no `out`): the value is left on
    /// the eval stack for a following `{VAR=}`/`{temp=}` to consume.
    private static func lowerValue(
        _ expression: InkExpression,
        constants: [String: InkExpression]
    ) -> [NodeKind] {
        lowerExpression(expression, constants: constants)
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

    private static func emitKnot(_ knot: KnotGroup, constants: [String: InkExpression]) -> ContainerNode {
        var named: [String: ContainerNode] = [:]
        for stitch in knot.stitches {
            var stitchNamed: [String: ContainerNode] = [:]
            let children = lowerBody(
                stitch.body, constants: constants,
                keyPrefix: [knot.name, stitch.name], named: &stitchNamed
            )
            named[stitch.name] = ContainerNode(
                children: children, namedContent: stitchNamed, flags: 0, name: stitch.name
            )
        }
        var knotNamed = named
        let children = lowerBody(
            knot.body, constants: constants, keyPrefix: [knot.name], named: &knotNamed
        )
        return ContainerNode(children: children, namedContent: knotNamed, flags: 0, name: knot.name)
    }

    /// Lower an ordered statement body into runtime nodes. A text line directly
    /// followed by glue keeps its trailing space so the runtime joins segments
    /// exactly as the oracle does (the parser trims the space off the text). When
    /// a block/switch conditional is reached, its branch and continuation
    /// containers are registered under `keyPrefix` in `named` and the remaining
    /// statements fold into the continuation (the conditional always diverts).
    private static func lowerBody(
        _ statements: [InkStatement],
        constants: [String: InkExpression],
        keyPrefix: [String],
        named: inout [String: ContainerNode]
    ) -> [NodeKind] {
        var children: [NodeKind] = []
        for (offset, statement) in statements.enumerated() {
            let rest = Array(statements[(offset + 1)...])
            if case .conditionalBlock(let subject, let isSwitch, let branches) = statement.kind {
                children.append(contentsOf: ConditionalEmitter.lower(
                    subject: subject, isSwitch: isSwitch, branches: branches,
                    continuation: rest, keyPrefix: keyPrefix, named: &named,
                    lowerBranch: branchLowerer(constants: constants),
                    lowerExpression: { lowerExpression($0, constants: constants) }
                ))
                return children
            }
            if case .content(let segments) = statement.kind,
               let inlineIndex = segments.firstIndex(where: isConditionalSegment) {
                children.append(contentsOf: lowerInlineConditionalLine(
                    segments, conditionalIndex: inlineIndex, restOfBody: rest,
                    constants: constants, keyPrefix: keyPrefix, named: &named
                ))
                return children
            }
            let nextIsGlue = isGlue(statements, at: offset + 1)
            children.append(contentsOf: lower(
                statement, gluedToNext: nextIsGlue, constants: constants
            ))
        }
        return children
    }

    /// A reusable branch-lowering closure for the conditional emitter: lowers an
    /// arm body under its own qualified key-prefix into a private named collector.
    private static func branchLowerer(
        constants: [String: InkExpression]
    ) -> (_ body: [InkStatement], _ prefix: [String], _ named: inout [String: ContainerNode]) -> [NodeKind] {
        return { body, prefix, collected in
            lowerBody(body, constants: constants, keyPrefix: prefix, named: &collected)
        }
    }

    private static func isConditionalSegment(_ segment: ContentSegment) -> Bool {
        if case .conditional = segment { return true }
        return false
    }

    /// Lower a content line carrying an inline conditional `{ c: a|b }`. Segments
    /// before it render first; the conditional selects branch text via the
    /// runtime conditional-divert pathway; the branches rejoin a continuation
    /// container holding the line's trailing segments (newline + any tag) and the
    /// rest of the enclosing body.
    private static func lowerInlineConditionalLine(
        _ segments: [ContentSegment],
        conditionalIndex: Int,
        restOfBody: [InkStatement],
        constants: [String: InkExpression],
        keyPrefix: [String],
        named: inout [String: ContainerNode]
    ) -> [NodeKind] {
        guard case .conditional(let condition, let ifTrue, let ifFalse) = segments[conditionalIndex] else {
            return []
        }
        let prefixSegments = Array(segments[..<conditionalIndex])
        let suffixSegments = Array(segments[(conditionalIndex + 1)...])
        var children = lowerContentSegments(prefixSegments, constants: constants)

        let continuation = inlineContinuationStatements(suffixSegments, restOfBody: restOfBody)

        children.append(contentsOf: ConditionalEmitter.lowerInline(
            condition: condition, trueText: ifTrue, falseText: ifFalse,
            continuation: continuation, keyPrefix: keyPrefix, named: &named,
            lowerBranch: branchLowerer(constants: constants),
            lowerExpression: { lowerExpression($0, constants: constants) }
        ))
        return children
    }

    /// Build the continuation statements for an inline conditional: the line's
    /// trailing segments become a content statement (so the line's newline and any
    /// tag are emitted after the chosen branch), followed by the rest of the body.
    private static func inlineContinuationStatements(
        _ suffixSegments: [ContentSegment],
        restOfBody: [InkStatement]
    ) -> [InkStatement] {
        var continuation: [InkStatement] = []
        continuation.append(InkStatement(kind: .content(suffixSegments), position: zeroPosition))
        continuation.append(contentsOf: restOfBody)
        return continuation
    }

    private static let zeroPosition = SourcePosition(line: 0, column: 0)

    private static func lower(
        _ statement: InkStatement,
        gluedToNext: Bool,
        constants: [String: InkExpression]
    ) -> [NodeKind] {
        switch statement.kind {
        case .text(let value):
            let text = gluedToNext ? value + " " : value
            return [.text(text), .newline]
        case .content(let segments):
            return lowerContent(segments, constants: constants)
        case .temporaryVariable(let name, let value):
            return lowerAssignment(name: name, value: value, isGlobal: false, constants: constants)
        case .assignment(let name, let value):
            return lowerAssignment(name: name, value: value, isGlobal: true, constants: constants)
        case .divert(let target):
            return [.divert(target: target, isConditional: false, isVariable: false)]
        case .end:
            return [.controlCommand("end")]
        case .glue:
            return [.controlCommand("<>")]
        case .globalVariable, .constant:
            // Declarations are hoisted into the `global decl` container (VAR) or
            // inlined at codegen (CONST); they emit nothing in the body stream.
            return []
        case .knot, .stitch:
            // Headers are consumed during grouping and never reach lowering.
            return []
        case .choice, .gather:
            // Weave lines are resolved by the WeaveEmitter before reaching the
            // flat statement lowerer; they never lower individually here.
            return []
        case .conditionalBlock:
            // Block/switch conditionals are resolved by lowerBody (which threads
            // the named-content collector + key-prefix); they never lower here.
            return []
        }
    }

    /// Lower a content line: literal segments emit text, expression segments emit
    /// an `ev`/`out`/`/ev` print group, tag segments emit a tag node. A trailing
    /// newline ends the rendered line. (Inline conditionals are routed through
    /// `lowerInlineConditionalLine` before reaching here.)
    private static func lowerContent(
        _ segments: [ContentSegment],
        constants: [String: InkExpression]
    ) -> [NodeKind] {
        var nodes = lowerContentSegments(segments, constants: constants)
        nodes.append(.newline)
        return nodes
    }

    /// Lower content segments WITHOUT the trailing newline: literal/expression/tag
    /// segments only. Shared by `lowerContent` and the inline-conditional path.
    private static func lowerContentSegments(
        _ segments: [ContentSegment],
        constants: [String: InkExpression]
    ) -> [NodeKind] {
        var nodes: [NodeKind] = []
        for segment in segments {
            switch segment {
            case .literal(let text):
                nodes.append(.text(text))
            case .expression(let expression):
                nodes.append(contentsOf: lowerInlineExpression(expression, constants: constants))
            case .tag(let tag):
                nodes.append(contentsOf: [.tagOpen, .text(tag), .tagClose])
            case .conditional:
                // Inline conditionals are handled by lowerInlineConditionalLine.
                break
            }
        }
        return nodes
    }

    /// Lower `~ [temp] name = expr` / `~ name = expr`: evaluate the RHS then
    /// assign it. `isGlobal` selects `{VAR=}` (reassignment of a global) vs
    /// `{temp=}` (local declaration).
    private static func lowerAssignment(
        name: String,
        value: InkExpression,
        isGlobal: Bool,
        constants: [String: InkExpression]
    ) -> [NodeKind] {
        var nodes: [NodeKind] = [.controlCommand("ev")]
        nodes.append(contentsOf: lowerExpression(value, constants: constants))
        nodes.append(.controlCommand("/ev"))
        nodes.append(.variableAssignment(name: name, isGlobal: isGlobal))
        return nodes
    }

    private static func isGlue(_ statements: [InkStatement], at index: Int) -> Bool {
        guard index < statements.count else { return false }
        if case .glue = statements[index].kind {
            return true
        }
        return false
    }
}
