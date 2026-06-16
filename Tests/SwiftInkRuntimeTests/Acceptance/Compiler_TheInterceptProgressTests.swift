// DELIVER — native-compiler-emission-alignment, step 01-01 (PROBE-DRIVEN).
//
// Ratchet suite for the REAL TheIntercept playthrough. Synthetic minimal fixtures
// kept FALSE-GREENING (passing while the real story stayed broken — feature-delta.md
// `#4b … RE-DIAGNOSIS`), so this suite drives against the REAL TheIntercept along the
// canonical choice script, pinning the achieved oracle-matching line FLOOR (N).
//
// Each step ratchets N upward: native[0..<N] must equal oracle[0..<N], with N > 4
// (before this step native dead-ended at 4 lines entering the real `opts` gather).
// The floor only goes UP — a regression that drops below N reds the suite.
//
// Driving port: InkCompiler.compile(source:) → Story(blueprint:) → play along the
// canonical script. Execution-equivalence (D5 Level-1, ADR-012), example-based
// oracle per CLAUDE.md (OOP paradigm; PBT N/A; mutation disabled).

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — TheIntercept native playthrough progress ratchet")
struct Compiler_TheInterceptProgressTests {

    /// The canonical choice script the playback probe drives TheIntercept along.
    private static let script = [0, 2, 1, 0, 0, 1, 2, 0, 1, 0]

    /// The achieved oracle-matching line floor for this step. Native must match the
    /// oracle for at least the first `floor` lines. Step 01-04 resolves the
    /// post-`lift_up_cup` gather (TheIntercept.ink ~148), where native dead-ended
    /// after the `lift_up_cup` choice body. Three root causes, all in `Compiler/`:
    ///   1. FALL-THROUGH — an inline conditional `{took:lift|take}` MID-body (the
    ///      `lift_up_cup` body) routed flow into its `cond{N}-end` rejoin container,
    ///      but the body's loose-end fall-through divert was emitted (unreachable)
    ///      AFTER the dispatch instead of inside the rejoin. The enclosing
    ///      fall-through now threads into the rejoin so flow rejoins the gather.
    ///   2. READ-COUNT — a bare choice-label read-count conditional
    ///      (`{lift_up_cup:he|Harris}`) resolved as a plain variable (always false →
    ///      "Harris"). A bare label that is UNIQUE story-wide is now registered in the
    ///      read-count table so it lowers to `CNT?` of the label's container, matching
    ///      inklecate's local-scope by-name resolution → "he".
    ///   3. WEAVE-IN-CONTINUATION — choices trailing an inline-conditional line
    ///      (`… begins{forceful<=0:,sternly}.` then `[Agree]/[Disagree]/…`) flattened
    ///      into the rejoin as literal prose. The rejoin now routes a weave-bearing
    ///      continuation through the WeaveEmitter (real choicePoints), nesting its
    ///      containers under the rejoin's own scope to avoid sibling collisions.
    /// Step 01-05 resolves the gather-position multi-line block conditional at
    /// TheIntercept.ink ~159, where native split the gather line and echoed a literal
    /// "}". Two root causes, both in `Compiler/Parser/InkParser.swift`:
    ///   1. GATHER-OPENED BLOCK — a gather may itself OPEN a multi-line block
    ///      conditional (`-     { teacup:`). The opener detector only matched a line
    ///      whose first char was `{`, so the gather's outcome captured `{ teacup:`
    ///      and the block body (`~ drugged = true`, the glue+text, the bare `}`)
    ///      leaked as separate statements — the `}` echoed as literal text. The
    ///      detector now strips a leading gather-marker run, emits the gather header
    ///      (empty outcome), and parses the block into the gather's body.
    ///   2. LEADING GLUE — a content line LEADING with `<>` (the block body
    ///      `<>, sipping…` and the post-block `<>.`) lowered the `<>` as literal
    ///      text. `appendContent` now emits leading glue and re-lowers the remainder,
    ///      so the block's continuation joins the gather line on one output line,
    ///      matching inklecate's "…I reply, sipping at my tea…".
    /// Step 01-06 resolves two coupled defects at the post-teacup weave (ink ~159-174),
    /// advancing native 17 → 19 oracle-matching lines. Both fixes are in `Compiler/`:
    ///   1. BLOCK-CONDITIONAL FALL-THROUGH — a block conditional (`-  { teacup: … }`
    ///      then `<>.`) at the TAIL of a gather body rejoined its `cond{N}-end`
    ///      continuation container, but that container ended without diverting onward;
    ///      the gather's loose-end divert (`-> g-5`) was emitted (unreachable) AFTER
    ///      the conditional dispatch. `ConditionalEmitter.lower` now threads the
    ///      enclosing-scope fall-through into the `-end` rejoin (symmetric with
    ///      `lowerInline`), so flow rejoins the gather and the `[Watch him]`/`[Wait]`/
    ///      `{not disagree}[Smile]` choice menu is presented.
    ///   2. READ-COUNT PATH RECONCILIATION — the `{not disagree}` guard on `[Smile]`
    ///      read `start.waited.disagree`, but the `(disagree)` choice trails an
    ///      inline-conditional gather lead and physically compiles to
    ///      `start.waited.cond2-end.cond0-end.disagree`. The discovery pre-pass
    ///      predicts the flat path; a post-lowering pass reconciles each dangling
    ///      `.readCount` key to the unique real container ending in that label within
    ///      the same knot, so `not disagree` reads the true count (1) and suppresses
    ///      `[Smile]` — matching the oracle's 2-choice menu.
    /// Step 01-07 threads the TUNNEL CHAIN `-> missing_reel -> harris_demands_component`
    /// (TheIntercept.ink line 182 inside the `{not missing_reel:}` block conditional,
    /// and line 195 at the gather loose end), advancing native 19 → 22 oracle-matching
    /// lines. A chain `-> A -> B` means: tunnel-call A; on the knot's `->->` return,
    /// continue to B — inklecate lowers it to adjacent `{"->t->":A},{"->":B}`. Two
    /// coordinated fixes, both in `Compiler/`:
    ///   1. PARSER CHAIN SPLIT — `InkParser.divertStatements` recognises a leading-`->`
    ///      line carrying ≥2 named hops (`-> A -> B`) and emits `tunnelDivert(A)` +
    ///      `divert(B)`, rather than a single broken `divert("A -> B")`. The standalone
    ///      statement path (and, via `appendStatements`, the block-conditional branch
    ///      body at line 182) now thread the chain. A bare divert / `-> END` / single
    ///      tunnel `-> k ->` is untouched (one statement).
    ///   2. GATHER-OUTCOME CHAIN — `WeaveEmitter.inlineBodyStatements` routes a
    ///      bare-divert gather outcome whose target itself contains `->` (the line-195
    ///      `-> missing_reel -> harris_demands_component` loose end) through the same
    ///      `divertStatements` recogniser, so the gather's loose-end chain lowers
    ///      identically.
    /// Step 01-08 resolves the TUNNEL-RETURN gather loose-end, advancing native
    /// 22 → 29 oracle-matching lines. The `missing_reel` knot's loose end
    /// (TheIntercept.ink ~211, `-    ->->`) is a tunnel RETURN: pop the tunnel stack
    /// and resume at the call site so flow continues to `harris_demands_component`.
    /// The fix is in `WeaveEmitter.inlineBodyStatements` (gather/choice outcome
    /// lowering): a bare `->->` outcome now lowers to `.tunnelReturn` (runtime
    /// `->->`), matching the main-statement path. Previously the arrow-split treated
    /// `->->` as a divert whose target was itself `->`, yielding an empty
    /// `tunnelDivert("")` that restarted the story at its top — hence native played
    /// `start.g-0`'s "They are keeping me waiting." instead of returning to
    /// `harris_demands_component`'s "So. Do you have it?".
    /// Step 01-09 resolves the BLOCK-CONDITIONAL-OPENED WEAVE, advancing native
    /// 29 → 40 oracle-matching lines. The `admitted_to_something` knot (ink ~380)
    /// OPENS with a multi-line block conditional (`{ not drugged: … - else: … }`),
    /// then presents a guarded choice menu (`[Explain]` then nested `[Explain]` /
    /// `{drugged}[Say nothing]` / `{not drugged}[Lie]`; outer `{not drugged}[Don't
    /// explain]/[Lie]/[Evade]`, `{drugged}[Say nothing]`). The block conditional's
    /// `cond{N}-end` rejoin flattened those trailing choices into literal prose —
    /// the menu was never presented and native fell straight through to the first
    /// body (`i_know_where`'s "There's nothing to explain…"). Two coordinated fixes,
    /// both in `Compiler/`:
    ///   1. BLOCK-REJOIN WEAVE ROUTING — `ConditionalEmitter.lower` /
    ///      `registerContinuation` gained the `lowerContinuation` weave-routing path
    ///      that `lowerInline` already had (step 01-04): a weave-bearing rejoin now
    ///      routes through the WeaveEmitter so the trailing choices become real
    ///      choicePoints whose `c-N`/`g-N` containers nest under the `-end` rejoin.
    ///      `RuntimeObjectEmitter.lowerBody` threads its
    ///      `inlineConditionalContinuationLowerer` into the block-conditional call.
    ///   2. REJOIN CHOICE GUARDS — both continuation lowerers
    ///      (`inlineConditionalContinuationLowerer`, `continuationLowerer`) now pass
    ///      `lowerCondition` to `WeaveEmitter.lower`, so the rejoin weave's `{cond}`
    ///      choice guards emit their eval-stack nodes. Without it every choice
    ///      lowered unguarded (all shown), so native offered `{not drugged}` choices
    ///      on the drugged path and picked the wrong nested branch.
    /// The NEXT blocker is at index 40 (`harris_has_seen_it_before`, ink ~440+):
    /// native splits a glue-joined line — NATIVE[40] = "Smart man," he replies.
    /// "You wouldn't last. (then NATIVE[41] = "<> So why don't you tell me…")
    /// where ORACLE[40] joins them: "…You wouldn't last. So why don't you tell me,
    /// right now. Where is it?" — a `<>` leading-glue line-join defect for the
    /// next step.
    private static let floor = 40

    @Test
    func `native TheIntercept plays past the opts gather, matching the oracle prefix`() throws {
        let result = try CompilerOracle.compileAndPlay("TheIntercept", choiceScript: Self.script)
        #expect(
            result.native.count >= Self.floor,
            "native played only \(result.native.count) lines; expected at least \(Self.floor)"
        )
        #expect(
            Array(result.oracle.prefix(Self.floor)) == Array(result.native.prefix(Self.floor)),
            "native diverged from the oracle within the first \(Self.floor) lines"
        )
    }
}
