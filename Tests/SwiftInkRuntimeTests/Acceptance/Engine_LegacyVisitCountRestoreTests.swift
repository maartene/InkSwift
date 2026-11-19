// @real-io
// Issue #33 — old saves restore with split visit counts merged
// (ADR-022 §4, reference-fidelity-backlog step 01-06).
//
// Before canonical keys, one container could be counted under two spellings,
// its index and its name. `legacy-save-split-visit-counts.json` is such a save
// (provenance in the header of Engine_CanonicalVisitCountTests.swift): the
// labelled gather of issue33-loop-with-choice holds 1 under `0.0` and 1 under
// `0.loop`, and the stopping sequence inside it likewise. Restoring converts
// every key to its canonical path through the loaded story's tree and sums the
// split counts, so the save resumes as the uninterrupted inklecate playthrough
// does. Saves are forward-only from here: a re-save writes canonical keys only.
//
// Driving port: Story(json:), restoreState(_:), continueMaximally(),
// chooseChoice(at:), saveState(). Expected text is `inklecate -p` output on
// issue33-loop-with-choice.ink, route 1, 1, 1, 1, from the save point on.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct Engine_LegacyVisitCountRestoreTests {

    private func story() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "issue33-loop-with-choice", withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func goldenSave() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "legacy-save-split-visit-counts", withExtension: "json"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func restored(_ save: [String: Any]) throws -> Story {
        let story = try story()
        try story.restoreState(JSONSerialization.data(withJSONObject: save))
        return story
    }

    private func visitCounts(in data: Data) throws -> [String: Int] {
        let save = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(save["visitCounts"] as? [String: Int])
    }

    // GIVEN: the legacy save with the gather and its sequence each split over two spellings
    // WHEN: it is restored and saved again
    // THEN: each container has one canonical key holding the sum of its split counts

    @Test func `an old save's split visit counts are merged under one canonical key`() throws {
        let story = try restored(goldenSave())

        #expect(try visitCounts(in: story.saveState()) == ["0.loop": 2, "0.loop.0": 2])
    }

    // GIVEN: the legacy save taken at the second pass's Go round / Leave choice point
    // WHEN: the player goes round until the loop ends, then finishes
    // THEN: the text and choices are inklecate's from that point on

    @Test func `an old save with split visit counts continues as inklecate plays`() throws {
        let story = try restored(goldenSave())

        #expect(story.currentChoices.map(\.text) == ["Go round", "Leave"])
        try story.chooseChoice(at: 0)
        #expect(story.continueMaximally() == "Round.\n\nSecond.\n")
        #expect(story.currentChoices.map(\.text) == ["Go round", "Leave"])
        try story.chooseChoice(at: 0)
        #expect(story.continueMaximally() == "Round.\nGone round enough.\nOut of the loop.\n")
        #expect(story.currentChoices.map(\.text) == ["Finish"])
        try story.chooseChoice(at: 0)
        #expect(story.continueMaximally() == "Finished.\n")
    }

    // GIVEN: the legacy save plus a key that names no container in the loaded story
    //        (a knot since removed from the story; derived in memory, the golden is untouched)
    // WHEN: it is restored and saved again
    // THEN: the unresolvable key keeps its spelling and count; the split keys still merge

    @Test func `a legacy visit-count key that names no container is kept as it is`() throws {
        var save = try goldenSave()
        var counts = try #require(save["visitCounts"] as? [String: Int])
        counts["removed_knot.stitch"] = 3
        save["visitCounts"] = counts

        let story = try restored(save)

        #expect(try visitCounts(in: story.saveState())
                == ["0.loop": 2, "0.loop.0": 2, "removed_knot.stitch": 3])
    }
}
