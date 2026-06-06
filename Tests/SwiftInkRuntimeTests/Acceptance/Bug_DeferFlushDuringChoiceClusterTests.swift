// @real-io
// Regression test for the line-28 Intercept follow-on bug.
//
// Trigger: a buffered line (from a preceding multi-line `{cond: a - else: b}`
// gather body) sits in `outputStream` when a choice cluster begins. After
// the first choicePoint is collected, the engine processes the next
// choice's preceding `ev/.../ev` block and at the `/ev` boundary flushes
// the buffered line — returning early from `stepToNextLine`. The caller
// then sees `canContinue == false` (because `currentChoices` is non-empty)
// and stops calling `continue()`, so the subsequent choicePoints in the
// cluster are NEVER visited. Result: the second choice (with a `{var}`
// condition that should evaluate true) appears MISSING.
//
// Fix: `stepToNextLine` defers all flushes once `state.currentChoices`
// becomes non-empty, matching the C# runtime's behaviour where `Continue()`
// keeps stepping through choicePoints until the container exhausts.
//
// See `distill/upstream-issues.md` Issue 5 #3 and the commit titled
// `fix(engine): defer flush across multi-choice cluster collection`.

import Testing
import Foundation
@testable import SwiftInkRuntime
#if os(macOS)
import InkSwift
#endif

@Suite("Bug — defer flush across a multi-choice cluster")
struct Bug_DeferFlushDuringChoiceClusterTests {

    private func loadJSON() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "slice-bug-conditional-choice-cluster", withExtension: "ink.json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // After the preceding `{not drugged: A. - else: B.}` gather body (which
    // emits "B." because drugged is true), the engine reaches the choice
    // cluster. Both [Always] (no condition) AND [Only if drugged] (gated by
    // `{drugged}`, which IS true) must appear in `currentChoices`.
    @Test func `both choices visible when preceded by multi-line conditional gather with text in between`() throws {
        let story = try Story(json: try loadJSON())
        while story.canContinue { _ = story.`continue`() }
        #expect(story.currentChoices.map { $0.text } == ["Always", "Only if drugged"])
    }

    // Cross-check against the JS-bridge oracle to confirm the expected
    // choice list above is faithful to the Ink spec rather than the author's
    // assumption.
    #if os(macOS)
    @Test func `native choice list matches JavaScript oracle`() throws {
        let json = try loadJSON()

        let native = try Story(json: json)
        while native.canContinue { _ = native.`continue`() }

        let oracle = InkStory()
        oracle.loadStory(json: json)
        while oracle.canContinue { _ = oracle.continueStory() }

        #expect(native.currentChoices.map { $0.text } == oracle.options.map { $0.text })
    }
    #endif
}
