// @real-io
// Bug-fix regression test for the post-finalize Tier-3 divergence
// uncovered by TheInterceptNonTrivialPlaythroughTests.
//
// Reproducer: a choice whose text has no `[...]` brackets, immediately
// followed by a gather body that starts with `<>` glue. The JS-bridge
// oracle fuses the choice text with the glued gather body into ONE output
// line. The native engine (pre-fix) emits the glued line TWICE in a row.
//
// Driving port: Story facade — init(json:), continue(), chooseChoice(at:)
// Fixture:      slice-bug-glue-after-choice.ink.json (inklecate-compiled)
//
// See docs/feature/tier3-conditionals-and-tunnels/distill/upstream-issues.md
// Issue 5 for the divergence as observed in The Intercept.

import Testing
import Foundation
@testable import SwiftInkRuntime
#if os(macOS)
import InkSwift
#endif

@Suite("Bug — glue after choice does not duplicate the glued line")
struct Bug_GlueAfterChoiceTests {

    private func loadJSON() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "slice-bug-glue-after-choice", withExtension: "ink.json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // After picking choice 0 — `* [Deny] Denial body. -> pushes_cup` — the
    // engine must flow through the labeled depth-2 gather `pushes_cup` to
    // the depth-1 parent gather and continue. It must NOT loop back to the
    // depth-2 choice cluster and present the remaining once-only choice
    // ("Take a cup."), since the `*` choice that was just picked is
    // exhausted and the divert + labeled gather should advance past the
    // cluster.
    //
    // This is the structural pattern that breaks the non-trivial Intercept
    // playthrough at line 11: `* [Deny] ... -> pushes_cup` in the
    // `make_your_peace` / Harris-tea-cup scene.
    @Test func `bracketed once-only choice with divert to labeled gather advances past the cluster`() throws {
        let story = try Story(json: try loadJSON())
        var lines: [String] = []

        func drainContinues() {
            while story.canContinue {
                let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { lines.append(line) }
            }
        }

        drainContinues()
        try story.chooseChoice(at: 0)   // pick Deny
        drainContinues()

        // Story should END after the parent gather + "next line", with no
        // remaining choice point. If the engine loops back to the cluster,
        // `currentChoices` will be non-empty and the test fails before the
        // line-content assertion.
        #expect(story.currentChoices.isEmpty,
                "After picking [Deny] -> pushes_cup, engine looped back to remaining choices: \(story.currentChoices.map { $0.text })")

        // Picking [Deny] (choice 0 in the visible cluster:
        // [Deny, Take one, Wait] — `what2` is gated by `{not tellme}` and
        // tellme is true) must produce:
        //   1. "Opening line."
        //   2. "Two cups of tea on the table."
        //   3. "\"I'm not pretending anything.\""
        //   4. "Harris looks disapproving. He pushes one mug halfway towards me: a small gesture of friendship."
        //   5. "Enough to give me hope?"
        // — NOT loop back to ["Take one", "Wait"].
        #expect(lines == [
            "Opening line.",
            "Two cups of tea on the table.",
            "\"I'm not pretending anything.\"",
            "Harris looks disapproving. He pushes one mug halfway towards me: a small gesture of friendship.",
            "Enough to give me hope?"
        ])
    }

    // Cross-check against the JS-bridge oracle to confirm the expected
    // output above is faithful to the Ink spec rather than the author's
    // assumption.
    #if os(macOS)
    @Test func `native output matches JavaScript oracle for choice-glue-gather sequence`() throws {
        let json = try loadJSON()

        let native = try Story(json: json)
        var nativeLines: [String] = []
        func drainNative() {
            while native.canContinue {
                let line = native.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { nativeLines.append(line) }
            }
        }
        drainNative()
        try native.chooseChoice(at: 0)
        drainNative()

        let oracle = InkStory()
        oracle.loadStory(json: json)
        var oracleLines: [String] = []
        let initial = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !initial.isEmpty { oracleLines.append(initial) }
        func drainOracle() {
            while oracle.canContinue {
                let line = oracle.continueStory().trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { oracleLines.append(line) }
            }
        }
        drainOracle()
        oracle.chooseChoiceIndex(0)
        let afterPick = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !afterPick.isEmpty { oracleLines.append(afterPick) }
        drainOracle()

        #expect(nativeLines == oracleLines)
    }
    #endif
}
