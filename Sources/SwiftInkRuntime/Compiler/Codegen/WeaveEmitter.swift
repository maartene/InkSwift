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
//     algorithm DELIVER extended to nested levels.
//
// GENERAL WEAVE RESOLVER (DELIVER S3 / ADR-008 / DDD-6): resolves the full Ink
// weave structure — indentation-driven choice/gather hierarchy, labeled and
// multiple gathers, plain-label and sticky choices, loose-end stitching, and
// sealed weaves — into a `ContainerNode` tree the EXISTING runtime engine plays
// choice-for-choice identical to the inklecate oracle. Codegen has full freedom
// over tree shape; only PLAY/choice equivalence matters (NOT byte-for-byte JSON
// parity — D5 Level-1 correctness, ADR-008 spike gate).
//
// CONTAINER-CONSTRUCTION TEMPLATE (probe-validated, SPIKE findings §2):
//   - Each choice at a level emits, into its enclosing container's `children`:
//     `ev str ^<label> /str /ev` (pushes the menu text for the engine's
//     `resolveChoiceText()` strategy #1) followed by
//     `choicePoint(target: <c-key>, flags:)`. Bracketed `* [text] body` uses
//     flag 0x14 (hasChoiceOnlyContent | isOnceOnly) and does NOT echo the label;
//     plain `* text` uses flag 0x12 (hasStartContent | isOnceOnly) and echoes the
//     label into output. Sticky `+` omits the once-only bit 0x10.
//   - A sibling `namedContent` map holds the outcome containers `c-N` and the
//     gather containers `g-N`. A nested weave nests its own c/g map inside the
//     parent choice's outcome container, addressed by qualified path (`c-0.g-0`).
//   - Loose-end stitching (SPIKE findings §3): a choice body's loose end diverts
//     to the nearest gather at its own level after it; a gather's loose end
//     diverts to the next gather at the enclosing (shallower) level; a top-level
//     gather's loose end is `end`. A body that already diverts away (sealed) gets
//     no fall-through divert.
//   - Addressing uses absolute-qualified paths from root (SPIKE findings §4): the
//     engine's `navigateAbsolute`/`resolveNamedPath` walk namedContent/numeric
//     children from root, so qualified names resolve unambiguously regardless of
//     execution position — no relative `.^.` caret arithmetic required.

import Foundation

enum WeaveEmitter {

    /// Does this body contain at least one weave choice (and so must lower
    /// through the weave resolver rather than the flat statement lowerer)?
    static func containsWeave(_ statements: [InkStatement]) -> Bool {
        statements.contains { statement in
            if case .choice = statement.kind { return true }
            return false
        }
    }

    /// Lower a body containing a weave into the runtime tree: the leading prose +
    /// per-choice label/choicePoint nodes go into `children`; the outcome
    /// containers `c-N` and gather containers `g-N` go into `named`. Addresses are
    /// absolute-qualified from root; nested weaves recurse with a deeper key prefix.
    static func lower(
        _ statements: [InkStatement],
        keyPrefix: [String] = [],
        lowerStatement: @escaping ([InkStatement]) -> [NodeKind],
        lowerCondition: @escaping (InkExpression) -> [NodeKind] = { _ in [] }
    ) throws -> (children: [NodeKind], named: [String: ContainerNode]) {
        let resolved = try lowerWithLabelPaths(
            statements, keyPrefix: keyPrefix,
            lowerStatement: lowerStatement, lowerCondition: lowerCondition
        )
        return (resolved.children, resolved.named)
    }

    /// Lower a weave AND expose the `label -> absolute compiled path` table the
    /// `WeaveResolver` writes at its keying site (criterion 3). The same arithmetic
    /// that keys the outcome/gather containers records the labelled-only path —
    /// never re-derived. Unlabelled `c-N`/`g-N` containers are not registered.
    /// `lowerCondition` lowers a choice's `{guard}` expression to POSTFIX eval-stack
    /// nodes (the `RuntimeObjectEmitter.lowerExpression` idiom, reused — not edited).
    /// `keyPrefix` is the enclosing knot/stitch path: choicePoint divert targets and
    /// loose-end diverts are absolute-qualified from root, so a weave nested in a
    /// knot addresses its `c-N`/`g-N` containers as `knot.c-N` (the engine resolves
    /// absolute named paths regardless of execution position).
    static func lowerWithLabelPaths(
        _ statements: [InkStatement],
        keyPrefix: [String] = [],
        lowerStatement: @escaping ([InkStatement]) -> [NodeKind],
        lowerCondition: @escaping (InkExpression) -> [NodeKind] = { _ in [] }
    ) throws -> (children: [NodeKind], named: [String: ContainerNode], labelPaths: [String: [String]]) {
        let block = WeaveParser.parse(statements, atLevel: 1)
        let resolver = WeaveResolver(lowerStatement: lowerStatement, lowerCondition: lowerCondition)
        let resolved = try resolver.resolve(block, keyPrefix: keyPrefix, fallThrough: .end)
        return (resolved.children, resolved.named, resolver.labelPaths)
    }

    /// Discovery pre-pass (ADR-011 EXTEND #3 — the inklecate `ResolveWeavePointNaming`
    /// phase-1 analogue): walk the level-partitioned weave BEFORE expression
    /// lowering and (a) record every LABELLED container's absolute path into the
    /// table, (b) collect the SET of labels that appear as read-count references
    /// (a condition subject naming a known label). Running before lowering makes
    /// resolution order-independent — a forward reference resolves (criterion 4).
    /// Unlabelled `c-N`/`g-N` containers are NOT registered (criterion 5).
    static func discover(
        _ statements: [InkStatement]
    ) -> (labelPaths: [String: [String]], referencedLabels: Set<String>) {
        let block = WeaveParser.parse(statements, atLevel: 1)
        var labelPaths: [String: [String]] = [:]
        WeaveDiscovery.recordLabelPaths(block, keyPrefix: [], into: &labelPaths)
        let referencedLabels = WeaveDiscovery.referencedLabels(block, knownLabels: Set(labelPaths.keys))
        return (labelPaths, referencedLabels)
    }

    /// Discover labelled weave-point paths inside a body nested under `keyPrefix`
    /// (a knot or knot.stitch). Each label's absolute path is `keyPrefix + label`,
    /// and the lookup key is the DOTTED source name (`knot.label`, `knot.stitch.label`)
    /// the reference uses — so `{not start.delay}` resolves to `[start, delay]`.
    static func discoverLabelPaths(
        _ statements: [InkStatement],
        keyPrefix: [String]
    ) -> [String: [String]] {
        guard containsWeave(statements) else { return [:] }
        let block = WeaveParser.parse(statements, atLevel: 1)
        var localPaths: [String: [String]] = [:]
        WeaveDiscovery.recordLabelPaths(block, keyPrefix: keyPrefix, into: &localPaths)
        // recordLabelPaths keys by bare label; re-key by the dotted source name so
        // a knot-qualified reference (`knot.label`) resolves to the absolute path.
        var qualified: [String: [String]] = [:]
        for path in localPaths.values {
            qualified[path.joined(separator: ".")] = path
        }
        return qualified
    }
}

// MARK: - Discovery pre-pass (phase-1 weave-point naming)

/// Walks the parsed `WeaveBlock` tree to register labelled weave-point paths and
/// the labels referenced as read-counts — independent of lowering order, so a
/// forward reference resolves. Reuses the resolver's `label ?? c-N/g-N` keying
/// shape but registers ONLY the labelled segments (labelled-only addressability).
private enum WeaveDiscovery {

    /// Record every labelled container's absolute path (keyPrefix + label) into
    /// `labelPaths`. Unlabelled `c-N`/`g-N` ordinals are walked for nesting but
    /// not registered; a nested labelled container keys under its parent label.
    static func recordLabelPaths(
        _ block: WeaveBlock,
        keyPrefix: [String],
        into labelPaths: inout [String: [String]]
    ) {
        var choiceOrdinal = 0
        var gatherOrdinal = 0
        for item in block.items {
            switch item {
            case .choice(let choice):
                let key = choice.weaveLabel ?? "c-\(choiceOrdinal)"
                registerIfLabelled(choice.weaveLabel, key: key, keyPrefix: keyPrefix, into: &labelPaths)
                if let nested = choice.nested {
                    recordLabelPaths(nested, keyPrefix: keyPrefix + [key], into: &labelPaths)
                }
                choiceOrdinal += 1
            case .gather(let gather):
                let key = gather.label ?? "g-\(gatherOrdinal)"
                registerIfLabelled(gather.label, key: key, keyPrefix: keyPrefix, into: &labelPaths)
                if let nested = gather.nested {
                    recordLabelPaths(nested, keyPrefix: keyPrefix + [key], into: &labelPaths)
                }
                gatherOrdinal += 1
            }
        }
    }

    private static func registerIfLabelled(
        _ label: String?,
        key: String,
        keyPrefix: [String],
        into labelPaths: inout [String: [String]]
    ) {
        guard let label else { return }
        labelPaths[label] = keyPrefix + [key]
    }

    /// The SET of known labels appearing as a read-count reference: any condition
    /// (a choice guard) whose expression references a name whose dotted segments
    /// include a known label. Walks every choice/gather's condition and nested
    /// structure (order-independent — the known-label set is computed up front).
    static func referencedLabels(_ block: WeaveBlock, knownLabels: Set<String>) -> Set<String> {
        var referenced: Set<String> = []
        collectReferenced(block, knownLabels: knownLabels, into: &referenced)
        return referenced
    }

    private static func collectReferenced(
        _ block: WeaveBlock,
        knownLabels: Set<String>,
        into referenced: inout Set<String>
    ) {
        for item in block.items {
            switch item {
            case .choice(let choice):
                if let condition = choice.condition {
                    collectLabelsIn(condition, knownLabels: knownLabels, into: &referenced)
                }
                if let nested = choice.nested {
                    collectReferenced(nested, knownLabels: knownLabels, into: &referenced)
                }
            case .gather(let gather):
                if let nested = gather.nested {
                    collectReferenced(nested, knownLabels: knownLabels, into: &referenced)
                }
            }
        }
    }

    /// Add any known label named by a variable reference inside `expression` —
    /// matching either the bare name (`{label: …}`) or any dotted segment
    /// (`{head.label: …}`) — to the referenced set.
    private static func collectLabelsIn(
        _ expression: InkExpression,
        knownLabels: Set<String>,
        into referenced: inout Set<String>
    ) {
        switch expression {
        case .variableReference(let name):
            for segment in name.split(separator: ".").map(String.init) where knownLabels.contains(segment) {
                referenced.insert(segment)
            }
        case .binary(_, let left, let right):
            collectLabelsIn(left, knownLabels: knownLabels, into: &referenced)
            collectLabelsIn(right, knownLabels: knownLabels, into: &referenced)
        case .unary(_, let operand):
            collectLabelsIn(operand, knownLabels: knownLabels, into: &referenced)
        case .functionCall(_, let arguments):
            for argument in arguments {
                collectLabelsIn(argument, knownLabels: knownLabels, into: &referenced)
            }
        case .intLiteral, .boolLiteral, .floatLiteral, .stringLiteral:
            break
        }
    }
}

// MARK: - Weave tree (level-partitioned intermediate representation)

/// A weave block at one nesting level: leading prose plus an ordered sequence of
/// items (choices and gathers at this level). Statements trailing the block's
/// final gather (e.g. a top-level `-> END`) fold into that gather's body.
private struct WeaveBlock {
    let lead: [InkStatement]
    let items: [WeaveItem]
}

/// One element of a weave block at a given level.
private enum WeaveItem {
    /// A choice plus its body: the prose that runs when chosen and any nested
    /// weave (choices at a deeper level) inside that body.
    case choice(WeaveChoice)
    /// A gather at this level: its label, its outcome prose, and the body that
    /// follows it up to the next same-level gather.
    case gather(WeaveGather)
}

private struct WeaveChoice {
    let label: String
    /// The optional leading `(name)` weave label — symmetric with a gather's
    /// `label`. Keys the choice's outcome container (`weaveLabel ?? "c-N"`).
    let weaveLabel: String?
    let echoesLabel: Bool
    let isSticky: Bool
    /// Body prose that runs after the choice is taken (before any nested weave).
    let body: [InkStatement]
    /// A nested weave inside the choice body, when the body contains deeper choices.
    let nested: WeaveBlock?
    /// The optional `{…}` guard expression (ADR-011): captured so the discovery
    /// pre-pass can collect labels referenced as read-counts. Not lowered here
    /// (the choice-offer guard emission is a later slice); discovery-only at 02-02.
    let condition: InkExpression?
}

private struct WeaveGather {
    let label: String?
    /// The gather's own outcome prose.
    let body: [InkStatement]
    /// The implicit sub-weave a gather opens: choices (and deeper structure)
    /// following the gather belong to its scope, terminating at the next
    /// same-or-shallower gather. `nil` when the gather is followed only by prose.
    let nested: WeaveBlock?
}

// MARK: - Parsing the flat stream into the level-partitioned tree

/// Splits a flat `[InkStatement]` stream into a `WeaveBlock` tree by weave level.
/// A choice/gather at the current level belongs to this block; a deeper choice
/// opens a nested weave inside the current choice; a shallower gather terminates
/// the block (it belongs to an enclosing level).
private enum WeaveParser {

    static func parse(_ statements: [InkStatement], atLevel level: Int) -> WeaveBlock {
        var cursor = 0
        return parseBlock(statements, cursor: &cursor, atLevel: level, stopAtSameLevelGather: false)
    }

    /// Parse a weave block at `level`. When `stopAtSameLevelGather` is set (the
    /// gather-opened sub-scope context), a same-level gather terminates the block
    /// and is returned to the caller as a sibling; otherwise it is consumed as an
    /// item of this block. A shallower choice/gather always terminates the block.
    private static func parseBlock(
        _ statements: [InkStatement],
        cursor: inout Int,
        atLevel level: Int,
        stopAtSameLevelGather: Bool
    ) -> WeaveBlock {
        var lead: [InkStatement] = []
        var items: [WeaveItem] = []
        var sawItem = false

        while cursor < statements.count {
            let statement = statements[cursor]
            switch statement.kind {
            case .choice(let choiceLevel, _, _, _, _, _) where choiceLevel < level,
                 .gather(let choiceLevel, _, _) where choiceLevel < level:
                return WeaveBlock(lead: lead, items: items)
            case .gather(let gatherLevel, _, _) where gatherLevel == level && stopAtSameLevelGather:
                return WeaveBlock(lead: lead, items: items)
            case .choice(let choiceLevel, _, _, _, _, _) where choiceLevel == level:
                cursor += 1
                items.append(.choice(parseChoice(statement, statements, cursor: &cursor, atLevel: level)))
                sawItem = true
            case .gather(let gatherLevel, _, _) where gatherLevel == level:
                cursor += 1
                items.append(.gather(parseGather(statement, statements, cursor: &cursor, atLevel: level)))
                sawItem = true
            default:
                cursor += 1
                if sawItem == false {
                    lead.append(statement)
                } else {
                    return WeaveBlock(lead: lead, items: appendTrailing(statement, to: items))
                }
            }
        }
        return WeaveBlock(lead: lead, items: items)
    }

    /// Parse a choice's body: the prose that runs after it, plus a nested weave
    /// when deeper choices follow. Stops at the next same-or-shallower item.
    private static func parseChoice(
        _ header: InkStatement,
        _ statements: [InkStatement],
        cursor: inout Int,
        atLevel level: Int
    ) -> WeaveChoice {
        guard case .choice(_, let isSticky, let choiceOnlyLabel, let body, let weaveLabel, let condition) = header.kind else {
            fatalError("parseChoice requires a choice statement")
        }
        var bodyStatements: [InkStatement] = []
        if choiceOnlyLabel != nil {
            bodyStatements.append(contentsOf: inlineBodyStatements(body, at: header.position))
        }
        var nested: WeaveBlock?

        while cursor < statements.count {
            let statement = statements[cursor]
            if isDeeperChoice(statement, than: level) {
                nested = parseBlock(statements, cursor: &cursor, atLevel: level + 1, stopAtSameLevelGather: false)
                break
            }
            if isSameOrShallowerItem(statement, level: level) {
                break
            }
            bodyStatements.append(statement)
            cursor += 1
        }
        return WeaveChoice(
            label: choiceOnlyLabel ?? body,
            weaveLabel: weaveLabel,
            echoesLabel: choiceOnlyLabel == nil,
            isSticky: isSticky,
            body: bodyStatements,
            nested: nested,
            condition: condition
        )
    }

    /// Parse a gather: its outcome prose, then the implicit sub-weave it opens.
    /// Plain prose immediately after the gather is its outcome body; once a choice
    /// (or deeper structure) appears, it opens a nested weave at the same level
    /// that terminates at the next same-or-shallower gather.
    private static func parseGather(
        _ header: InkStatement,
        _ statements: [InkStatement],
        cursor: inout Int,
        atLevel level: Int
    ) -> WeaveGather {
        guard case .gather(_, let label, let outcome) = header.kind else {
            fatalError("parseGather requires a gather statement")
        }
        var body: [InkStatement] = []
        if outcome.isEmpty == false {
            // A gather whose outcome is a divert (`- -> target`, parser bug #1)
            // lowers via the shared inline-body helper so the leading `->` becomes
            // a real divert, not literal text. Plain prose still lowers to `.text`.
            body.append(contentsOf: inlineBodyStatements(outcome, at: header.position))
        }
        while cursor < statements.count {
            let statement = statements[cursor]
            if isSameOrShallowerGather(statement, level: level) || isAnyChoice(statement) {
                break
            }
            body.append(statement)
            cursor += 1
        }
        var nested: WeaveBlock?
        if cursor < statements.count, isAnyChoice(statements[cursor]) {
            let block = parseBlock(statements, cursor: &cursor, atLevel: level, stopAtSameLevelGather: true)
            if block.items.isEmpty == false { nested = block }
        }
        return WeaveGather(label: label, body: body, nested: nested)
    }

    private static func isSameOrShallowerGather(_ statement: InkStatement, level: Int) -> Bool {
        if case .gather(let gatherLevel, _, _) = statement.kind { return gatherLevel <= level }
        return false
    }

    /// Lower a bracketed choice's inline outcome (`* [menu] body`) into body
    /// statements: any leading prose as text, plus a trailing inline divert
    /// (`-> target` / `-> END`) parsed as a divert/end so the choice diverts away
    /// rather than echoing the arrow as literal text. An empty body yields none.
    private static func inlineBodyStatements(_ body: String, at position: SourcePosition) -> [InkStatement] {
        guard body.isEmpty == false else { return [] }
        guard let arrowRange = body.range(of: "->") else {
            return [InkStatement(kind: .text(body), position: position)]
        }
        var statements: [InkStatement] = []
        let prose = String(body[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        if prose.isEmpty == false {
            statements.append(InkStatement(kind: .text(prose), position: position))
        }
        let target = String(body[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        let divertKind: InkStatementKind = target == "END" ? .end : .divert(target)
        statements.append(InkStatement(kind: divertKind, position: position))
        return statements
    }

    private static func appendTrailing(_ statement: InkStatement, to items: [WeaveItem]) -> [WeaveItem] {
        // A non-item statement appearing after items at this level, with the next
        // item being shallower, is trailing prose of the block's final gather.
        guard case .gather(let gather)? = items.last else { return items }
        var updated = items
        updated[updated.count - 1] = .gather(
            WeaveGather(label: gather.label, body: gather.body + [statement], nested: gather.nested)
        )
        return updated
    }

    private static func isDeeperChoice(_ statement: InkStatement, than level: Int) -> Bool {
        if case .choice(let choiceLevel, _, _, _, _, _) = statement.kind { return choiceLevel > level }
        return false
    }

    private static func isAnyChoice(_ statement: InkStatement) -> Bool {
        if case .choice = statement.kind { return true }
        return false
    }

    private static func isSameOrShallowerItem(_ statement: InkStatement, level: Int) -> Bool {
        if case .choice(let choiceLevel, _, _, _, _, _) = statement.kind { return choiceLevel <= level }
        if case .gather(let gatherLevel, _, _) = statement.kind { return gatherLevel <= level }
        return false
    }
}

// MARK: - Resolving the tree into the runtime container tree

/// Where a body's loose end falls when it does not divert away itself.
private enum FallThrough {
    /// Divert to a gather container at this qualified path.
    case gather([String])
    /// Terminate the story (top-level weave with no enclosing gather).
    case end
}

/// Lowers a `WeaveBlock` tree into runnable `(children, named)`. Owns the
/// `c-N`/`g-N` namespace; addresses are absolute-qualified from root via
/// `keyPrefix`. Loose ends stitch to the nearest gather at the current level or
/// fall through to the enclosing-level `fallThrough`.
private final class WeaveResolver {

    let lowerStatement: ([InkStatement]) -> [NodeKind]
    /// Lowers a choice's `{guard}` expression to POSTFIX eval-stack nodes, reusing
    /// the `RuntimeObjectEmitter.lowerExpression` idiom (composes with 02-03's dotted
    /// read-count operands). The resolver wraps the result in an `ev … /ev` block.
    let lowerCondition: (InkExpression) -> [NodeKind]

    /// The `label -> absolute compiled path` table written at the keying site as
    /// containers resolve (criterion 3): the same `keyPrefix + key` the container
    /// is addressed by, recorded for the labelled-only entries — never re-derived.
    private(set) var labelPaths: [String: [String]] = [:]

    init(
        lowerStatement: @escaping ([InkStatement]) -> [NodeKind],
        lowerCondition: @escaping (InkExpression) -> [NodeKind] = { _ in [] }
    ) {
        self.lowerStatement = lowerStatement
        self.lowerCondition = lowerCondition
    }

    func resolve(
        _ block: WeaveBlock,
        keyPrefix: [String],
        fallThrough: FallThrough
    ) throws -> (children: [NodeKind], named: [String: ContainerNode]) {
        let gathers = gatherKeys(block, keyPrefix: keyPrefix)
        var children = lowerStatement(block.lead)
        var named: [String: ContainerNode] = [:]

        // A block that LEADS with a gather (content above the first `*`, e.g. an
        // intro line) is reached by sequential flow, not a loose-end divert: after
        // the lead, flow diverts into that first gather, whose body + nested choices
        // and own loose-end carry the rest of the weave. Without this entry divert a
        // leading gather only lands in `named` and is never entered (start.children
        // would be just `done`). A block that leads with a CHOICE keeps offering the
        // choicePoints inline (the existing path below).
        if case .gather? = block.items.first, let firstGather = gathers.first {
            children.append(.divert(
                target: firstGather.path.joined(separator: "."), isConditional: false, isVariable: false
            ))
        }

        var choiceOrdinal = 0
        var gatherOrdinal = 0
        for (position, item) in block.items.enumerated() {
            switch item {
            case .choice(let choice):
                let key = choiceKey(choice, ordinal: choiceOrdinal)
                recordLabelPath(choice.weaveLabel, keyPrefix: keyPrefix, key: key)
                children.append(contentsOf: choicePointNodes(choice, target: qualified(keyPrefix, key)))
                named[key] = try outcomeContainer(
                    choice,
                    key: key,
                    keyPrefix: keyPrefix + [key],
                    looseEnd: looseEnd(after: position, in: gathers, fallThrough: fallThrough)
                )
                choiceOrdinal += 1
            case .gather(let gather):
                let key = gatherKey(gather, ordinal: gatherOrdinal)
                recordLabelPath(gather.label, keyPrefix: keyPrefix, key: key)
                named[key] = try gatherContainer(
                    gather,
                    key: key,
                    keyPrefix: keyPrefix,
                    looseEnd: nextGatherFallThrough(after: gatherOrdinal, in: gathers, fallThrough: fallThrough)
                )
                gatherOrdinal += 1
            }
        }
        children.append(.controlCommand("done"))
        return (children, named)
    }

    /// Record a labelled container's absolute path into the label table, reusing
    /// the already-computed `keyPrefix`/`key` the container is keyed by — never
    /// re-deriving the path (criterion 3). Unlabelled `c-N`/`g-N` keys pass a `nil`
    /// label and are not registered (criterion 5).
    private func recordLabelPath(_ label: String?, keyPrefix: [String], key: String) {
        guard let label else { return }
        labelPaths[label] = qualified(keyPrefix, key)
    }

    /// A gather's namedContent key: its `(label)` when present, else `g-N`.
    private func gatherKey(_ gather: WeaveGather, ordinal: Int) -> String {
        gather.label ?? "g-\(ordinal)"
    }

    /// A choice outcome container's namedContent key: its `(label)` when present,
    /// else `c-N`. The identical `label ?? default` idiom as `gatherKey`; the
    /// labelled name becomes the addressable segment in the absolute path.
    private func choiceKey(_ choice: WeaveChoice, ordinal: Int) -> String {
        choice.weaveLabel ?? "c-\(ordinal)"
    }

    // MARK: Choice lowering

    private func choicePointNodes(_ choice: WeaveChoice, target: [String]) -> [NodeKind] {
        // Choice-text eval block first (leaves the menu string on the eval stack),
        // then — for a `{guard}`-carrying choice — the guard eval block (leaves a
        // boolean on top). The runtime pops the condition bool first, then the
        // choice-text string, so this order matches inklecate (criterion 3).
        var nodes: [NodeKind] = [
            .controlCommand("ev"), .controlCommand("str"), .text(choice.label),
            .controlCommand("/str"), .controlCommand("/ev"),
        ]
        if let condition = choice.condition {
            nodes.append(.controlCommand("ev"))
            nodes.append(contentsOf: lowerCondition(condition))
            nodes.append(.controlCommand("/ev"))
        }
        nodes.append(.choicePoint(target: target.joined(separator: "."), flags: flags(for: choice)))
        return nodes
    }

    private func flags(for choice: WeaveChoice) -> ChoiceFlags {
        var flags = choice.echoesLabel ? ChoiceFlagTemplate.plain : ChoiceFlagTemplate.bracketed
        // Sticky choices clear the once-only bit so they remain selectable on repeat.
        if choice.isSticky { flags.remove(.isOnceOnly) }
        // A `{guard}`-carrying choice sets hasCondition so the runtime pops the
        // boolean the guard eval block left and skips the choice when false.
        if choice.condition != nil { flags.insert(.hasCondition) }
        return flags
    }

    /// A choice's outcome container: optional label echo, the body prose, the
    /// nested weave (when present), and — unless the body already diverts away —
    /// a fall-through divert to the resolved loose-end target.
    private func outcomeContainer(
        _ choice: WeaveChoice,
        key: String,
        keyPrefix: [String],
        looseEnd: FallThrough
    ) throws -> ContainerNode {
        var lead: [NodeKind] = []
        if choice.echoesLabel {
            lead.append(.text(choice.label))
            lead.append(.newline)
        }
        lead.append(contentsOf: lowerStatement(choice.body))
        return try containerSpliced(
            lead: lead, body: choice.body, nested: choice.nested,
            key: key, nestedKeyPrefix: keyPrefix, looseEnd: looseEnd
        )
    }

    // MARK: Gather lowering

    /// A gather's container: its outcome prose, the implicit sub-weave it opens
    /// (choices following it, whose loose ends fall through to the gather's own
    /// loose end), and — when neither the prose nor a nested choice diverts away —
    /// a fall-through divert to the loose-end target.
    private func gatherContainer(
        _ gather: WeaveGather,
        key: String,
        keyPrefix: [String],
        looseEnd: FallThrough
    ) throws -> ContainerNode {
        try containerSpliced(
            lead: lowerStatement(gather.body), body: gather.body, nested: gather.nested,
            key: key, nestedKeyPrefix: keyPrefix + [key], looseEnd: looseEnd
        )
    }

    /// Build an outcome/gather container from its already-lowered `lead` prose:
    /// when a nested weave is present, resolve it (under `nestedKeyPrefix`) and
    /// splice its de-`done`d children plus contributed named content; otherwise,
    /// unless `body` already diverts away, append the loose-end fall-through.
    private func containerSpliced(
        lead: [NodeKind],
        body: [InkStatement],
        nested: WeaveBlock?,
        key: String,
        nestedKeyPrefix: [String],
        looseEnd: FallThrough
    ) throws -> ContainerNode {
        var children = lead
        var named: [String: ContainerNode] = [:]
        if let nested {
            let resolved = try resolve(nested, keyPrefix: nestedKeyPrefix, fallThrough: looseEnd)
            children.append(contentsOf: stripDone(resolved.children))
            named = resolved.named
        } else if endsWithDivert(body) == false {
            children.append(contentsOf: fallThroughNodes(looseEnd))
        }
        return ContainerNode(children: children, namedContent: named, flags: 0, name: key)
    }

    // MARK: Loose-end resolution

    /// Absolute-qualified paths of every gather declared in this block, in order,
    /// each tagged with the level item-position it sits at.
    private func gatherKeys(_ block: WeaveBlock, keyPrefix: [String]) -> [(position: Int, path: [String])] {
        var keys: [(position: Int, path: [String])] = []
        var ordinal = 0
        for (position, item) in block.items.enumerated() {
            guard case .gather(let gather) = item else { continue }
            keys.append((position, qualified(keyPrefix, gatherKey(gather, ordinal: ordinal))))
            ordinal += 1
        }
        return keys
    }

    /// The loose end for a choice at `position`: the nearest gather declared
    /// AFTER it in this block, else the enclosing-level fall-through.
    private func looseEnd(
        after position: Int,
        in gathers: [(position: Int, path: [String])],
        fallThrough: FallThrough
    ) -> FallThrough {
        for gather in gathers where gather.position > position {
            return .gather(gather.path)
        }
        return fallThrough
    }

    /// The loose end for the gather at ordinal `ordinal`: the next gather after
    /// it in this block, else the enclosing-level fall-through.
    private func nextGatherFallThrough(
        after ordinal: Int,
        in gathers: [(position: Int, path: [String])],
        fallThrough: FallThrough
    ) -> FallThrough {
        guard ordinal + 1 < gathers.count else { return fallThrough }
        return .gather(gathers[ordinal + 1].path)
    }

    private func fallThroughNodes(_ fallThrough: FallThrough) -> [NodeKind] {
        switch fallThrough {
        case .gather(let path):
            return [.divert(target: path.joined(separator: "."), isConditional: false, isVariable: false)]
        case .end:
            return [.controlCommand("end")]
        }
    }

    // MARK: Helpers

    private func qualified(_ prefix: [String], _ key: String) -> [String] {
        prefix + [key]
    }

    /// Drop the trailing `done` a nested resolve appends so the nested choice
    /// cluster splices cleanly into the parent outcome container.
    private func stripDone(_ nodes: [NodeKind]) -> [NodeKind] {
        guard case .controlCommand("done")? = nodes.last else { return nodes }
        return Array(nodes.dropLast())
    }

    private func endsWithDivert(_ statements: [InkStatement]) -> Bool {
        switch statements.last?.kind {
        case .divert, .end:
            return true
        default:
            return false
        }
    }
}

/// Choice-flag templates for the two weave choice shapes (SPIKE findings §5).
/// `hasChoiceOnlyContent`/`hasStartContent` are compile-time encodings the
/// runtime `ChoiceFlags` does not name, so they are folded in by raw value.
private enum ChoiceFlagTemplate {
    private static let hasStartContent = 0x2
    private static let hasChoiceOnlyContent = 0x4

    /// Bracketed `* [text] body` — the `[text]` is the menu label and is NOT
    /// echoed into the outcome body.
    static let bracketed = ChoiceFlags(rawValue: hasChoiceOnlyContent).union(.isOnceOnly)
    /// Plain `* text` — the text is both the menu label AND echoed into the body.
    static let plain = ChoiceFlags(rawValue: hasStartContent).union(.isOnceOnly)
}
