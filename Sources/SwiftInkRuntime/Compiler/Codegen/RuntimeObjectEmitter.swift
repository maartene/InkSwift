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
        let functions = collectFunctionSignatures(statements)
        let context = LoweringContext(constants: constants, functions: functions)
        let (rootBody, knots, functionDefinitions) = partitionTopLevel(statements)

        var namedContent: [String: ContainerNode] = [:]
        let rootChildren = try lowerRootBody(rootBody, context: context, named: &namedContent)

        for knot in knots {
            namedContent[knot.name] = emitKnot(knot, context: context)
        }
        for function in functionDefinitions {
            namedContent[function.name] = emitFunction(function, context: context)
        }
        if let globalDecl = emitGlobalDecl(statements, context: context) {
            namedContent[globalDeclKey] = globalDecl
        }
        return ContainerNode(children: rootChildren, namedContent: namedContent, flags: 0, name: nil)
    }

    /// Codegen-wide lowering inputs threaded through the lowerers: the CONST
    /// inlining table and the function-signature table (so a `ref` argument can
    /// be lowered to a `variablePointer` at the call site).
    struct LoweringContext {
        let constants: [String: InkExpression]
        let functions: [String: [FunctionParameter]]
        /// Names that are function-local in the current scope (parameters plus
        /// `~ temp` declarations inside a function body). An assignment to a local
        /// name lowers to `temp=` so the runtime consults the call frame — the
        /// write-through path that makes a `ref` parameter mutate the caller's
        /// variable. Empty at knot/root scope (all assignments are global there).
        var localNames: Set<String> = []

        func bindingLocals(_ names: Set<String>) -> LoweringContext {
            LoweringContext(constants: constants, functions: functions, localNames: names)
        }
    }

    /// Collect the parameter list of every function definition, keyed by name, so
    /// call sites can tell which arguments bind to `ref` parameters.
    private static func collectFunctionSignatures(
        _ statements: [InkStatement]
    ) -> [String: [FunctionParameter]] {
        var functions: [String: [FunctionParameter]] = [:]
        for statement in statements {
            guard case .functionDefinition(let name, let parameters, _) = statement.kind else { continue }
            functions[name] = parameters
        }
        return functions
    }

    /// Lower the pre-knot root body. A body containing a weave routes through the
    /// `WeaveEmitter` (which appends its own `done` and contributes the `c-N`/
    /// `g-N` outcome/gather containers into `named`); a plain body lowers flatly
    /// and terminates in `done`.
    private static func lowerRootBody(
        _ rootBody: [InkStatement],
        context: LoweringContext,
        named: inout [String: ContainerNode]
    ) throws -> [NodeKind] {
        guard WeaveEmitter.containsWeave(rootBody) else {
            return lowerBody(rootBody, context: context, keyPrefix: [], named: &named)
                + [.controlCommand("done")]
        }
        // Weave choice/gather bodies in the supported set do not themselves open
        // block conditionals (S3 scope), so they lower with a private collector.
        let weave = try WeaveEmitter.lower(rootBody) { statements in
            var weaveNamed: [String: ContainerNode] = [:]
            return lowerBody(statements, context: context, keyPrefix: [], named: &weaveNamed)
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
        context: LoweringContext
    ) -> ContainerNode? {
        let globals = statements.compactMap { statement -> (name: String, value: InkExpression)? in
            guard case .globalVariable(let name, let value) = statement.kind else { return nil }
            return (name, value)
        }
        guard globals.isEmpty == false else { return nil }

        var assignments: [NodeKind] = []
        for global in globals {
            assignments.append(contentsOf: lowerValue(global.value, context: context))
            assignments.append(.variableAssignment(name: global.name, isGlobal: true))
        }
        let children = evalGroup(assignments) + [.controlCommand("end")]
        return ContainerNode(children: children, namedContent: [:], flags: 0, name: nil)
    }

    // MARK: - Expression lowering

    /// Lower an inline-printed expression `{ <expr> }` into the runtime nodes
    /// that evaluate it and emit the result, matching the committed oracle
    /// token order for `{2 + 3 * 4}`: `ev, 2, 3, 4, *, +, out, /ev`. The
    /// expression body is lowered to POSTFIX (RPN) so it drives the runtime's
    /// evaluation stack directly; `out` pops the result and prints it.
    static func lowerInlineExpression(_ expression: InkExpression) -> [NodeKind] {
        lowerInlineExpression(expression, context: emptyContext)
    }

    /// An empty lowering context (no CONSTs, no functions) for callers that lower
    /// a standalone expression with no surrounding declaration/function tables.
    private static let emptyContext = LoweringContext(constants: [:], functions: [:])

    private static func lowerInlineExpression(
        _ expression: InkExpression,
        context: LoweringContext
    ) -> [NodeKind] {
        evalGroup(lowerExpression(expression, context: context) + [.controlCommand("out")])
    }

    /// Wrap eval-stack nodes in the runtime's `ev` … `/ev` evaluation block. The
    /// shared shape behind inline-print, return, assignment, and discarded-call
    /// lowering: each supplies the body that runs between the markers.
    private static func evalGroup(_ body: [NodeKind]) -> [NodeKind] {
        [.controlCommand("ev")] + body + [.controlCommand("/ev")]
    }

    /// Lower an expression to POSTFIX runtime nodes, inlining any CONST
    /// reference to its literal value (D6 / DDD-9). `a OP b` becomes
    /// `<lower a> <lower b> .nativeFunction(OP)`; literals push onto the eval
    /// stack; non-CONST identifiers lower to `.variableReference`; string
    /// literals lower to a `str`/`^text`/`/str` group that pushes the string; a
    /// function call lowers its arguments onto the eval stack then emits the
    /// `f():`-tagged divert that calls the function and leaves its result there.
    private static func lowerExpression(
        _ expression: InkExpression,
        context: LoweringContext
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
            if let inlined = context.constants[name] {
                return lowerExpression(inlined, context: context)
            }
            return [.variableReference(name: name)]
        case .binary(let oper, let left, let right):
            var nodes = lowerExpression(left, context: context)
            nodes.append(contentsOf: lowerExpression(right, context: context))
            nodes.append(.nativeFunction(oper))
            return nodes
        case .functionCall(let name, let arguments):
            return lowerFunctionCall(name: name, arguments: arguments, context: context)
        }
    }

    /// Lower a function call `f(args)`: push each argument onto the eval stack —
    /// an argument bound to a `ref` parameter becomes a `variablePointer` so the
    /// callee mutates the caller's variable — then emit the `f():`-tagged divert
    /// the runtime intercepts to push a return address and jump into the function.
    private static func lowerFunctionCall(
        name: String,
        arguments: [InkExpression],
        context: LoweringContext
    ) -> [NodeKind] {
        let parameters = context.functions[name] ?? []
        var nodes: [NodeKind] = []
        for (offset, argument) in arguments.enumerated() {
            let isReference = offset < parameters.count && parameters[offset].isReference
            if isReference, case .variableReference(let variableName) = argument {
                nodes.append(.variablePointer(name: variableName, contextIndex: globalContextIndex))
                continue
            }
            nodes.append(contentsOf: lowerExpression(argument, context: context))
        }
        nodes.append(.divert(target: functionCallTargetPrefix + name, isConditional: false, isVariable: false))
        return nodes
    }

    /// The runtime intercepts a divert whose target carries this prefix as a
    /// function call (push a return address before jumping). Matches the decoder's
    /// lowering of an inklecate `{"f()": path}` divert.
    private static let functionCallTargetPrefix = "f():"

    /// Reference arguments use `ci == -1` to denote global scope (brief tier3); a
    /// non-negative index would point into a call frame's temp scope.
    private static let globalContextIndex = -1

    /// Lower a declaration/assignment RHS value (no `out`): the value is left on
    /// the eval stack for a following `{VAR=}`/`{temp=}` to consume.
    private static func lowerValue(
        _ expression: InkExpression,
        context: LoweringContext
    ) -> [NodeKind] {
        lowerExpression(expression, context: context)
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

    /// A function definition and the body lines that follow its header.
    private struct FunctionGroup {
        let name: String
        let parameters: [FunctionParameter]
        let body: [InkStatement]
    }

    /// Split the flat stream into the pre-knot root body, the ordered knots, and
    /// the ordered function definitions. Knot and function headers both terminate
    /// the preceding group; a function definition consumes its body lines like a
    /// knot but is lowered with its own parameter/return convention.
    private static func partitionTopLevel(
        _ statements: [InkStatement]
    ) -> (rootBody: [InkStatement], knots: [KnotGroup], functions: [FunctionGroup]) {
        var rootBody: [InkStatement] = []
        var knots: [KnotGroup] = []
        var functions: [FunctionGroup] = []
        var index = 0
        while index < statements.count {
            if case .functionDefinition(let name, let parameters, _) = statements[index].kind {
                let (body, nextIndex) = readDefinitionBody(after: index, in: statements)
                functions.append(FunctionGroup(name: name, parameters: parameters, body: body))
                index = nextIndex
                continue
            }
            guard case .knot(let name) = statements[index].kind else {
                rootBody.append(statements[index])
                index += 1
                continue
            }
            let (knot, nextIndex) = readKnot(named: name, after: index, in: statements)
            knots.append(knot)
            index = nextIndex
        }
        return (rootBody, knots, functions)
    }

    /// Read one knot starting just after its header at `headerIndex`, consuming
    /// statements up to (but not including) the next knot/function header.
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
            if isDefinitionHeader(kind) {
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

    /// Read a function body just after its header at `headerIndex`, consuming
    /// statements up to (but not including) the next knot/function header.
    private static func readDefinitionBody(
        after headerIndex: Int,
        in statements: [InkStatement]
    ) -> (body: [InkStatement], nextIndex: Int) {
        var body: [InkStatement] = []
        var index = headerIndex + 1
        while index < statements.count {
            if isDefinitionHeader(statements[index].kind) {
                break
            }
            body.append(statements[index])
            index += 1
        }
        return (body, index)
    }

    /// True when a statement kind opens a top-level definition (knot or function),
    /// terminating the preceding knot/function body.
    private static func isDefinitionHeader(_ kind: InkStatementKind) -> Bool {
        switch kind {
        case .knot, .functionDefinition:
            return true
        default:
            return false
        }
    }

    private static func appendStitch(
        _ pending: (name: String, body: [InkStatement])?,
        into stitches: inout [StitchGroup]
    ) {
        guard let pending else { return }
        stitches.append(StitchGroup(name: pending.name, body: pending.body))
    }

    // MARK: - Lowering

    private static func emitKnot(_ knot: KnotGroup, context: LoweringContext) -> ContainerNode {
        var named: [String: ContainerNode] = [:]
        for stitch in knot.stitches {
            var stitchNamed: [String: ContainerNode] = [:]
            let children = lowerBody(
                stitch.body, context: context,
                keyPrefix: [knot.name, stitch.name], named: &stitchNamed
            )
            named[stitch.name] = ContainerNode(
                children: children, namedContent: stitchNamed, flags: 0, name: stitch.name
            )
        }
        var knotNamed = named
        let children = lowerBody(
            knot.body, context: context, keyPrefix: [knot.name], named: &knotNamed
        )
        return ContainerNode(children: children, namedContent: knotNamed, flags: 0, name: knot.name)
    }

    /// Emit a function container: bind the call's pushed arguments to per-frame
    /// temps (the runtime pops the eval stack last-parameter-first, so the temp
    /// bindings are emitted in REVERSE parameter order, matching the oracle), then
    /// lower the body. A body whose last statement is not an explicit `~ return`
    /// relies on the runtime's implicit void return at container exhaustion.
    private static func emitFunction(_ function: FunctionGroup, context: LoweringContext) -> ContainerNode {
        var named: [String: ContainerNode] = [:]
        var children: [NodeKind] = []
        for parameter in function.parameters.reversed() {
            children.append(.variableAssignment(name: parameter.name, isGlobal: false))
        }
        let functionContext = context.bindingLocals(localNames(of: function))
        children.append(contentsOf: lowerBody(
            function.body, context: functionContext, keyPrefix: [function.name], named: &named
        ))
        return ContainerNode(children: children, namedContent: named, flags: 0, name: function.name)
    }

    /// The function-local names: its parameters plus any `~ temp` declarations in
    /// the body. Assignments to these names lower to `temp=` so the runtime writes
    /// through the call frame (the ref-param mutation path).
    private static func localNames(of function: FunctionGroup) -> Set<String> {
        var names = Set(function.parameters.map(\.name))
        for statement in function.body {
            if case .temporaryVariable(let name, _) = statement.kind {
                names.insert(name)
            }
        }
        return names
    }

    /// Lower an ordered statement body into runtime nodes. A text line directly
    /// followed by glue keeps its trailing space so the runtime joins segments
    /// exactly as the oracle does (the parser trims the space off the text). When
    /// a block/switch conditional is reached, its branch and continuation
    /// containers are registered under `keyPrefix` in `named` and the remaining
    /// statements fold into the continuation (the conditional always diverts).
    private static func lowerBody(
        _ statements: [InkStatement],
        context: LoweringContext,
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
                    lowerBranch: branchLowerer(context: context),
                    lowerExpression: { lowerExpression($0, context: context) }
                ))
                return children
            }
            if case .content(let segments) = statement.kind,
               let inlineIndex = segments.firstIndex(where: isConditionalSegment) {
                children.append(contentsOf: lowerInlineConditionalLine(
                    segments, conditionalIndex: inlineIndex, restOfBody: rest,
                    context: context, keyPrefix: keyPrefix, named: &named
                ))
                return children
            }
            if case .content(let segments) = statement.kind,
               let variableTextIndex = segments.firstIndex(where: isVariableTextSegment) {
                children.append(contentsOf: lowerVariableTextLine(
                    segments, variableTextIndex: variableTextIndex, restOfBody: rest,
                    context: context, keyPrefix: keyPrefix, named: &named
                ))
                return children
            }
            let nextIsGlue = isGlue(statements, at: offset + 1)
            children.append(contentsOf: lower(
                statement, gluedToNext: nextIsGlue, context: context
            ))
        }
        return children
    }

    /// A reusable branch-lowering closure for the conditional emitter: lowers an
    /// arm body under its own qualified key-prefix into a private named collector.
    private static func branchLowerer(
        context: LoweringContext
    ) -> (_ body: [InkStatement], _ prefix: [String], _ named: inout [String: ContainerNode]) -> [NodeKind] {
        return { body, prefix, collected in
            lowerBody(body, context: context, keyPrefix: prefix, named: &collected)
        }
    }

    private static func isConditionalSegment(_ segment: ContentSegment) -> Bool {
        if case .conditional = segment { return true }
        return false
    }

    private static func isVariableTextSegment(_ segment: ContentSegment) -> Bool {
        if case .variableText = segment { return true }
        return false
    }

    /// Lower a content line carrying a variable-text alternative `{a|b}` / `{&a|b}`
    /// / `{!a|b}`. Segments before it render first; the alternative dispatches to a
    /// visited stage container via VariableTextEmitter; the stages rejoin a
    /// continuation container holding the line's trailing segments (newline + any
    /// tag) and the rest of the enclosing body (mirrors lowerInlineConditionalLine).
    private static func lowerVariableTextLine(
        _ segments: [ContentSegment],
        variableTextIndex: Int,
        restOfBody: [InkStatement],
        context: LoweringContext,
        keyPrefix: [String],
        named: inout [String: ContainerNode]
    ) -> [NodeKind] {
        guard case .variableText(let mode, let stages) = segments[variableTextIndex] else {
            return []
        }
        let prefixSegments = Array(segments[..<variableTextIndex])
        let suffixSegments = Array(segments[(variableTextIndex + 1)...])
        var children = lowerContentSegments(prefixSegments, context: context)

        let continuation = inlineContinuationStatements(suffixSegments, restOfBody: restOfBody)

        children.append(contentsOf: VariableTextEmitter.lower(
            mode: mode, stages: stages, continuation: continuation,
            keyPrefix: keyPrefix, named: &named,
            lowerContinuation: continuationLowerer(context: context)
        ))
        return children
    }

    /// A continuation lowerer for the variable-text emitter: when the rejoin body
    /// opens a weave (choices that follow the alternative on the same line/knot),
    /// route it through the WeaveEmitter so the choices become real choicePoints +
    /// `c-N`/`g-N` outcome containers (promoted into the caller's collector so they
    /// resolve from the enclosing scope); otherwise lower it flatly.
    private static func continuationLowerer(
        context: LoweringContext
    ) -> (_ body: [InkStatement], _ prefix: [String], _ named: inout [String: ContainerNode]) -> [NodeKind] {
        return { body, prefix, collected in
            guard WeaveEmitter.containsWeave(body),
                  let weave = try? WeaveEmitter.lower(body, lowerStatement: { statements in
                      var weaveNamed: [String: ContainerNode] = [:]
                      return lowerBody(statements, context: context, keyPrefix: prefix, named: &weaveNamed)
                  }) else {
                return lowerBody(body, context: context, keyPrefix: prefix, named: &collected)
            }
            for (key, container) in weave.named {
                collected[key] = container
            }
            return weave.children
        }
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
        context: LoweringContext,
        keyPrefix: [String],
        named: inout [String: ContainerNode]
    ) -> [NodeKind] {
        guard case .conditional(let condition, let ifTrue, let ifFalse) = segments[conditionalIndex] else {
            return []
        }
        let prefixSegments = Array(segments[..<conditionalIndex])
        let suffixSegments = Array(segments[(conditionalIndex + 1)...])
        var children = lowerContentSegments(prefixSegments, context: context)

        let continuation = inlineContinuationStatements(suffixSegments, restOfBody: restOfBody)

        children.append(contentsOf: ConditionalEmitter.lowerInline(
            condition: condition, trueText: ifTrue, falseText: ifFalse,
            continuation: continuation, keyPrefix: keyPrefix, named: &named,
            lowerBranch: branchLowerer(context: context),
            lowerExpression: { lowerExpression($0, context: context) }
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
        context: LoweringContext
    ) -> [NodeKind] {
        switch statement.kind {
        case .text(let value):
            let text = gluedToNext ? value + " " : value
            return [.text(text), .newline]
        case .content(let segments):
            return lowerContent(segments, context: context)
        case .temporaryVariable(let name, let value):
            return lowerAssignment(name: name, value: value, isGlobal: false, context: context)
        case .assignment(let name, let value):
            // An assignment to a function-local name (parameter or body temp)
            // lowers to `temp=` so the runtime writes through the call frame — the
            // path a `ref` parameter needs to mutate the caller's variable. Any
            // other name is a global reassignment (`VAR=`).
            let isGlobal = context.localNames.contains(name) == false
            return lowerAssignment(name: name, value: value, isGlobal: isGlobal, context: context)
        case .divert(let target):
            return [.divert(target: target, isConditional: false, isVariable: false)]
        case .tunnelDivert(let target):
            return [.tunnelDivert(target: target)]
        case .tunnelReturn:
            // The runtime pops the tunnel return address on `->->`; the leading
            // `ev void /ev` matches the oracle (a void result for the call site).
            return [.controlCommand("ev"), .voidValue, .controlCommand("/ev"), .controlCommand("->->")]
        case .functionCallStatement(let call):
            return lowerFunctionCallStatement(call, context: context)
        case .returnStatement(let value):
            return lowerReturn(value, context: context)
        case .end:
            return [.controlCommand("end")]
        case .glue:
            return [.controlCommand("<>")]
        case .globalVariable, .constant:
            // Declarations are hoisted into the `global decl` container (VAR) or
            // inlined at codegen (CONST); they emit nothing in the body stream.
            return []
        case .knot, .stitch, .functionDefinition:
            // Headers/definitions are consumed during grouping and never reach
            // the per-statement lowerer.
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

    /// Lower a standalone function-call statement `~ f(args)`: evaluate the call
    /// inside an `ev` block and `pop` its result (the value is discarded), exactly
    /// as the oracle encodes a side-effecting call whose return is unused.
    private static func lowerFunctionCallStatement(
        _ call: InkExpression,
        context: LoweringContext
    ) -> [NodeKind] {
        evalGroup(lowerExpression(call, context: context) + [.controlCommand("pop")])
    }

    /// Lower a function return `~ return [expr]`: evaluate the optional value onto
    /// the eval stack, then emit `~ret` (the runtime pops the function return
    /// address and jumps back to the caller, leaving the value for its `out`).
    private static func lowerReturn(
        _ value: InkExpression?,
        context: LoweringContext
    ) -> [NodeKind] {
        let valueNodes = value.map { lowerExpression($0, context: context) } ?? []
        return evalGroup(valueNodes) + [.controlCommand("~ret")]
    }

    /// Lower a content line: literal segments emit text, expression segments emit
    /// an `ev`/`out`/`/ev` print group, tag segments emit a tag node. A trailing
    /// newline ends the rendered line. (Inline conditionals are routed through
    /// `lowerInlineConditionalLine` before reaching here.)
    private static func lowerContent(
        _ segments: [ContentSegment],
        context: LoweringContext
    ) -> [NodeKind] {
        var nodes = lowerContentSegments(segments, context: context)
        nodes.append(.newline)
        return nodes
    }

    /// Lower content segments WITHOUT the trailing newline: literal/expression/tag
    /// segments only. Shared by `lowerContent` and the inline-conditional path.
    private static func lowerContentSegments(
        _ segments: [ContentSegment],
        context: LoweringContext
    ) -> [NodeKind] {
        var nodes: [NodeKind] = []
        for segment in segments {
            switch segment {
            case .literal(let text):
                nodes.append(.text(text))
            case .expression(let expression):
                nodes.append(contentsOf: lowerInlineExpression(expression, context: context))
            case .tag(let tag):
                nodes.append(contentsOf: [.tagOpen, .text(tag), .tagClose])
            case .conditional:
                // Inline conditionals are handled by lowerInlineConditionalLine.
                break
            case .variableText:
                // Variable-text alternatives are handled by lowerVariableTextLine.
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
        context: LoweringContext
    ) -> [NodeKind] {
        evalGroup(lowerExpression(value, context: context))
            + [.variableAssignment(name: name, isGlobal: isGlobal)]
    }

    private static func isGlue(_ statements: [InkStatement], at index: Int) -> Bool {
        guard index < statements.count else { return false }
        if case .glue = statements[index].kind {
            return true
        }
        return false
    }
}
