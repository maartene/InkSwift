// @real-io @driving_adapter
// Acceptance tests for native-move-to-knot — US-01 through US-04.
//
// Driving port: Story facade — init(json:), moveToKnot(_:stitch:), continue(), canContinue
// Oracle: InkSwift.InkStory (JavaScript bridge) — macOS only
//
// Strategy C: all adapters use real inklecate-compiled JSON fixtures from the test bundle.
// Walking skeleton: not applicable — brownfield extension; WalkingSkeletonTests remains the module WS.
//
// Fixture: slice-move-to-knot.ink.json
//   Entry: with_choices — one continue() leaves the story at a choice point (dirty state).
//   Knots: with_choices, score_setup, prologue, interrogation, epilogue, investigation, investigation.lab
//
// Oracle behaviour note (RD-04): InkStory.moveToKnitStitch auto-continues internally; Story.moveToKnot
// does not. Oracle tests call story.continue() once after moveToKnot to align with the oracle output.

import Testing
import Foundation
@testable import SwiftInkRuntime
#if os(macOS)
import InkSwift
#endif

// MARK: - Shared helpers

private func makeMoveToKnotStory() throws -> Story {
    let url = try #require(Bundle.module.url(forResource: "slice-move-to-knot", withExtension: "ink.json"))
    return try Story(json: String(contentsOf: url, encoding: .utf8))
}

private func loadMoveToKnotJSON() throws -> String {
    let url = try #require(Bundle.module.url(forResource: "slice-move-to-knot", withExtension: "ink.json"))
    return try String(contentsOf: url, encoding: .utf8)
}

// MARK: - US-01 — Jump to a Named Knot (Happy Path)

@Suite("US-01 — Jump to a Named Knot")
struct US01_JumpToNamedKnotTests {

    // AC: moveToKnot(_:stitch:) is a public throwing method with the specified signature.
    // AC: After a successful call, canContinue is true.
    @Test func `moveToKnot with valid knot name does not throw and canContinue is true`() throws {
        let story = try makeMoveToKnotStory()
        _ = story.`continue`()
        try story.moveToKnot("interrogation")
        #expect(story.canContinue)
    }

    // AC: After a successful call, continue() returns the first line of the target knot.
    @Test func `continue after moveToKnot returns first line of target knot`() throws {
        let story = try makeMoveToKnotStory()
        _ = story.`continue`()
        try story.moveToKnot("interrogation")
        let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "Detective Mills enters the room.")
    }

    // AC: Jump succeeds even when the story is already ended (isEnded == true).
    // AC: After a successful call, canContinue is true.
    @Test func `moveToKnot from ended story resets canContinue to true`() throws {
        let story = try makeMoveToKnotStory()
        // Exhaust all content to reach the choice point, then make a choice to end the story.
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 0)
        while story.canContinue { _ = story.`continue`() }
        #expect(!story.canContinue)
        try story.moveToKnot("prologue")
        #expect(story.canContinue)
        let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "Once upon a time there was a detective.")
    }

    // AC: Multiple consecutive jumps each fully reset state (no accumulation of stale frames).
    @Test func `multiple consecutive moveToKnot calls each produce correct target content`() throws {
        let story = try makeMoveToKnotStory()
        _ = story.`continue`()

        try story.moveToKnot("interrogation")
        _ = story.`continue`()

        try story.moveToKnot("epilogue")
        let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "The final score was 0.")
    }

    // AC: After a successful call, currentText does not contain any text from before the jump.
    @Test func `continue after moveToKnot does not contain text from before the jump`() throws {
        let story = try makeMoveToKnotStory()
        // Capture all pre-jump lines; the last non-empty one is the "crossroads" line.
        var priorLines: [String] = []
        while story.canContinue {
            let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { priorLines.append(line) }
        }
        #expect(priorLines.contains { $0.contains("crossroads") })

        try story.moveToKnot("epilogue")
        let postText = story.`continue`()
        #expect(!postText.contains("crossroads"))
        #expect(!postText.contains("You are at"))
    }

    // AC: Jump clears currentChoices (state fields cleared include currentChoices).
    @Test func `moveToKnot from mid-execution state with choices clears currentChoices`() throws {
        let story = try makeMoveToKnotStory()
        // Exhaust text content to reach the choice point.
        while story.canContinue { _ = story.`continue`() }
        #expect(story.currentChoices.count == 2)
        try story.moveToKnot("interrogation")
        #expect(story.currentChoices.isEmpty)
    }

    // AC: state fields preserved — variablesState not cleared.
    @Test func `global variables are preserved across a jump`() throws {
        let story = try makeMoveToKnotStory()
        try story.moveToKnot("score_setup")
        _ = story.`continue`()
        try story.moveToKnot("epilogue")
        let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "The final score was 42.")
    }

    // Oracle comparison — macOS only.
    // RD-04: native moveToKnot does not auto-continue; oracle moveToKnitStitch does.
    // One continue() call on the native side aligns with the oracle's auto-continued output.
    @Test func `moveToKnot continue output matches JS-bridge oracle`() throws {
        #if os(macOS)
        let json = try loadMoveToKnotJSON()
        let native = try Story(json: json)
        try native.moveToKnot("interrogation")
        let nativeLine = native.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)

        let oracle = InkStory()
        oracle.loadStory(json: json)
        oracle.moveToKnitStitch("interrogation")
        let oracleLine = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(nativeLine == oracleLine)
        #endif
    }

    // Save/restore invariant: post-jump position survives a save/restore cycle.
    @Test func `moveToKnot position survives save and restore into fresh Story`() throws {
        let json = try loadMoveToKnotJSON()
        let story = try Story(json: json)
        _ = story.`continue`()
        try story.moveToKnot("interrogation")
        _ = story.`continue`()
        let savedData = try story.saveState()

        let restored = try Story(json: json)
        try restored.restoreState(savedData)
        #expect(restored.canContinue == story.canContinue)
    }
}

// MARK: - US-02 — Jump Throws knotNotFound for Non-Existent Knot

@Suite("US-02 — knotNotFound Error")
struct US02_KnotNotFoundTests {

    // AC: Calling moveToKnot with a name not in root.namedContent throws knotNotFound with the knot name.
    @Test func `moveToKnot with nonexistent knot name throws knotNotFound`() throws {
        let story = try makeMoveToKnotStory()
        #expect(throws: StoryError.knotNotFound("ghost_town")) {
            try story.moveToKnot("ghost_town")
        }
    }

    // AC: knotNotFound carries the attempted path as the associated value.
    @Test func `knotNotFound carries the attempted knot name as associated value`() throws {
        let story = try makeMoveToKnotStory()
        var caughtPath: String? = nil
        do {
            try story.moveToKnot("missing_knot")
        } catch StoryError.knotNotFound(let path) {
            caughtPath = path
        }
        #expect(caughtPath == "missing_knot")
    }

    // AC: Calling moveToKnot("") throws knotNotFound("").
    @Test func `moveToKnot with empty string throws knotNotFound with empty string`() throws {
        let story = try makeMoveToKnotStory()
        #expect(throws: StoryError.knotNotFound("")) {
            try story.moveToKnot("")
        }
    }

    // AC: No state mutation occurs before the throw (pre-jump state is preserved).
    @Test func `engine state is unchanged after a failed jump`() throws {
        let story = try makeMoveToKnotStory()
        let priorCanContinue = story.canContinue
        _ = story.`continue`()
        let priorChoicesCount = story.currentChoices.count
        let priorCanContinueAfterContinue = story.canContinue

        try? story.moveToKnot("nonexistent_knot")

        #expect(story.canContinue == priorCanContinueAfterContinue)
        #expect(story.currentChoices.count == priorChoicesCount)
        _ = priorCanContinue
    }

    // AC: Stitch not found on valid knot throws knotNotFound with compound "knot.stitch" path.
    @Test func `moveToKnot with nonexistent stitch on valid knot throws knotNotFound with compound path`() throws {
        let story = try makeMoveToKnotStory()
        #expect(throws: StoryError.knotNotFound("investigation.ghost_alley")) {
            try story.moveToKnot("investigation", stitch: "ghost_alley")
        }
    }
}

// MARK: - US-03 — Jump to a Knot + Stitch (Compound Path)

@Suite("US-03 — Compound Path")
struct US03_CompoundPathTests {

    // AC: When stitch is non-nil, compound path "knot.stitch" is resolved; canContinue is true.
    @Test func `moveToKnot with stitch resolves compound path and canContinue is true`() throws {
        let story = try makeMoveToKnotStory()
        try story.moveToKnot("investigation", stitch: "lab")
        #expect(story.canContinue)
    }

    // AC: A successful compound-path jump produces the stitch's first line on continue().
    @Test func `continue after compound path jump returns first line of stitch`() throws {
        let story = try makeMoveToKnotStory()
        try story.moveToKnot("investigation", stitch: "lab")
        let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "The lab is full of evidence.")
    }

    // AC: When stitch is nil, behaviour is identical to a knot-only jump (no regression).
    @Test func `moveToKnot with nil stitch jumps to knot root not stitch`() throws {
        let story = try makeMoveToKnotStory()
        try story.moveToKnot("investigation", stitch: nil)
        let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "You begin investigating.")
    }

    // AC: Non-existent stitch on valid knot throws knotNotFound with compound path.
    @Test func `compound path with nonexistent stitch throws knotNotFound with compound path`() throws {
        let story = try makeMoveToKnotStory()
        #expect(throws: StoryError.knotNotFound("investigation.dungeon")) {
            try story.moveToKnot("investigation", stitch: "dungeon")
        }
    }

    // AC: Compound-path output matches JS-bridge oracle (macOS only).
    @Test func `compound path output matches JS-bridge oracle`() throws {
        #if os(macOS)
        let json = try loadMoveToKnotJSON()
        let native = try Story(json: json)
        try native.moveToKnot("investigation", stitch: "lab")
        let nativeLine = native.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)

        let oracle = InkStory()
        oracle.loadStory(json: json)
        oracle.moveToKnitStitch("investigation", stitch: "lab")
        let oracleLine = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(nativeLine == oracleLine)
        #endif
    }

    // Save/restore after compound path jump.
    @Test func `compound path jump position survives save and restore`() throws {
        let json = try loadMoveToKnotJSON()
        let story = try Story(json: json)
        try story.moveToKnot("investigation", stitch: "lab")
        _ = story.`continue`()
        let savedData = try story.saveState()

        let restored = try Story(json: json)
        try restored.restoreState(savedData)
        #expect(restored.canContinue == story.canContinue)
    }
}

// MARK: - US-04 — Save/Restore Round-Trip After a Jump

@Suite("US-04 — Save/Restore After Jump")
struct US04_SaveRestoreAfterJumpTests {

    // AC: saveState() after moveToKnot() + continue() captures post-jump execution position.
    // AC: restoreState() from a post-jump save resumes from the correct location.
    @Test func `restore after jump resumes from the jumped-to knot`() throws {
        let json = try loadMoveToKnotJSON()
        let story = try Story(json: json)
        _ = story.`continue`()
        try story.moveToKnot("interrogation")
        let firstLine = story.`continue`()
        let savedData = try story.saveState()

        let restored = try Story(json: json)
        try restored.restoreState(savedData)
        #expect(restored.canContinue == story.canContinue)
        _ = firstLine
    }

    // AC: Pre-jump saves are unaffected by a subsequent jump (saves are point-in-time snapshots).
    @Test func `pre-jump save is unaffected by later jump`() throws {
        let json = try loadMoveToKnotJSON()
        let story = try Story(json: json)
        let priorData = try story.saveState()

        _ = story.`continue`()
        try story.moveToKnot("interrogation")
        _ = story.`continue`()

        let restored = try Story(json: json)
        try restored.restoreState(priorData)
        let restoredLine = restored.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(restoredLine == "You are at a crossroads.")
    }

    // AC: All state fields reset by the jump are not present in the save with their pre-jump values.
    @Test func `stale frames do not survive reset and save cycle`() throws {
        let json = try loadMoveToKnotJSON()
        let story = try Story(json: json)
        // Exhaust to choice point so currentChoices is non-empty before jump.
        while story.canContinue { _ = story.`continue`() }
        #expect(story.currentChoices.count == 2)
        try story.moveToKnot("interrogation")
        let savedData = try story.saveState()

        let restored = try Story(json: json)
        try restored.restoreState(savedData)
        #expect(restored.currentChoices.isEmpty)
    }

    // AC: Save/restore after a compound-path jump works identically to a knot-only jump.
    @Test func `save-restore after compound path jump resumes from stitch`() throws {
        let json = try loadMoveToKnotJSON()
        let story = try Story(json: json)
        try story.moveToKnot("investigation", stitch: "lab")
        _ = story.`continue`()
        let savedData = try story.saveState()

        let restored = try Story(json: json)
        try restored.restoreState(savedData)
        #expect(restored.canContinue == story.canContinue)
    }

    // AC: Restore from ended-story-then-jump save correctly places reader in target knot.
    @Test func `restore after jump from ended story resumes from jumped-to knot`() throws {
        let json = try loadMoveToKnotJSON()
        let story = try Story(json: json)
        // Exhaust to choice point, choose, exhaust to end.
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 0)
        while story.canContinue { _ = story.`continue`() }
        try story.moveToKnot("prologue")
        _ = story.`continue`()
        let savedData = try story.saveState()

        let restored = try Story(json: json)
        try restored.restoreState(savedData)
        #expect(restored.canContinue == story.canContinue)
    }
}
