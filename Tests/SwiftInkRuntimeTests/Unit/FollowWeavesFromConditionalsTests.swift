//
//  FollowWeavesFromConditionalsTests.swift
//  InkSwift
//
//  Created by Engels, Maarten MAK on 24/06/2026.
//

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct FollowWeavesFromConditionalsTests {

    // MARK: - Bug B (FIXED) — inline conditional divert into a same-knot stitch

    /// Regression for the real `poc-borrowed-light` story: an inline conditional
    /// whose branch is a divert — `{ accepted_borrowed_light && found_story: -> end_game }`
    /// inside the `cass` knot — must take the divert to the `end_game` STITCH of that
    /// same knot. Before the fix the inline-conditional branch emitted the divert
    /// target RAW (`end_game`) instead of qualifying it to `cass.end_game` (the way a
    /// plain divert is lowered), so the runtime's absolute-from-root resolver could
    /// not find the knot-nested stitch and the divert silently no-op'd — `cass`
    /// printed its opening line and then stopped, never reaching `end_game`.
    ///
    /// Anchored to the inklecate oracle (execution-equivalence, KPI #1): the native
    /// compile and the committed oracle JSON are played through the SAME runtime
    /// along the SAME path (enter `cass` with the borrowed-light quest accepted and
    /// the story found) and must produce identical output.
    @Test func `story follows inline conditional divert into a same-knot stitch matching the oracle`() throws {
        let source = try CompilerOracle.source("BorrowedLight")
        let oracleJSON = try CompilerOracle.oracleJSON("BorrowedLight")

        let native = Story(blueprint: try InkCompiler.compile(source: source))
        let oracle = try Story(json: oracleJSON)

        // Set the state that makes `cass` divert to its `end_game` stitch, then enter
        // the knot. (The story's own entry is `-> journal`; the divert-bearing
        // conditionals live in `cass` and depend on quest variables the wider game
        // sets externally.)
        for story in [native, oracle] {
            story.setVariable("accepted_borrowed_light", to: true)
            story.setVariable("found_story", to: true)
            try story.moveToKnot("cass")
        }

        let nativeText = native.continueMaximally()
        let oracleText = oracle.continueMaximally()

        // The inline conditional took the divert and reached the `end_game` stitch.
        #expect(nativeText.contains(
            "Cass is at the counter, and he sees your face and lights up"
        ))
        // Line-for-line execution-equivalence with the inklecate oracle.
        #expect(nativeText == oracleText)
    }

    // MARK: - Bug A (FIXED) — top-level single-`=` stitch dropped at codegen

    /// A SEPARATE defect surfaced while fixing Bug B: a top-level single-`=` stitch
    /// (declared at file scope, outside any knot) was dropped during codegen — it
    /// never became a `namedContent` container, so a `{ cond: -> end_game }` divert
    /// to it found no target and the story produced EMPTY output (and a plain
    /// fall-through over-produced, flattening the stitch body inline). This is the
    /// original minimal reproduction. It is a DIFFERENT root cause from Bug B (here
    /// the target container was never emitted; in Bug B it existed but the divert was
    /// unqualified). The fix groups top-level stitches into the root's named content,
    /// reusing the same stitch-emission machinery a knot uses.
    ///
    /// Anchored to the inklecate oracle: native compile and the committed oracle JSON
    /// are played through the SAME runtime and must produce identical output.
    @Test func `story follows an inline conditional divert into a top-level stitch matching the oracle`() throws {
        let source = try CompilerOracle.source("TopLevelStitchDivert")
        let oracleJSON = try CompilerOracle.oracleJSON("TopLevelStitchDivert")

        let native = Story(blueprint: try InkCompiler.compile(source: source))
        let oracle = try Story(json: oracleJSON)

        let nativeText = native.continueMaximally()
        let oracleText = oracle.continueMaximally()

        // The top-level `= end_game` stitch is a resolvable divert target.
        #expect(nativeText.contains(
            "Cass is at the counter, and he sees your face and lights up before you've said a word"
        ))
        // The conditional took the divert, so the post-conditional line is skipped.
        #expect(nativeText.contains("You should never reach this line.") == false)
        // Line-for-line execution-equivalence with the inklecate oracle.
        #expect(nativeText == oracleText)
    }
}
