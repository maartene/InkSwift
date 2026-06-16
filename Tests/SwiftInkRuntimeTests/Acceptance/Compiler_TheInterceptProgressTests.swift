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
    /// Step 01-10 resolves the GATHER-LEAD LEADING-GLUE line-join, advancing native
    /// 40 → 55 oracle-matching lines. The `tell_me_now` gather (`harris_has_seen_it_before`,
    /// TheIntercept.ink ~481, `- (tell_me_now) <> So why don't you tell me…`) has an
    /// outcome LEADING with `<>`. The choice bodies above it (`[Agree]` etc.) fall
    /// through into the gather, so its leading glue must join the gather's content onto
    /// the previous output line. `WeaveEmitter.inlineBodyStatements` lowered the whole
    /// outcome as one `.text("<> So why…")`, echoing the marker as literal text and
    /// starting a new line — `outcomeStatement` (unlike `appendContent`, step 01-05)
    /// never split a LEADING marker. The fix adds a leading-`<>` branch to
    /// `inlineBodyStatements` (symmetric with its trailing-`<>` branch): emit `.glue`
    /// first, then the remainder VERBATIM (the source space after `<>` is literal
    /// content inklecate preserves — oracle text node `^ So why…`, so trimming would
    /// yield `last.So` instead of the oracle's `last. So`). The fix is in `Compiler/`.
    /// Step 01-11 resolves the BLOCK-CONDITIONAL-AT-GATHER-POSITION + bare read-count,
    /// advancing native 55 → 63 oracle-matching lines. The `paused` gather
    /// (`i_met_a_young_man`, TheIntercept.ink ~542) OPENS with a block conditional
    /// `{ not nope: That gives me pause… }` then presents a `[Yes]/[No]/[Tell the
    /// truth]/[Lie]` menu. Native both SKIPPED the true-branch line (ORACLE[55]) and
    /// dead-ended after the gather prose (the menu was never offered). Two coordinated
    /// fixes, both in `Compiler/`:
    ///   1. BARE READ-COUNT LOCAL SCOPE — `{ not nope }`'s `nope` is a choice LABEL,
    ///      but `nope` is not unique story-wide (also a label in `harris_demands_component`),
    ///      so `mergeUniqueBareLabels` left it dotted-only and the subject lowered as a
    ///      plain `.variableReference nope` (undefined → wrong truth value). `LoweringContext.readCountPath`
    ///      now resolves a bare subject in LOCAL knot scope FIRST (`knot.label` against
    ///      `weaveLabelPaths`), symmetric with `qualifiedDivertTarget`'s by-name weave
    ///      resolution — so `nope` lowers to `.readCount i_met_a_young_man.g-1.nope`.
    ///   2. GATHER-CONDITIONAL-THEN-CHOICES ROUTING — a gather whose body opens/contains
    ///      a block conditional and is followed by nested choices diverts away into the
    ///      conditional's `cond{N}-end` continuation; splicing the choices INLINE after
    ///      the dispatch left them unreachable. `WeaveEmitter.gatherWithConditionalThenChoices`
    ///      now resolves the nested choices into a named rejoin sub-container (`<key>-w`)
    ///      and lowers the body with its fall-through pointing AT that rejoin, so the
    ///      continuation diverts into the choice menu.
    /// Step 01-12 resolves the GUARDED-IF/ELSE-MISREAD-AS-SWITCH defect at the
    /// `harris_believes` stitch (`reveal_location_of_component`, TheIntercept.ink ~1604),
    /// advancing native 63 → 73 oracle-matching lines. The block conditional
    /// `{ not night_falls.hooper_didnt_give_himself_up : …God help you… - else: …double
    /// bluff… }` is a GUARDED if/else: content ("God help you") follows `{ subject:`
    /// directly as the implicit first arm, the subject IS that arm's guard. The fix is
    /// in `Compiler/Parser/InkParser.swift`:
    ///   - SWITCH-VS-GUARDED STRUCTURAL DISCRIMINATION — `switchOrGuardedBlock`
    ///     classified any subject lacking a comparison operator as a switch value
    ///     (`subjectIsSwitchValue` only scanned for `> < == != >= <=`). A boolean
    ///     subject like `not knot.label` therefore became a (bogus) switch, so the
    ///     pre-arm "God help you" content — emitted before `armStarted` — and the
    ///     condition itself were DROPPED; native hardcoded an unconditional jump to
    ///     the `- else:` branch ("double bluff"). A real switch opens DIRECTLY with
    ///     `- guard:` arms (`{ x: - 1: … - 2: … }`) with no pre-arm content; a guarded
    ///     if/else carries content right after `{ subject:`. The classifier now also
    ///     requires the block's FIRST body line to be an arm opener (`opensWithArm`)
    ///     before treating it as a switch — so the guarded if/else keeps its subject
    ///     as the implicit first-arm guard, lowering `not night_falls.hooper_…` to the
    ///     real `CNT?` read-count (0 in this playthrough → "God help you").
    /// The NEXT blocker is at index 73 (TheIntercept.ink ~1661): native and oracle
    /// diverge on the inline conditional `{ forceful > 2:…|A little vengeance, disguised
    /// as doing something good.}` — native picks a different branch than the oracle (a
    /// `forceful` operand evaluation defect) for a later step.
    private static let floor = 73

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
