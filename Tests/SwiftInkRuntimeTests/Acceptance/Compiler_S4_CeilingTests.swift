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
    @Test(.disabled("DEFERRED to native-ink-compiler (user-approved descope 2026-06-15): TheIntercept native compile needs weave-label read-count addressing. not-unary was delivered here (05-01); only the weave-label subsystem remains. The AT genuinely fails and is not weakened."))
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
    @Test(.disabled("pending step 06-01 expanded scope (escalated): dotted read-count addressing needs choice (label)+{condition} parsing, label-keyed choice containers, count-visits flagging, and a name→path table — multiple weave subsystems missing; SCOPE-GUARD STOP"))
    func `a dotted read-count reference to a named stitch lowers to a read-count node`() throws {
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
