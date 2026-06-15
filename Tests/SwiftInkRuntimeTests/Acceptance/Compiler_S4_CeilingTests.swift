// @us-05 @real-io @kpi-1
//
// S4 / US-05 — compile the full supported ceiling: inline / block / switch-style
// conditionals, functions `=== f() ===` + inline calls `{f()}`, tunnels
// `-> k ->`, reference parameters `ref x`, and tags `#tag`
// (matrix rows 22-24, 29-35). Native compile plays identical to the inklecate
// oracle up to The Intercept ceiling.
//
// Driving port: InkCompiler.compile(source:). RED until DELIVER S4.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler S4 — Supported Ceiling (conditionals, functions, tunnels, ref params, tags)")
struct Compiler_S4_CeilingTests {

    @Test func `a story exercising the full supported ceiling compiles and plays, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-ceiling")

        #expect(result.native == result.oracle)
    }

    @Test func `inline function calls, tunnels and ref-param mutation match the oracle`() throws {
        // double(2) → 4 strength; tunnel detour runs then returns; raise(ref force)
        // mutates the caller's variable so "Force is now 3". The whole sequence
        // matching the oracle proves all four mechanisms compile correctly.
        let result = try CompilerOracle.compileAndPlay("compile-ceiling")

        #expect(result.native == result.oracle)
        #expect(result.oracle.contains { $0.contains("strength") })
        #expect(result.oracle.contains("Force is now 3."))
    }

    // End-to-end ceiling oracle: The Intercept is the comprehensive supported-set
    // story (existing fixture). It was DESCOPED (user-approved 2026-06-14) solely
    // because TheIntercept.ink line 86 uses a once-only variable-text form
    // `{|I rattle...|}` (matrix row 27), then outside the supported set.
    //
    // @us-04 @kpi-1 @kpi-2 (compiler-variable-text US-04 — distinct from this
    // file's @us-05 native-ink-compiler ceiling tests above).
    // This is the US-04 acceptance test for the `compiler-variable-text` feature.
    // Slices 01-03 lowered the variable-text forms (rows 25-27), so the line-86
    // once-only form `{|...|}` that originally caused the descope now compiles.
    //
    // STILL BLOCKED (slice-04 RED finding, 2026-06-15): re-enabling the trait
    // surfaced TWO compiler gaps unrelated to variable text — the 2026-06-14
    // descope premise (line-86 variable-text only) was FALSIFIED:
    //   1. `not` unary operator in conditions (e.g. `{not think:...}`) —
    //      DELIVERED in this feature (step 05-01, lowers to native `!`).
    //   2. dotted read-count references in conditions, e.g.
    //      `{harris_demands_component.cant_talk_right: ...}` → a `CNT?` node
    //      addressing a named WEAVE LABEL. Step 06-01 investigation found this
    //      needs a weave-label addressing subsystem (choice `(label)` +
    //      `{condition}` parsing, label-keyed containers, count-visits flagging,
    //      a name→path table) — out of scope for variable-text. USER-APPROVED
    //      DESCOPE to the `native-ink-compiler` feature (2026-06-15).
    // Trait stays `.disabled` until native-ink-compiler lands weave-label
    // read-count addressing; the AT genuinely fails and must NOT be weakened.
    @Test(.disabled("DEFERRED (native-ink-compiler weave-label slice, user decision 2026-06-15 'cut losses; alternative approach'): read-count addressing + CountVisits flagging + {condition} lowering + the gather-divert/empty-bracket parser fixes ALL landed and are oracle-green in isolation. The full TheIntercept e2e additionally needs variable-text {|...|} at a gather-lead position to thread back into the gather's nested choices (VariableTextEmitter + gather-lead continuation threading) plus likely further blockers past line 86 — a multi-subsystem effort to be designed as a follow-up, not chased per-blocker. The AT genuinely fails and is NOT weakened."))
    func `The Intercept compiles natively and plays identical to the inklecate oracle`() throws {
        let oracleJSON = try CompilerOracle.oracleJSON("TheIntercept")
        let interceptScript = [0, 2, 1, 0, 0, 1, 2, 0, 1, 0]

        let oracleLines = try CompilerOracle.play(
            Story(json: oracleJSON), choiceScript: interceptScript, maxLines: 100
        )

        let source = try CompilerOracle.source("TheIntercept")
        let nativeStory = Story(blueprint: try InkCompiler.compile(source: source))
        let nativeLines = try CompilerOracle.play(
            nativeStory, choiceScript: interceptScript, maxLines: 100
        )

        #expect(nativeLines == oracleLines)
    }

    // GAP-1 enabler (step 05-01): the expression Pratt parser gains a `not`
    // unary-prefix path that lowers to native postfix `!` — `not x` pushes the
    // operand then emits `.nativeFunction("!")`, matching inklecate's shape
    // (oracle fixture slice-bug-glue-after-choice: `{"VAR?":"tellme"},"!","/ev"`).
    // This unblocks ~50 `{not …}` conditions in TheIntercept (the `.disabled` AT
    // above stays disabled — GAP-2 dotted read-count addressing is still open).
    //
    // Authored crafter-side (no DISTILL AT covers this internal mechanism); the
    // port-level AT is the TheIntercept e2e re-run at step 04-01.

    @Test func `not unary operator lowers to native postfix bang after the operand`() throws {
        let plain = try InkExpressionParser.parse("not x")
        #expect(describeNotLowering(plain) == ["ev", "var:x", "fn:!", "out", "/ev"])

        // Parenthesised operand: the whole comparison is lowered before `!`.
        let parenthesised = try InkExpressionParser.parse("not (a == b)")
        #expect(describeNotLowering(parenthesised) == ["ev", "var:a", "var:b", "fn:==", "fn:!", "out", "/ev"])

        // Double `not` recurses: inner `!` then outer `!`.
        let doubled = try InkExpressionParser.parse("not not x")
        #expect(describeNotLowering(doubled) == ["ev", "var:x", "fn:!", "fn:!", "out", "/ev"])
    }

    // GAP-2 enabler (step 06-01): a dotted read-count reference to a NAMED target
    // inside a condition — e.g. `{some_knot.some_stitch: text}` — must lower to a
    // read-count node (`.readCount(path)`) addressing the resolved container, NOT a
    // `.variableReference("some_knot.some_stitch")` the runtime cannot resolve.
    //
    // RED finding (step 06-01): the tokenizer treats `.` as a word char, so
    // `a.b` lexes as one identifier and `lowerExpression`'s `.variableReference`
    // case emits `.variableReference("a.b")`. inklecate instead emits a `CNT?`
    // addressing the named target's container. This test pins the defect at the
    // emitter boundary: a dotted condition subject that names a knot.stitch target
    // present in the compiled tree must surface as a `.readCount`, never a
    // `.variableReference`.
    //
    // Authored crafter-side (no DISTILL AT covers this internal mechanism); the
    // port-level AT is the TheIntercept e2e re-run at step 04-01.
    //
    // SCOPE-GUARD (step 06-01, 2026-06-15): this test was authored in RED and
    // genuinely fails — but the failure surfaced a far larger gap than the
    // "RESOLUTION only" scoping assumed. A dotted read-count subject is rejected
    // at PARSE time (`.unexpectedToken("waiting.guard_post")`), and a correct,
    // execution-equivalent implementation additionally needs: (1) parser support
    // for `(label)` weave-labels AND `{condition}` guards on choice lines (both
    // missing from the AST `choice` case); (2) label-keyed choice outcome
    // containers in WeaveEmitter (today keyed `c-N`, addressable neither as divert
    // target nor read-count); (3) the count-visits flag (0x1) set on addressable
    // containers (no compiler-emitted knot/stitch/gather/choice container sets it,
    // so a resolved read-count would always evaluate 0); (4) a name→path table on
    // LoweringContext. This is multiple major weave subsystems — the SCOPE-GUARD
    // STOP condition. Disabled (not deleted) so the suite stays releasable and the
    // pending mechanism stays documented; re-enabled when the expanded-scope step
    // lands the resolver. Escalated to the orchestrator.
    @Test func `a dotted read-count reference to a named stitch lowers to a read-count node`() throws {
        let source = """
        -> waiting
        === waiting ===
        = guard_post
        The corridor is empty.
        {waiting.guard_post: He has been here before.}
        -> END
        """
        let blueprint = try InkCompiler.compile(source: source)

        let dottedReferences = variableReferenceNames(in: blueprint.root)
            .filter { $0.contains(".") }
        #expect(
            dottedReferences.isEmpty,
            "dotted read-count subject lowered as a variableReference: \(dottedReferences)"
        )
        #expect(
            containsReadCount(blueprint.root),
            "no .readCount node emitted for the dotted read-count subject"
        )
    }

    // 02-03 enabler B1 — PARSER: a dotted identifier parses to a single
    // `.variableReference("a.b")` atom (not an `unexpectedToken` throw), while a
    // plain identifier and a dotted comparison still parse unchanged.
    @Test func `parses a dotted identifier as a single variable reference`() throws {
        #expect(try InkExpressionParser.parse("waiting.guard_post")
            == .variableReference("waiting.guard_post"))
        // Plain identifier unchanged (no regression).
        #expect(try InkExpressionParser.parse("force") == .variableReference("force"))
        // Operator parsing around a dotted ref unchanged: `a.b > 1`.
        #expect(try InkExpressionParser.parse("a.b > 1")
            == .binary(op: ">", left: .variableReference("a.b"), right: .intLiteral(1)))
    }

    // 02-03 enabler B2 — RESOLUTION (knot.stitch): a dotted reference naming a
    // compiled knot.stitch lowers to `.readCount("knot.stitch")`, never a
    // surviving `.variableReference`.
    @Test func `a dotted reference to a knot stitch lowers to a read-count node`() throws {
        let source = """
        -> waiting
        === waiting ===
        = guard_post
        The corridor is empty.
        {waiting.guard_post: He has been here before.}
        -> END
        """
        let blueprint = try InkCompiler.compile(source: source)
        #expect(containsReadCount(blueprint.root))
        #expect(variableReferenceNames(in: blueprint.root).filter { $0.contains(".") }.isEmpty)
    }

    // 02-03 enabler B3 — RESOLUTION (weave label): a reference naming a weave
    // label (the `(door)` label on a root-level choice, registered by the 02-02
    // discovery pre-pass into `weaveLabelPaths`) resolves to `.readCount(<path>)`
    // via the weave-label table, never a surviving `.variableReference`.
    @Test func `a reference to a weave label lowers to a read-count node`() throws {
        let source = """
        + (door) Open the door.
        {door: It is already open.}
        -> END
        """
        let blueprint = try InkCompiler.compile(source: source)
        #expect(containsReadCount(blueprint.root))
        #expect(variableReferenceNames(in: blueprint.root).contains("door") == false)
    }

    // 02-03 enabler B4 — table MISS fall-through: a dotted name resolving to no
    // known knot/stitch/weave-label stays a `.variableReference` (a real
    // qualified variable, NOT an error and NOT a read-count).
    @Test func `an unknown dotted name falls through to a variable reference`() throws {
        let source = """
        VAR ship = 0
        {ship.engine: humming}
        -> END
        """
        let blueprint = try InkCompiler.compile(source: source)
        #expect(variableReferenceNames(in: blueprint.root).contains("ship.engine"))
    }

    // 03-01 enabler — COUNTVISITS FLAG (criteria 1 + 2): a read-count-referenced
    // weave label gets the 0x1 CountVisits flag on its outcome container, while an
    // unreferenced sibling label keeps flags = 0 (no over-flagging). Without the
    // flag the runtime never tracks the container's visits, so a resolved read-count
    // would always evaluate 0 and the playback diverges from the oracle.
    @Test func `the count-visits flag is set only on read-count-referenced weave labels`() throws {
        let source = """
        + (door) Open the door.
        {door: It is already open.}
        + (window) Open the window.
        -> END
        """
        let blueprint = try InkCompiler.compile(source: source)
        // `door` is referenced by `{door: …}` → flagged; `window` never referenced.
        #expect(flagsForLabel("door", in: blueprint.root) == 0x1,
                "referenced weave label `door` must carry the 0x1 CountVisits flag")
        #expect(flagsForLabel("window", in: blueprint.root) == 0,
                "unreferenced weave label `window` must keep flags = 0 (no over-flagging)")
    }

    // 03-01 enabler — COUNTVISITS FLAG on knot/stitch (criteria 1 + 2): a dotted
    // read-count reference to a knot.stitch flags exactly that stitch container,
    // while an unreferenced stitch in the same knot keeps flags = 0.
    @Test func `the count-visits flag is set only on read-count-referenced stitches`() throws {
        let source = """
        -> waiting
        === waiting ===
        = guard_post
        The corridor is empty.
        {waiting.guard_post: He has been here before.}
        -> idle
        = idle
        Nothing happens.
        -> END
        """
        let blueprint = try InkCompiler.compile(source: source)
        let waiting = blueprint.root.namedContent["waiting"]
        #expect(waiting?.namedContent["guard_post"]?.flags == 0x1,
                "referenced stitch `waiting.guard_post` must carry the 0x1 CountVisits flag")
        #expect(waiting?.namedContent["idle"]?.flags == 0,
                "unreferenced stitch `waiting.idle` must keep flags = 0")
    }

    // 03-01 enabler — {condition}-GUARDED CHOICE (criterion 3): a choice carrying a
    // `{condition}` guard lowers its guard expression onto the eval stack BEFORE its
    // choicePoint, and the choicePoint carries the hasCondition (0x1) flag so the
    // runtime pops the boolean to gate the choice. The guard eval block sits AFTER
    // the choice-text eval block (the runtime pops the condition bool first, then
    // the choice-text string).
    @Test func `a guarded choice lowers its condition before the choicePoint with the hasCondition flag`() throws {
        let source = """
        VAR ready = true
        + {ready} Proceed.
        -> END
        """
        let blueprint = try InkCompiler.compile(source: source)
        let (flags, conditionBeforeChoicePoint) = guardedChoiceLowering(in: blueprint.root, label: "Proceed.")
        #expect(flags?.contains(.hasCondition) == true,
                "a guarded choicePoint must carry the hasCondition flag")
        #expect(conditionBeforeChoicePoint,
                "the guard condition must be lowered onto the eval stack before the choicePoint")
    }
}

/// The flags of the namedContent outcome container keyed by a weave `label`,
/// searched anywhere in the tree (root or nested), or nil when not found.
private func flagsForLabel(_ label: String, in container: ContainerNode) -> Int? {
    if let found = container.namedContent[label] { return found.flags }
    for child in container.children {
        if case .container(let nested) = child, let found = flagsForLabel(label, in: nested) {
            return found
        }
    }
    for nested in container.namedContent.values {
        if let found = flagsForLabel(label, in: nested) { return found }
    }
    return nil
}

/// Find the choicePoint whose preceding choice text matches `label` and report
/// (its flags, whether a condition eval block was lowered between the choice-text
/// eval block and the choicePoint). Used to assert guarded-choice lowering order.
private func guardedChoiceLowering(
    in container: ContainerNode, label: String
) -> (flags: ChoiceFlags?, conditionBeforeChoicePoint: Bool) {
    let children = container.children
    for (index, child) in children.enumerated() {
        guard case .choicePoint(_, let flags) = child else { continue }
        guard precedingChoiceText(children, before: index) == label else { continue }
        // A condition eval block lowered before the choicePoint means there is a
        // second `/ev` between the choice-text `/ev` and the choicePoint.
        let evCloseCount = children[..<index].filter { node in
            if case .controlCommand("/ev") = node { return true }
            return false
        }.count
        return (flags, evCloseCount >= 2)
    }
    for nested in container.namedContent.values {
        let result = guardedChoiceLowering(in: nested, label: label)
        if result.flags != nil { return result }
    }
    return (nil, false)
}

/// The choice-text string pushed by the `str ^text /str` group immediately
/// preceding the choicePoint at `index` (scans backwards for the nearest text node).
private func precedingChoiceText(_ children: [NodeKind], before index: Int) -> String? {
    for node in children[..<index].reversed() {
        if case .text(let value) = node { return value }
    }
    return nil
}

/// Collect every `.variableReference` name anywhere in the container tree so the
/// dotted read-count assertion can prove no `a.b` identifier survived lowering.
private func variableReferenceNames(in container: ContainerNode) -> [String] {
    var names: [String] = []
    for child in container.children {
        switch child {
        case .variableReference(let name):
            names.append(name)
        case .container(let nested):
            names.append(contentsOf: variableReferenceNames(in: nested))
        default:
            break
        }
    }
    for nested in container.namedContent.values {
        names.append(contentsOf: variableReferenceNames(in: nested))
    }
    return names
}

/// True when any node in the container tree is a `.readCount` — the node the
/// dotted read-count subject must lower to.
private func containsReadCount(_ container: ContainerNode) -> Bool {
    for child in container.children {
        if case .readCount = child { return true }
        if case .container(let nested) = child, containsReadCount(nested) { return true }
    }
    return container.namedContent.values.contains(where: containsReadCount)
}

/// Render a lowered expression's nodes into intention-revealing tokens so the
/// postfix `not`→`!` order can be asserted (local to this enabler test).
private func describeNotLowering(_ expression: InkExpression) -> [String] {
    RuntimeObjectEmitter.lowerInlineExpression(expression).map { node in
        switch node {
        case .controlCommand(let command): return command
        case .nativeFunction(let symbol): return "fn:\(symbol)"
        case .variableReference(let name): return "var:\(name)"
        default: return "other"
        }
    }
}
