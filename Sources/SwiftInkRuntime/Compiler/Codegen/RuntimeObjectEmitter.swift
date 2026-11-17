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
//   - Diverts emit `.divert(target: .path(…), isConditional: false)` carrying
//     the unresolved path, parsed but not resolved — the runtime resolves
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
        let outline = StoryOutline(statements)
        let context = LoweringContext(statements: statements, outline: outline)

        var namedContent: [String: ContainerNode] = [:]
        let rootChildren = try lowerRootBody(outline.rootBody, context: context, named: &namedContent)

        for stitch in outline.rootStitches {
            namedContent[stitch.name] = try emitStitch(stitch, keyPrefix: [stitch.name], context: context)
        }
        for knot in outline.knots {
            namedContent[knot.name] = try emitKnot(knot, context: context)
        }
        for function in outline.functions {
            namedContent[function.name] = emitFunction(function, context: context)
        }
        if let globalDecl = emitGlobalDecl(statements, context: context) {
            namedContent[globalDeclKey] = globalDecl
        }
        let builtRoot = ContainerNode(children: rootChildren, namedContent: namedContent, flags: 0, name: nil)
        return RuntimePathReconciler.reconcile(builtRoot)
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
        try lowerBodyRoutingWeave(rootBody, context: context, keyPrefix: [], named: &named)
    }

    /// Lower a body, routing through the `WeaveEmitter` when it contains choices
    /// (the weave resolver emits the per-choice choicePoints, contributes the
    /// `c-N`/`g-N` outcome/gather containers under `keyPrefix` into `named`, lowers
    /// each `{guard}` via `lowerExpression`, and appends its own `done`); otherwise
    /// lowers flatly and terminates in `done`. Shared by the root body and every
    /// knot/stitch/function body so weaves nested inside knots compile identically.
    private static func lowerBodyRoutingWeave(
        _ body: [InkStatement],
        context: LoweringContext,
        keyPrefix: [String],
        named: inout [String: ContainerNode],
        terminateFlatBodyWithDone: Bool = true
    ) throws -> [NodeKind] {
        // Route through the weave resolver ONLY when the body LEADS with weave
        // content (a choice/gather before any variable-text or block conditional).
        // When a variable-text / conditional line comes first, `lowerBody` folds the
        // trailing choices into that line's continuation (the established S3 path) —
        // routing the whole body through the resolver would instead emit those
        // choicePoints unreachable after the variable-text divert (loop never
        // advances). Bodies with no leading weave keep the flat `lowerBody` path.
        guard leadsWithWeave(body) else {
            let flat = lowerBody(body, context: context, keyPrefix: keyPrefix, named: &named)
            return terminateFlatBodyWithDone ? flat + [.controlCommand("done")] : flat
        }
        // A weave lead / choice / gather body can itself emit named containers
        // (variable-text `seq*-d`/`seq*-end`, inline-conditional `cond*-b*` arms).
        // The weave resolver invokes `lowerStatement` per body with a fresh local
        // collector, so those containers must be promoted here or the diverts that
        // target them (e.g. `divert(seq0-d)`) would not resolve. Accumulate them in
        // a reference collector the closure shares, then merge into `named`.
        let bodyNamed = NamedContentCollector()
        let weave = try WeaveEmitter.lower(
            body,
            keyPrefix: keyPrefix,
            lowerStatement: { statements, _ in
                // Seed the per-body collector with the SHARED accumulator so the
                // anonymous `cond{N}`/`seq{N}` ordinal counter (`nextOrdinal(in:)`)
                // keeps counting across sibling bodies instead of resetting to 0 —
                // otherwise two sibling choice bodies' conditionals both key `cond0-*`
                // at the promoted top-level scope and clobber each other's
                // continuation (the `-> pushes_cup` loss, step 01-03). Containers
                // stay promoted FLAT at the enclosing scope (the established design);
                // only their ordinal is made body-unique. Diverts use the same flat
                // `keyPrefix`, so target and storage agree. This path lowers under the
                // FLAT `keyPrefix`, so it returns its named containers via the shared
                // collector (promoted flat below) — NOT through BodyLowering.named
                // (which nests them in the container, the wrong scope here).
                var weaveNamed = bodyNamed.contents
                let children = lowerBody(statements, context: context, keyPrefix: keyPrefix, named: &weaveNamed)
                bodyNamed.merge(weaveNamed)
                return WeaveEmitter.BodyLowering(children: children)
            },
            // Threads the gather/choice loose-end into a body that LEADS with a
            // variable-text line, so its folded trailing choices fall through to the
            // enclosing gather (not the hardcoded `.end`) — #3b layer 1+2.
            lowerStatementWithFallThrough: { statements, looseEnd, _ in
                // Same shared-ordinal seeding as `lowerStatement` so sibling bodies'
                // anonymous conditional/sequence containers get unique ordinals and
                // do not collide when promoted to the enclosing scope (step 01-03).
                var weaveNamed = bodyNamed.contents
                let children = lowerBody(
                    statements, context: context, keyPrefix: keyPrefix,
                    fallThrough: looseEnd, named: &weaveNamed
                )
                bodyNamed.merge(weaveNamed)
                return WeaveEmitter.BodyLowering(children: children)
            },
            lowerCondition: { expression in ExpressionLowering.lowerExpression(expression, context: context) }
        )
        for (key, container) in weave.named {
            named[key] = container
        }
        for (key, container) in bodyNamed.contents {
            named[key] = container
        }
        return weave.children
    }

    /// True when the body's first flow-controlling statement is a weave item
    /// (choice/gather) rather than a variable-text or block-conditional line. A
    /// leading weave must route through the resolver; a leading variable-text /
    /// conditional owns its trailing choices via its continuation (so the flat
    /// `lowerBody` path handles them and the resolver must not pre-empt it).
    private static func leadsWithWeave(_ body: [InkStatement]) -> Bool {
        for statement in body {
            switch statement.kind {
            case .choice, .gather:
                return true
            case .conditionalBlock:
                return false
            case .content(let segments)
                where segments.contains(where: isConditionalSegment)
                   || segments.contains(where: isVariableTextSegment):
                return false
            default:
                continue
            }
        }
        return false
    }

    /// A reference-type accumulator letting the weave `lowerStatement` closure (which
    /// cannot capture an `inout` parameter) collect the named containers each body
    /// emits, so they can be promoted into the enclosing container's namedContent.
    private final class NamedContentCollector {
        private(set) var contents: [String: ContainerNode] = [:]
        func merge(_ other: [String: ContainerNode]) {
            for (key, value) in other { contents[key] = value }
        }
    }

    // MARK: - Declarations

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
            // The value is left on the eval stack for the `{VAR=}` that follows.
            assignments.append(contentsOf: ExpressionLowering.lowerExpression(global.value, context: context))
            assignments.append(.variableAssignment(name: global.name, isGlobal: true))
        }
        let children = ExpressionLowering.evalGroup(assignments) + [.controlCommand("end")]
        return ContainerNode(children: children, namedContent: [:], flags: 0, name: nil)
    }

    // MARK: - Expression lowering

    /// Lower an inline-printed expression with no surrounding declaration or
    /// function tables (see `ExpressionLowering.lowerInlineExpression`).
    static func lowerInlineExpression(_ expression: InkExpression) -> [NodeKind] {
        ExpressionLowering.lowerInlineExpression(expression, context: LoweringContext(constants: [:], functions: [:]))
    }

    // MARK: - Lowering

    private static func emitKnot(_ knot: StoryOutline.Knot, context: LoweringContext) throws -> ContainerNode {
        // Bind the enclosing knot scope so a bare stitch-local divert (`-> waited`)
        // qualifies to its absolute `knot.stitch` path (the runtime resolves divert
        // targets absolutely from root; an un-qualified sibling-stitch target would
        // otherwise dead-end). Stitch and knot bodies share the same knot scope.
        let knotContext = context.inKnotScope(knot.name)
        var named: [String: ContainerNode] = [:]
        for stitch in knot.stitches {
            named[stitch.name] = try emitStitch(
                stitch, keyPrefix: [knot.name, stitch.name], context: knotContext
            )
        }
        var knotNamed = named
        let children = try lowerBodyRoutingWeave(
            knot.body, context: knotContext, keyPrefix: [knot.name], named: &knotNamed,
            terminateFlatBodyWithDone: false
        )
        return ContainerNode(children: children, namedContent: knotNamed, flags: 0, name: knot.name)
    }

    /// Emit one stitch container: lower its body under `keyPrefix` (the path
    /// `emitKnot`/`emitRoot` key it by) in the supplied scope. Used for both
    /// knot-nested stitches (`[knot, stitch]` under a knot-scoped context) and
    /// TOP-LEVEL stitches declared before the first knot (`[stitch]` under the root
    /// context) — the latter are addressable root sections in ink, so they must
    /// become real `namedContent` containers rather than flattening into the root
    /// body (where a `-> stitch` divert would find no container to resolve).
    private static func emitStitch(
        _ stitch: StoryOutline.Stitch, keyPrefix: [String], context: LoweringContext
    ) throws -> ContainerNode {
        var stitchNamed: [String: ContainerNode] = [:]
        let children = try lowerBodyRoutingWeave(
            stitch.body, context: context,
            keyPrefix: keyPrefix, named: &stitchNamed,
            terminateFlatBodyWithDone: false
        )
        return ContainerNode(children: children, namedContent: stitchNamed, flags: 0, name: stitch.name)
    }

    /// Emit a function container: bind the call's pushed arguments to per-frame
    /// temps (the runtime pops the eval stack last-parameter-first, so the temp
    /// bindings are emitted in REVERSE parameter order, matching the oracle), then
    /// lower the body. A body whose last statement is not an explicit `~ return`
    /// relies on the runtime's implicit void return at container exhaustion.
    private static func emitFunction(_ function: StoryOutline.Function, context: LoweringContext) -> ContainerNode {
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
    private static func localNames(of function: StoryOutline.Function) -> Set<String> {
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
        fallThrough: WeaveEmitter.FallThrough = .end,
        named: inout [String: ContainerNode]
    ) -> [NodeKind] {
        var children: [NodeKind] = []
        for (offset, statement) in statements.enumerated() {
            let rest = Array(statements[(offset + 1)...])
            if case .conditionalBlock(let subject, let isSwitch, let branches) = statement.kind {
                children.append(contentsOf: ConditionalEmitter.lower(
                    subject: subject, isSwitch: isSwitch, branches: branches,
                    continuation: rest, keyPrefix: keyPrefix,
                    fallThrough: fallThrough, named: &named,
                    lowerBranch: branchLowerer(context: context),
                    lowerContinuation: inlineConditionalContinuationLowerer(
                        context: context, enclosingKeyPrefix: keyPrefix
                    ),
                    lowerExpression: { ExpressionLowering.lowerExpression($0, context: context) }
                ))
                return children
            }
            if case .content(let segments) = statement.kind,
               let inlineIndex = segments.firstIndex(where: isConditionalSegment) {
                children.append(contentsOf: lowerInlineConditionalLine(
                    segments, conditionalIndex: inlineIndex, restOfBody: rest,
                    context: context, keyPrefix: keyPrefix, fallThrough: fallThrough, named: &named
                ))
                return children
            }
            if case .content(let segments) = statement.kind,
               let variableTextIndex = segments.firstIndex(where: isVariableTextSegment) {
                children.append(contentsOf: lowerVariableTextLine(
                    segments, variableTextIndex: variableTextIndex, restOfBody: rest,
                    context: context, keyPrefix: keyPrefix, fallThrough: fallThrough, named: &named
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
    ) -> ConditionalEmitter.BranchLowerer {
        return { body, prefix, fallThrough, collected in
            // The caller decides where this body's loose end lands (an arm rejoins
            // its own conditional's `-end`; a rejoin body inherits the enclosing
            // scope's fall-through), so THREAD it — a conditional nested in the body
            // otherwise fell back on the `.end` default and ended the story inside
            // its own rejoin container, stranding everything after the outer block.
            lowerBody(body, context: context, keyPrefix: prefix, fallThrough: fallThrough, named: &collected)
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
        fallThrough: WeaveEmitter.FallThrough = .end,
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
            lowerContinuation: continuationLowerer(
                context: context, enclosingKeyPrefix: keyPrefix, fallThrough: fallThrough
            )
        ))
        return children
    }

    /// A continuation lowerer for the variable-text emitter: when the rejoin body
    /// opens a weave (choices that follow the alternative on the same line/knot),
    /// route it through the WeaveEmitter so the choices become real choicePoints +
    /// `c-N`/`g-N` outcome containers (promoted into the caller's collector so they
    /// resolve from the enclosing scope); otherwise lower it flatly.
    private static func continuationLowerer(
        context: LoweringContext,
        enclosingKeyPrefix: [String],
        fallThrough: WeaveEmitter.FallThrough
    ) -> (_ body: [InkStatement], _ prefix: [String], _ named: inout [String: ContainerNode]) -> [NodeKind] {
        return { body, prefix, collected in
            // The weave's `c-N`/`g-N` outcome/gather containers promote up into the
            // ENCLOSING scope's named map (the variable-text caller's collector), so
            // they are addressed from that scope — keyed by `enclosingKeyPrefix`, not
            // the continuation's own `prefix`. The loose-end fall-through threads the
            // enclosing target down so choices after the variable-text line fall
            // through to the enclosing gather, not the hardcoded `.end` (#3b layer 2).
            //
            // Route through the resolver ONLY when the continuation LEADS with a
            // weave item (choice/gather). When it leads with ANOTHER variable-text /
            // inline-conditional line (a multi-segment line `{&…} {!…}` then choices),
            // the flat `lowerBody` path chains that segment's own continuation into
            // the trailing choices — threading `fallThrough` so they still fall
            // through to the enclosing gather. Routing such a body through the
            // resolver would split the second segment's lead from the choice items,
            // dead-ending the dispatch before the choices are reached (#3b layer 1+2).
            guard let weave = lowerLeadingWeave(
                body, keyPrefix: enclosingKeyPrefix, fallThrough: fallThrough, context: context
            ) else {
                // Address the chained segment's containers under `enclosingKeyPrefix`
                // (not the continuation's own `prefix`): like the weave branch above,
                // its dispatch/stage/choice containers promote up into the enclosing
                // scope's collector, so their paths must resolve from that scope.
                return lowerBody(
                    body, context: context, keyPrefix: enclosingKeyPrefix,
                    fallThrough: fallThrough, named: &collected
                )
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
        fallThrough: WeaveEmitter.FallThrough = .end,
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
            continuation: continuation, keyPrefix: keyPrefix,
            fallThrough: fallThrough, named: &named,
            lowerBranch: branchLowerer(context: context),
            lowerContinuation: inlineConditionalContinuationLowerer(
                context: context, enclosingKeyPrefix: keyPrefix
            ),
            lowerExpression: { ExpressionLowering.lowerExpression($0, context: context) },
            qualifyDivertTarget: { context.qualifiedDivertTarget($0) }
        ))
        return children
    }

    /// A continuation lowerer for the inline-conditional rejoin `-end` container.
    /// When the rejoin opens a weave (trailing choices/gathers after the line, e.g.
    /// the post-lift_up_cup gather's `[Agree]/[Disagree]/…`), route it through the
    /// WeaveEmitter so they become real choicePoints whose loose ends thread the
    /// enclosing fall-through; the resolver promotes the `c-N`/`g-N` containers into
    /// the ENCLOSING scope (keyed by `enclosingKeyPrefix`). A NON-weave rejoin
    /// (plain text + logic, or a nested inline conditional like `{forceful<=0:…}`)
    /// lowers under the rejoin's OWN `prefix` so its nested containers nest under
    /// `…cond{N}-end`, not the enclosing scope (which would collide with sibling
    /// conditionals — step 01-04 cross-wiring regression).
    private static func inlineConditionalContinuationLowerer(
        context: LoweringContext,
        enclosingKeyPrefix: [String]
    ) -> ConditionalEmitter.BranchLowerer {
        // The rejoin's loose-end target arrives as a PARAMETER rather than being
        // captured here: the emitter is the one that knows whether it is lowering a
        // rejoin (the enclosing fall-through) or an arm (its own `-end`), and one
        // source for that target keeps the two from drifting apart.
        return { body, prefix, fallThrough, collected in
            // The rejoin's own `prefix` (`…cond{N}-end`) is the scope BOTH the weave
            // c-N/g-N containers and any nested inline conditional nest under, so
            // choicePoint targets and rejoin diverts resolve self-consistently and
            // never collide with sibling conditionals in the enclosing scope.
            guard let weave = lowerLeadingWeave(
                body, keyPrefix: prefix, fallThrough: fallThrough, context: context
            ) else {
                return lowerBody(
                    body, context: context, keyPrefix: prefix,
                    fallThrough: fallThrough, named: &collected
                )
            }
            for (key, container) in weave.named {
                collected[key] = container
            }
            return weave.children
        }
    }

    /// Lower a continuation body that LEADS with a weave item through the
    /// WeaveEmitter, so its choices become real choicePoints whose loose ends
    /// thread `fallThrough`, with the `c-N`/`g-N` containers addressed under
    /// `keyPrefix`. Returns `nil` when the body does not lead with a weave (or the
    /// resolver fails) — the caller then lowers it flatly.
    ///
    /// Each weave body lowers under its OWN per-container prefix; its
    /// inline-conditional `cond{N}-b*`/`-end` arms and variable-text
    /// sub-containers must nest inside that container — return them via
    /// BodyLowering so the resolver attaches them (step 01-13: the `[Yes]` body's
    /// `{forceful>2:…|…}` branches were dropped here, leaving the dispatch's
    /// branch diverts pointing at nothing).
    ///
    /// The choice-guard lowerer is threaded so the weave's `{cond}` guards emit
    /// their eval-stack nodes — a knot/gather-opening block conditional whose
    /// rejoin is a guarded choice menu (e.g. `admitted_to_something`'s
    /// `{not drugged}[…]` / `{drugged}[…]` choices) otherwise lowered every choice
    /// unguarded (all shown).
    private static func lowerLeadingWeave(
        _ body: [InkStatement],
        keyPrefix: [String],
        fallThrough: WeaveEmitter.FallThrough,
        context: LoweringContext
    ) -> (children: [NodeKind], named: [String: ContainerNode])? {
        guard leadsWithWeave(body) else {
            return nil
        }
        return try? WeaveEmitter.lower(
            body, keyPrefix: keyPrefix, fallThrough: fallThrough,
            lowerStatement: { statements, bodyKeyPrefix in
                var weaveNamed: [String: ContainerNode] = [:]
                let children = lowerBody(statements, context: context, keyPrefix: bodyKeyPrefix, named: &weaveNamed)
                return WeaveEmitter.BodyLowering(children: children, named: weaveNamed)
            },
            lowerStatementWithFallThrough: { statements, looseEnd, bodyKeyPrefix in
                var weaveNamed: [String: ContainerNode] = [:]
                let children = lowerBody(
                    statements, context: context, keyPrefix: bodyKeyPrefix,
                    fallThrough: looseEnd, named: &weaveNamed
                )
                return WeaveEmitter.BodyLowering(children: children, named: weaveNamed)
            },
            lowerCondition: { expression in ExpressionLowering.lowerExpression(expression, context: context) }
        )
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
            return [.divert(
                target: .path(PathReference(parsing: context.qualifiedDivertTarget(target))),
                isConditional: false
            )]
        case .tunnelDivert(let target):
            return [.tunnelDivert(target: PathReference(parsing: target))]
        case .tunnelReturn:
            // The runtime pops the tunnel return address on `->->`; the leading
            // `ev void /ev` matches the oracle (a void result for the call site).
            return ExpressionLowering.evalGroup([.voidValue]) + [.controlCommand("->->")]
        case .functionCallStatement(let call):
            return lowerFunctionCallStatement(call, context: context)
        case .returnStatement(let value):
            return lowerReturn(value, context: context)
        case .end:
            return [.controlCommand("end")]
        case .glue:
            return [.controlCommand("<>")]
        // These emit nothing in the body stream:
        // - Declarations are hoisted into the `global decl` container (VAR) or
        //   inlined at codegen (CONST).
        // - Headers/definitions are consumed during grouping (`StoryOutline`).
        // - Weave lines are resolved by the WeaveEmitter before reaching the flat
        //   statement lowerer.
        // - Block/switch conditionals are resolved by lowerBody (which threads the
        //   named-content collector + key-prefix).
        case .globalVariable, .constant, .knot, .stitch, .functionDefinition,
             .choice, .gather, .conditionalBlock:
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
        ExpressionLowering.evalGroup(ExpressionLowering.lowerExpression(call, context: context) + [.controlCommand("pop")])
    }

    /// Lower a function return `~ return [expr]`: evaluate the optional value onto
    /// the eval stack, then emit `~ret` (the runtime pops the function return
    /// address and jumps back to the caller, leaving the value for its `out`).
    private static func lowerReturn(
        _ value: InkExpression?,
        context: LoweringContext
    ) -> [NodeKind] {
        let valueNodes = value.map { ExpressionLowering.lowerExpression($0, context: context) } ?? []
        return ExpressionLowering.evalGroup(valueNodes) + [.controlCommand("~ret")]
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
                nodes.append(contentsOf: ExpressionLowering.lowerInlineExpression(expression, context: context))
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
        ExpressionLowering.evalGroup(ExpressionLowering.lowerExpression(value, context: context))
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
