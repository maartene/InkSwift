// @real-io
// Issue #33 — a divert counts every container it enters, as C# does
// (ADR-022 §3, reference-fidelity-backlog step 01-07).
//
// C# Story.cs `VisitChangedContainersDueToDivert` walks up from the divert's
// landing point to the first container the flow was already in, counting each
// container on the way; a count-start-only container (gathers, choice bodies,
// sequences: `#f` bit 4) is walked even when the flow was already in it, and
// counted only when entered at its start. Before this step only an absolute
// divert counted, and only its target: a relative divert (`-> .^.stitch`, a
// labelled-gather loop's `.^.^.^`) counted nothing, and a divert to a stitch
// left its knot uncounted.
//
// The fixture covers every divert kind: absolute and relative diverts to
// knots, stitches and a labelled gather, a gather loop's mid-gather rejoin, a
// knot that diverts to itself, absolute and relative tunnels, a function call,
// and a variable divert to a stitch (C# points a variable divert at the
// container itself, index -1, so it skips the walk and its knot stays at 0).
// Each read count is printed after its divert, and the story continues past
// every one of them (prose, then a choice).
//
// Driving port: Story(json:) on inklecate's JSON, continue(),
// chooseChoice(at:). Expected text is `inklecate -p` output, verbatim.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct Engine_DivertVisitCountTests {

    private func story(_ name: String) throws -> Story {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    /// `continueMaximally()`, capped: a miscounted loop guard (`{west < 2: -> east}`)
    /// would otherwise loop forever. Every pass prints a line, so the cap ends it.
    private func continueAtMost(_ maxLines: Int, _ story: Story) -> String {
        var text = ""
        var lines = 0
        while story.canContinue && lines < maxLines {
            text += story.continue()
            lines += 1
        }
        return text
    }

    // GIVEN: knots, stitches and a labelled gather reached by every kind of divert, from inklecate's JSON
    // WHEN: it plays to the closing choice, and that choice is taken
    // THEN: every read count printed along the way is inklecate's

    @Test func `A divert counts every container it enters, as C# does`() throws {
        let story = try story("divert-visit-counts")

        #expect(continueAtMost(40, story) == """
            Hub 1.
            Round 1.
            Round 2.
            Round 3.
            After the rounds, round 3.
            East 1 1.
            West 1 1.
            East 1 2.
            West 1 2.
            Back in hub 2, back 1.
            Finale 2 1.
            Loop knot 1.
            Loop knot 1.
            Loop knot 1.
            Passing 1.
            Passing 2.
            Passed 2.
            In the inner stitch 1.
            In the inner stitch 2.
            Inner 2, tunnels 1.
            Called 2.
            By variable 1.
            Spot 0 1.
            After variable 1.
            Prose after the diverts.

            """)
        #expect(story.currentChoices.map(\.text) == ["Finish"])
        try story.chooseChoice(at: 0)
        #expect(story.continueMaximally() == "Finish\nFinished.\n")
    }

    // GIVEN: `loop_knot`, which diverts to itself (`{m < 3: -> loop_knot}`) twice
    // WHEN: the story plays through it
    // THEN: its read count stays 1 on every pass, as inklecate prints it
    //
    // Deliberately matching the reference (maintainer decision, step 01-07).
    // A divert counts only the containers that change on the way in, and a knot
    // is not count-start-only, so `-> knot` from inside itself counts nothing.
    // Upstream pins this in its own TestKnotStitchGatherCounts (ink
    // tests/Tests.cs:3670-3734, "1 1 / 2 1 / 3 1"). inkle/ink #164 (closed 2016,
    // maintainer joethephish) explains it as intended: only the `-> END` /
    // ChoosePathString case was changed (b822360). #297 asks for the opposite
    // and has been open since 2017 with no maintainer reply. The behaviour has
    // shipped in inklecate for nine years and real stories depend on it. Until
    // this step InkSwift counted the knot again, so a story that relied on that
    // old count plays differently now.

    @Test func `a knot that diverts to itself keeps its read count, as inklecate does`() throws {
        let story = try story("divert-visit-counts")

        let loopLines = continueAtMost(40, story)
            .split(separator: "\n")
            .filter { $0.hasPrefix("Loop knot") }

        #expect(loopLines == ["Loop knot 1.", "Loop knot 1.", "Loop knot 1."])
    }
}
