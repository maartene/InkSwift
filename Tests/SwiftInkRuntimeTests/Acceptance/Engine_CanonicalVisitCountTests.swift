// @real-io
// Issue #33 — multi-line sequences and labelled-gather loops count each
// container once (ADR-022 §1-2, reference-fidelity-backlog step 01-05).
//
// inklecate gives a labelled gather two spellings, its index (`0.0`) and its
// name (`0.loop`). Sequential entry used the first, a divert the second, so the
// gather's count, and the `visit` index of every sequence inside it, split in
// two: the first pass after `-> loop` replayed the first sequence item and the
// loop ran one pass too many. C# counts one container under one path, its name
// wherever it has one (Object.cs:86-89).
//
// Driving port: Story(json:) on inklecate's JSON, continueMaximally(),
// chooseChoice(at:). Expected text is `inklecate -p` output, verbatim. Each
// fixture continues past the loop (prose, then a choice), so a loop that runs
// one pass too many or too few fails.
//
// GOLDEN PROVENANCE — never regenerate `legacy-save-split-visit-counts.json`.
// It is the verbatim output of the unmodified `Story.saveState()` at commit
// e5b423b (main, before canonical visit-count keys), for
// issue33-loop-with-choice.ink.json, route [0] (continueMaximally(), choose
// "Go round", continueMaximally()): the save is taken at the second pass's
// Go round / Leave choice point. Its visitCounts hold the labelled gather under
// both spellings (`0.0`: 1, `0.loop`: 1) and the sequence inside it likewise
// (`0.0.0`: 1, `0.loop.0`: 1). Step 01-06 restores it; this step only pins
// its key shape.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct Engine_CanonicalVisitCountTests {

    private func story(_ name: String) throws -> Story {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func source(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "ink"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // GIVEN: issue #33's stopping sequence inside a labelled-gather loop, from inklecate's JSON
    // WHEN: it plays to the choice after the loop, and that choice is taken
    // THEN: the text is inklecate's: the first item once, then the last item stops

    @Test func `a multi-line stopping sequence in a labelled-gather loop plays as inklecate plays it`() throws {
        let story = try story("issue33-multiline-sequence-loop")

        #expect(story.continueMaximally()
                == "First.\nAfter.\nSecond.\nAfter.\nSecond.\nAfter.\nOut of the loop.\n")
        #expect(story.currentChoices.map(\.text) == ["Finish"])
        try story.chooseChoice(at: 0)
        #expect(story.continueMaximally() == "Finished.\n")
    }

    // GIVEN: issue #33's cycle inside a loop that reads its own gather's count
    // WHEN: it plays to the choice after the loop, and that choice is taken
    // THEN: the cycle alternates A, B, A and the loop runs three passes, as in inklecate

    @Test func `a multi-line cycle in a loop guarded by its gather's read count plays as inklecate plays it`() throws {
        let story = try story("issue33-multiline-cycle-loop")

        #expect(story.continueMaximally() == "A.\n\nB.\n\nA.\nOut of the loop.\n")
        #expect(story.currentChoices.map(\.text) == ["Finish"])
        try story.chooseChoice(at: 0)
        #expect(story.continueMaximally() == "Finished.\n")
    }

    // GIVEN: a labelled-gather loop with a choice inside it
    // WHEN: the player goes round until the gather's read count ends the loop
    // THEN: the sequence and the loop follow inklecate pass for pass

    @Test func `a choice-driven labelled-gather loop counts each pass once`() throws {
        let story = try story("issue33-loop-with-choice")
        var transcript = [story.continueMaximally()]
        for _ in 0..<3 {
            #expect(story.currentChoices.map(\.text) == ["Go round", "Leave"])
            try story.chooseChoice(at: 0)
            transcript.append(story.continueMaximally())
        }
        #expect(story.currentChoices.map(\.text) == ["Finish"])
        try story.chooseChoice(at: 0)
        transcript.append(story.continueMaximally())

        #expect(transcript == [
            "First.\n",
            "Round.\n\nSecond.\n",
            "Round.\n\nSecond.\n",
            "Round.\nGone round enough.\nOut of the loop.\n",
            "Finished.\n",
        ])
    }

    // GIVEN: the #33 repros as ink source
    // WHEN: the native compiler compiles them
    // THEN: it still rejects the multi-line sequence with its located error (the fix is runtime-only)

    @Test(arguments: ["issue33-multiline-sequence-loop", "issue33-multiline-cycle-loop", "issue33-loop-with-choice"])
    func `the native compiler still rejects the issue 33 multi-line sequences`(fixture: String) throws {
        let source = try source(fixture)

        let error = #expect(throws: CompileError.self) { try InkCompiler.compile(source: source) }

        #expect(error?.kind == .unsupportedConstruct)
        #expect(error?.construct == "multi-line sequence")
        #expect(error?.line == (fixture == "issue33-multiline-sequence-loop" ? 3 : 2))
    }

    // GIVEN: the legacy split-key golden captured before canonical keys
    // WHEN: its visitCounts are inspected
    // THEN: one gather and one sequence each sit under both their index and their name spelling

    @Test func `the legacy split-key golden holds one container under both spellings`() throws {
        let url = try #require(Bundle.module.url(forResource: "legacy-save-split-visit-counts", withExtension: "json"))
        let save = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let visitCounts = try #require(save["visitCounts"] as? [String: Int])

        #expect(visitCounts == ["0.0": 1, "0.loop": 1, "0.0.0": 1, "0.loop.0": 1])
    }

    // GIVEN: upstream's dot-separated read-count story (a knot `hi` holding a stitch)
    // WHEN: it has tunnelled into the stitch three times
    // THEN: the host API reads the counts by `knot` and `knot.stitch` name as before

    @Test func `knot and stitch visit counts read by name as before`() throws {
        let story = try story("upstream-TestReadCountDotSeparatedPath-0")

        #expect(story.continueMaximally() == "hi\nhi\nhi\n3\n")
        #expect(story.visitCount(forKnot: "hi.stitch_to_count") == 3)
        #expect(story.visitCount(forKnot: "hi") == 0)
        #expect(story.visitCount(forKnot: "nowhere") == 0)
    }
}
