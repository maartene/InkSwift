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
        let (rootBody, knots, functionDefinitions) = partitionTopLevel(statements)
        // Discovery pre-pass (ADR-011 EXTEND #3): record the labelled weave-point
        // paths before lowering so read-count references resolve order-independently.
        // Weave labels live in the root body AND inside knot/stitch bodies (e.g.
        // TheIntercept's `(delay)` under `start`, `(tellme)` under `start.waited`);
        // each is keyed by its enclosing knot/stitch prefix so a dotted read-count
        // (`start.delay`) resolves to the absolute container path.
        var weaveLabelPaths = WeaveEmitter.discover(rootBody).labelPaths
        for knot in knots {
            mergeWeaveLabelPaths(of: knot, into: &weaveLabelPaths)
        }
        // Bare-name local resolution (step 01-04): a read-count subject spelled by
        // its BARE label (`{lift_up_cup:he|Harris}` referencing the `(lift_up_cup)`
        // choice in the same stitch) resolves in inklecate's local scope. Register
        // each bare label that is UNIQUE story-wide so the bare reference resolves;
        // duplicated bare labels (e.g. `opts`/`yes` reused across knots) stay
        // dotted-only — registering them would mis-resolve to the last knot's path.
        mergeUniqueBareLabels(rootBody: rootBody, knots: knots, into: &weaveLabelPaths)
        // Knot/stitch read-count addressing (ADR-011 EXTEND #2): record every
        // knot's and stitch's already-built namedContent path so a dotted
        // read-count subject (`knot.stitch`) resolves to its container path,
        // reusing the SAME path arithmetic emitKnot/emitStitch address by — never
        // re-derived. The runtime resolves the dotted key as-is against visitCounts.
        let knotStitchPaths = collectKnotStitchPaths(knots)
        let context = LoweringContext(
            constants: constants, functions: functions,
            weaveLabelPaths: weaveLabelPaths, knotStitchPaths: knotStitchPaths
        )

        var namedContent: [String: ContainerNode] = [:]
        let rootChildren = try lowerRootBody(rootBody, context: context, named: &namedContent)

        for knot in knots {
            namedContent[knot.name] = try emitKnot(knot, context: context)
        }
        for function in functionDefinitions {
            namedContent[function.name] = emitFunction(function, context: context)
        }
        if let globalDecl = emitGlobalDecl(statements, context: context) {
            namedContent[globalDeclKey] = globalDecl
        }
        let builtRoot = ContainerNode(children: rootChildren, namedContent: namedContent, flags: 0, name: nil)
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
        let root = reconcilingReadCountPaths(builtRoot)
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

    /// Codegen-wide lowering inputs threaded through the lowerers: the CONST
    /// inlining table and the function-signature table (so a `ref` argument can
    /// be lowered to a `variablePointer` at the call site).
    struct LoweringContext {
        let constants: [String: InkExpression]
        let functions: [String: [FunctionParameter]]
        /// The weave-label addressing table (ADR-011 EXTEND #3): source label ->
        /// absolute compiled path, populated by the discovery pre-pass before
        /// expression lowering so a read-count reference (later steps) resolves a
        /// label to its container path order-independently. Labelled-only. Threaded
        /// identically to the CONST and function tables; write-only at this slice
        /// (02-03 consumes it to emit `.readCount`).
        var weaveLabelPaths: [String: [String]] = [:]
        /// The knot/stitch read-count addressing table (ADR-011 EXTEND #2): a
        /// dotted source name (`knot.stitch`, or a bare `knot`) -> its absolute
        /// compiled namedContent path. Reuses the path emitKnot/emitStitch already
        /// key their containers by; consumed by the `.variableReference` lowering to
        /// emit `.readCount` for a dotted read-count subject naming a knot/stitch.
        var knotStitchPaths: [String: [String]] = [:]
        /// Names that are function-local in the current scope (parameters plus
        /// `~ temp` declarations inside a function body). An assignment to a local
        /// name lowers to `temp=` so the runtime consults the call frame — the
        /// write-through path that makes a `ref` parameter mutate the caller's
        /// variable. Empty at knot/root scope (all assignments are global there).
        var localNames: Set<String> = []
        /// The enclosing knot name of the body being lowered (empty at root). A bare
        /// divert target `-> T` inside a knot resolves first to a SIBLING stitch
        /// `knot.T` (ink scoping: current-knot stitch before root knot), but the
        /// runtime resolves divert targets ABSOLUTELY from root — so a bare stitch
        /// target dead-ends (no root-level `T`). The divert lowerer consults this to
        /// qualify a bare target to `knot.T` when `knot.T` is a known stitch.
        var knotScope: String = ""

        func bindingLocals(_ names: Set<String>) -> LoweringContext {
            LoweringContext(
                constants: constants, functions: functions,
                weaveLabelPaths: weaveLabelPaths, knotStitchPaths: knotStitchPaths,
                localNames: names, knotScope: knotScope
            )
        }

        /// Bind the enclosing knot scope so bare stitch-local diverts qualify.
        func inKnotScope(_ knotName: String) -> LoweringContext {
            LoweringContext(
                constants: constants, functions: functions,
                weaveLabelPaths: weaveLabelPaths, knotStitchPaths: knotStitchPaths,
                localNames: localNames, knotScope: knotName
            )
        }

        /// Resolve a bare divert target against the current knot scope. A bare `T`
        /// that names a sibling stitch (`knot.T` is a known stitch path) qualifies to
        /// `knot.T` so the runtime's absolute-from-root resolution finds it. A bare `T`
        /// that names a WEAVE LABEL anywhere in the current knot (`knot.T` is a known
        /// weave-label name) qualifies to that label's ABSOLUTE physical container
        /// path — a deeply-nested gather label (`-> pushes_cup` reaching a `- -`
        /// gather inside a sibling choice body) resolves regardless of nesting depth,
        /// mirroring inklecate's by-name weave-point resolution. Any other target
        /// (already-dotted, root knot, relative `.^`) is returned unchanged. Mirrors
        /// ink scoping (current-knot stitch / weave label before root knot).
        func qualifiedDivertTarget(_ target: String) -> String {
            guard knotScope.isEmpty == false,
                  target.contains(".") == false,
                  target.hasPrefix(".") == false else { return target }
            let qualified = "\(knotScope).\(target)"
            if knotStitchPaths[qualified] != nil { return qualified }
            if let labelPath = weaveLabelPaths[qualified] { return labelPath.joined(separator: ".") }
            return target
        }

        /// Resolve a (possibly dotted) name to the absolute compiled path of a
        /// known weave label or knot/stitch, reusing the pre-built tables — never
        /// re-deriving. Returns nil for a true miss (a real qualified variable).
        func readCountPath(for name: String) -> [String]? {
            if let labelPath = weaveLabelPaths[name] { return labelPath }
            return knotStitchPaths[name]
        }
    }

    /// Register the labelled weave points inside a knot's body and each of its
    /// stitch bodies, keyed by their dotted source name (`knot.label`,
    /// `knot.stitch.label`) so a knot-qualified read-count reference resolves to the
    /// absolute container path. Reuses the same key arithmetic the weave resolver
    /// addresses the containers by — never re-derived.
    private static func mergeWeaveLabelPaths(of knot: KnotGroup, into table: inout [String: [String]]) {
        for (key, path) in WeaveEmitter.discoverLabelPaths(knot.body, keyPrefix: [knot.name]) {
            table[key] = path
        }
        for stitch in knot.stitches {
            let prefix = [knot.name, stitch.name]
            for (key, path) in WeaveEmitter.discoverLabelPaths(stitch.body, keyPrefix: prefix) {
                table[key] = path
            }
        }
    }

    /// Register each BARE weave label that is unique across the whole story into the
    /// read-count table, so a bare-named read-count subject resolves in local scope.
    /// A bare name occurring in two or more bodies is left dotted-only (ambiguous).
    private static func mergeUniqueBareLabels(
        rootBody: [InkStatement],
        knots: [KnotGroup],
        into table: inout [String: [String]]
    ) {
        var occurrences: [String: [[String]]] = [:]
        func collect(_ body: [InkStatement], keyPrefix: [String]) {
            for (label, path) in WeaveEmitter.discoverBareLabelPaths(body, keyPrefix: keyPrefix) {
                occurrences[label, default: []].append(path)
            }
        }
        collect(rootBody, keyPrefix: [])
        for knot in knots {
            collect(knot.body, keyPrefix: [knot.name])
            for stitch in knot.stitches {
                collect(stitch.body, keyPrefix: [knot.name, stitch.name])
            }
        }
        for (label, paths) in occurrences where paths.count == 1 {
            if table[label] == nil { table[label] = paths[0] }
        }
    }

    /// Build the knot/stitch read-count path table (ADR-011 EXTEND #2). A knot is
    /// addressed by `[knot.name]`; a stitch nested under it by `[knot.name,
    /// stitch.name]` — the same namedContent path `emitKnot`/`emitStitch` key their
    /// containers by. The dotted source name (`knot.stitch`) is the lookup key.
    private static func collectKnotStitchPaths(_ knots: [KnotGroup]) -> [String: [String]] {
        var paths: [String: [String]] = [:]
        for knot in knots {
            paths[knot.name] = [knot.name]
            for stitch in knot.stitches {
                paths["\(knot.name).\(stitch.name)"] = [knot.name, stitch.name]
            }
        }
        return paths
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
                // `keyPrefix`, so target and storage agree.
                var weaveNamed = bodyNamed.contents
                let children = lowerBody(statements, context: context, keyPrefix: keyPrefix, named: &weaveNamed)
                bodyNamed.merge(weaveNamed)
                return children
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
                return children
            },
            lowerCondition: { expression in lowerExpression(expression, context: context) }
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
            // A name resolving to a known weave label or knot/stitch is a
            // read-count subject (ADR-011 EXTEND #2): emit `.readCount(path)`
            // addressing the resolved container. A true miss (a real qualified
            // variable) falls through to `.variableReference`.
            if let path = context.readCountPath(for: name) {
                return [.readCount(path.joined(separator: "."))]
            }
            return [.variableReference(name: name)]
        case .binary(let oper, let left, let right):
            var nodes = lowerExpression(left, context: context)
            nodes.append(contentsOf: lowerExpression(right, context: context))
            nodes.append(.nativeFunction(oper))
            return nodes
        case .unary(let oper, let operand):
            var nodes = lowerExpression(operand, context: context)
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

    private static func emitKnot(_ knot: KnotGroup, context: LoweringContext) throws -> ContainerNode {
        // Bind the enclosing knot scope so a bare stitch-local divert (`-> waited`)
        // qualifies to its absolute `knot.stitch` path (the runtime resolves divert
        // targets absolutely from root; an un-qualified sibling-stitch target would
        // otherwise dead-end). Stitch and knot bodies share the same knot scope.
        let knotContext = context.inKnotScope(knot.name)
        var named: [String: ContainerNode] = [:]
        for stitch in knot.stitches {
            var stitchNamed: [String: ContainerNode] = [:]
            let children = try lowerBodyRoutingWeave(
                stitch.body, context: knotContext,
                keyPrefix: [knot.name, stitch.name], named: &stitchNamed,
                terminateFlatBodyWithDone: false
            )
            named[stitch.name] = ContainerNode(
                children: children, namedContent: stitchNamed, flags: 0, name: stitch.name
            )
        }
        var knotNamed = named
        let children = try lowerBodyRoutingWeave(
            knot.body, context: knotContext, keyPrefix: [knot.name], named: &knotNamed,
            terminateFlatBodyWithDone: false
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
                    lowerExpression: { lowerExpression($0, context: context) }
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
            guard leadsWithWeave(body),
                  let weave = try? WeaveEmitter.lower(
                      body, keyPrefix: enclosingKeyPrefix, fallThrough: fallThrough,
                      lowerStatement: { statements, bodyKeyPrefix in
                          var weaveNamed: [String: ContainerNode] = [:]
                          return lowerBody(statements, context: context, keyPrefix: bodyKeyPrefix, named: &weaveNamed)
                      },
                      lowerStatementWithFallThrough: { statements, looseEnd, bodyKeyPrefix in
                          var weaveNamed: [String: ContainerNode] = [:]
                          return lowerBody(
                              statements, context: context, keyPrefix: bodyKeyPrefix,
                              fallThrough: looseEnd, named: &weaveNamed
                          )
                      }) else {
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
                context: context, enclosingKeyPrefix: keyPrefix, fallThrough: fallThrough
            ),
            lowerExpression: { lowerExpression($0, context: context) }
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
        enclosingKeyPrefix: [String],
        fallThrough: WeaveEmitter.FallThrough
    ) -> (_ body: [InkStatement], _ prefix: [String], _ named: inout [String: ContainerNode]) -> [NodeKind] {
        return { body, prefix, collected in
            // The rejoin's own `prefix` (`…cond{N}-end`) is the scope BOTH the weave
            // c-N/g-N containers and any nested inline conditional nest under, so
            // choicePoint targets and rejoin diverts resolve self-consistently and
            // never collide with sibling conditionals in the enclosing scope.
            guard leadsWithWeave(body),
                  let weave = try? WeaveEmitter.lower(
                      body, keyPrefix: prefix, fallThrough: fallThrough,
                      lowerStatement: { statements, bodyKeyPrefix in
                          var weaveNamed: [String: ContainerNode] = [:]
                          return lowerBody(statements, context: context, keyPrefix: bodyKeyPrefix, named: &weaveNamed)
                      },
                      lowerStatementWithFallThrough: { statements, looseEnd, bodyKeyPrefix in
                          var weaveNamed: [String: ContainerNode] = [:]
                          return lowerBody(
                              statements, context: context, keyPrefix: bodyKeyPrefix,
                              fallThrough: looseEnd, named: &weaveNamed
                          )
                      }) else {
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
                target: context.qualifiedDivertTarget(target),
                isConditional: false, isVariable: false
            )]
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
