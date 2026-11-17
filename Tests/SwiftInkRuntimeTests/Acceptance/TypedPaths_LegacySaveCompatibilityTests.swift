// @real-io
// Exercises: Story.saveState() and Story.restoreState(_:) against committed
// legacy save files (typed-runtime-paths, issue #25, ADR-018 / D4).
//
// GOLDEN PROVENANCE — never regenerate these files.
// Each golden is the verbatim output of the unmodified `Story.saveState()` at
// commit e7d0830 (main, before any typed-path change landed). They pin the
// string-encoded save format — `returnStack` entries ("path.N"),
// `stackFrames[].pathFromRoot`, and `visitCounts` / `chosenChoiceTargets`
// keyed by dotted path strings — so that saves made by the legacy build keep
// restoring after the refactor. A route is the sequence of choice indices taken
// from a fresh story, with `continueMaximally()` before each choice and once
// after the last; the save is taken at the choice point that follows.
//
//   legacy-save-mid-tunnel.json        TheIntercept.ink.json, route 0×10:
//       inside the `missing_reel` tunnel at the Panic/Calculate/Deny choice
//       point; returnStack = ["start.waited.0.g-6.2.4.b.2"].
//   legacy-save-once-only-chosen.json  slice01-once-only.ink.json, route [0]:
//       "Ask about the shop." taken; chosenChoiceTargets = ["0.0.c-0"].
//   legacy-save-visit-counts.json      slice03-read-counts.ink.json, route [0]:
//       café re-entered once; visitCounts["café"] = 2.
//   legacy-save-choice-point.json      TheIntercept.ink.json, route [0]:
//       top-level Think/Plan/Wait choice point with global variables set.
//
// Re-save normalisation (characterised, not designed): at a top-level choice
// point the engine's container stack is empty, so the save carries
// `stackFrames: []`. Restoring such a save takes the fallback in
// `InkEngine.rebuildContainerStack()`, which synthesises one frame from
// `pointer` (containerPath, index); the next save writes that frame out. So a
// re-save equals the golden except that an empty `stackFrames` becomes that
// single pointer-derived frame (visit-counts and choice-point goldens); goldens
// with frames re-save verbatim. Either way one round reaches a fixed point.
//
// A function-return frame ("fnret:path|N") cannot be captured here: ink allows
// no choices inside a function, and a save is only taken between continue()
// calls, so no golden can hold one. That wire form is covered by the step
// 02-06 codec round-trip tests instead.

import Testing
import Foundation
@testable import SwiftInkRuntime

/// One committed legacy save, the story it came from, and how to reach and
/// continue past it.
struct LegacySaveGolden: Sendable, CustomTestStringConvertible {
    let goldenName: String
    let storyName: String
    /// Choice indices taken from a fresh story to reach the saved choice point.
    let route: [Int]
    /// Choice indices taken after the save point; each must reach a later
    /// choice point or the end, so the comparison covers resumed flow.
    let continuation: [Int]
    /// Top-level save key that must be non-empty for the golden to pin the
    /// state it is named for.
    let pinnedStateKey: String

    var testDescription: String { goldenName }
}

private let legacySaveGoldens: [LegacySaveGolden] = [
    LegacySaveGolden(goldenName: "legacy-save-mid-tunnel", storyName: "TheIntercept",
                     route: Array(repeating: 0, count: 10), continuation: [0, 0, 0],
                     pinnedStateKey: "returnStack"),
    LegacySaveGolden(goldenName: "legacy-save-once-only-chosen", storyName: "slice01-once-only",
                     route: [0], continuation: [0, 0],
                     pinnedStateKey: "chosenChoiceTargets"),
    LegacySaveGolden(goldenName: "legacy-save-visit-counts", storyName: "slice03-read-counts",
                     route: [0], continuation: [0, 1],
                     pinnedStateKey: "visitCounts"),
    LegacySaveGolden(goldenName: "legacy-save-choice-point", storyName: "TheIntercept",
                     route: [0], continuation: [1, 0, 0],
                     pinnedStateKey: "currentChoices"),
]

@Suite struct TypedPaths_LegacySaveCompatibilityTests {

    private func freshStory(_ name: String) throws -> Story {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func goldenData(_ golden: LegacySaveGolden) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: golden.goldenName, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func canonicalJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func choiceLine(_ story: Story) -> String {
        "choices: " + story.currentChoices.map(\.text).joined(separator: " | ")
    }

    /// Takes each pick from the story's current choice point, recording the
    /// produced text and the following choices.
    private func transcript(of story: Story, picking continuation: [Int]) throws -> [String] {
        var lines = [choiceLine(story)]
        for pick in continuation {
            try story.chooseChoice(at: pick)
            lines.append("text: " + story.continueMaximally())
            lines.append(choiceLine(story))
        }
        return lines
    }

    private func play(_ story: Story, route: [Int]) throws {
        for pick in route {
            _ = story.continueMaximally()
            try story.chooseChoice(at: pick)
        }
        _ = story.continueMaximally()
    }

    // GIVEN: a legacy golden save
    // WHEN: its JSON is inspected
    // THEN: it holds the state it is named for (e.g. a non-empty return stack)

    @Test(arguments: legacySaveGoldens)
    func `each legacy golden save holds the state it is named for`(golden: LegacySaveGolden) throws {
        let object = try JSONSerialization.jsonObject(with: goldenData(golden))
        let save = try #require(object as? [String: Any])
        let pinned = save[golden.pinnedStateKey]
        let count = (pinned as? [Any])?.count ?? (pinned as? [String: Any])?.count ?? 0
        #expect(count > 0, "\(golden.goldenName): \(golden.pinnedStateKey) is empty")
    }

    // GIVEN: a legacy golden save and the route that produced it
    // WHEN: the golden is restored into a fresh story and play continues
    // THEN: text and choices match the uninterrupted playthrough from that point

    @Test(arguments: legacySaveGoldens)
    func `restoring a legacy golden save continues exactly like the uninterrupted playthrough`(
        golden: LegacySaveGolden
    ) throws {
        let uninterrupted = try freshStory(golden.storyName)
        try play(uninterrupted, route: golden.route)
        let expected = try transcript(of: uninterrupted, picking: golden.continuation)

        let restored = try freshStory(golden.storyName)
        try restored.restoreState(goldenData(golden))
        let actual = try transcript(of: restored, picking: golden.continuation)

        #expect(actual == expected)
        #expect(expected.count == 1 + 2 * golden.continuation.count)
    }

    /// The canonical JSON a re-save of `golden` must produce: the golden
    /// itself, with an empty `stackFrames` replaced by the single frame the
    /// restore fallback derives from `pointer` (see the file header).
    private func expectedResave(of golden: LegacySaveGolden) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: goldenData(golden))
        var save = try #require(object as? [String: Any])
        let frames = try #require(save["stackFrames"] as? [Any])
        if frames.isEmpty {
            let pointer = try #require(save["pointer"] as? [String: Any])
            save["stackFrames"] = [[
                "pathFromRoot": try #require(pointer["containerPath"]),
                "executionIndex": try #require(pointer["index"]),
                "isChoiceContinuationRoot": false,
            ]]
        }
        return try JSONSerialization.data(withJSONObject: save, options: [.sortedKeys])
    }

    private func restoreAndResave(_ data: Data, into storyName: String) throws -> Data {
        let story = try freshStory(storyName)
        try story.restoreState(data)
        return try story.saveState()
    }

    // GIVEN: a legacy golden save restored into a fresh story
    // WHEN: the story is saved again immediately
    // THEN: the canonical (sorted-key) JSON is byte-identical to the golden's,
    //       modulo the documented empty-stackFrames normalisation

    @Test(arguments: legacySaveGoldens)
    func `re-saving a restored legacy golden reproduces its canonical JSON`(golden: LegacySaveGolden) throws {
        let resaved = try restoreAndResave(goldenData(golden), into: golden.storyName)

        #expect(try canonicalJSON(resaved) == expectedResave(of: golden))
    }

    // GIVEN: a re-save of a restored legacy golden
    // WHEN: it is restored and saved once more
    // THEN: the canonical JSON is unchanged (save/restore is a fixed point)

    @Test(arguments: legacySaveGoldens)
    func `a second restore and re-save of a legacy golden is a fixed point`(golden: LegacySaveGolden) throws {
        let first = try restoreAndResave(goldenData(golden), into: golden.storyName)
        let second = try restoreAndResave(first, into: golden.storyName)

        #expect(try canonicalJSON(second) == canonicalJSON(first))
    }
}
