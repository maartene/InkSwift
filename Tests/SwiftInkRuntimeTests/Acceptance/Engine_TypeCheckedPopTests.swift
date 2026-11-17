// @acceptance @real-io
//
// S7 (typed-runtime-paths, ADR-017) — a tunnel onwards (`->->`) or function
// return (`~ return`) whose call-stack frame is of the other kind, or whose
// stack is empty, is refused: the engine reports the reference's exact message
// through `currentErrors` and ends the flow. C# Story.cs PopFunction/PopTunnel
// (~1255-1297) builds "Found {popped}, when expected {expected}", and
// AddError → state.ForceEnd() (~2838-2857) stops the story. inkjs (through the
// InkSwift JS bridge) reports the same text behind its "RUNTIME ERROR: (<pointer>): "
// location prefix; InkSwift reports the bare message.
//
// One fixture per scenario, compiled by inklecate: a story stops at its first
// refusal. Each fixture puts content after the offending construct; none of it
// may play. inklecate rejects choices and diverts inside a function and a plain
// divert into one, so a function is reached by a variable divert, and where the
// construct sits in a function the choice of the continuation sits in the
// caller, where a wrongly popped frame would resume.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Engine — type-checked tunnel and function pops")
struct Engine_TypeCheckedPopTests {

    struct Refusal: CustomTestStringConvertible, Sendable {
        let fixture: String
        let linesBeforeRefusal: [String]
        let error: String
        var testDescription: String { fixture }
    }

    static let refusals = [
        Refusal(
            fixture: "pop-tunnel-onwards-over-function",
            linesBeforeRefusal: ["Before the call.", "Inside f."],
            error: "Found tunnel onwards statement (->->), when expected function return statement (~ return)"),
        Refusal(
            fixture: "pop-function-return-over-tunnel",
            linesBeforeRefusal: ["Before the tunnel.", "Inside the tunnel.", "Inside f."],
            error: "Found function return statement (~ return), when expected tunnel onwards statement (->->)"),
        Refusal(
            fixture: "pop-tunnel-onwards-empty-stack",
            linesBeforeRefusal: ["Before the divert.", "Inside g."],
            error: "Found tunnel onwards statement (->->), when expected end of flow (-> END or choice)"),
        Refusal(
            fixture: "pop-function-return-empty-stack",
            linesBeforeRefusal: ["Before the divert.", "Inside f."],
            error: "Found function return statement (~ return), when expected end of flow (-> END or choice)"),
    ]

    /// Continue until the story cannot, without choosing: trimmed non-empty lines.
    private func playUntilStopped(_ story: Story) -> [String] {
        var lines: [String] = []
        var steps = 0
        while story.canContinue && steps < 100 {
            let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty == false { lines.append(line) }
            steps += 1
        }
        return lines
    }

    private func refusedStory(_ refusal: Refusal) throws -> Story {
        let story = try Story(json: try CompilerOracle.oracleJSON(refusal.fixture))
        _ = playUntilStopped(story)
        return story
    }

    @Test(arguments: refusals)
    func `a mismatched or empty-stack pop reports the reference message and ends the flow`(refusal: Refusal) throws {
        let story = try Story(json: try CompilerOracle.oracleJSON(refusal.fixture))

        let lines = playUntilStopped(story)

        #expect(lines == refusal.linesBeforeRefusal)
        #expect(story.currentErrors == [refusal.error])
        #expect(story.canContinue == false)
        #expect(story.currentChoices.isEmpty)
    }

    // The reference (Story.cs NextContent ~2676-2705) pops on function-body
    // exhaustion only when CanPop(Function); with a tunnel frame on top it does
    // not pop, the pointer runs out and the flow ends. Nothing is consumed, so
    // "After the tunnel." never plays. inkjs then also reports "unexpectedly
    // reached end of content. Do you need a '->->' to return from a tunnel?"
    // (Story.cs ContinueInternal ~505-514). That end-of-content check is a
    // separate family from ADR-017's pop check and InkSwift does not implement
    // it, so errors are deliberately not asserted here.
    @Test func `a function body that runs out over a tunnel frame ends the flow without consuming the frame`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON("pop-function-exhaustion-over-tunnel"))

        let lines = playUntilStopped(story)

        #expect(lines == ["Before the tunnel.", "Inside the tunnel.", "Inside f."])
        #expect(story.canContinue == false)
        #expect(story.currentChoices.isEmpty)
        #expect(story.engine.state.returnStack.map(\.kind) == [.tunnel])
    }

    // D7: a runtime error is unrecoverable, so it is never written to a save.
    @Test(arguments: refusals)
    func `errors are never saved and restoreState clears them`(refusal: Refusal) throws {
        let story = try refusedStory(refusal)
        try #require(story.currentErrors.isEmpty == false)

        let saved = try story.saveState()
        try story.restoreState(saved)

        #expect(String(decoding: saved, as: UTF8.self).contains("Found") == false)
        #expect(story.currentErrors.isEmpty)
    }

    @Test func `moveToKnot clears the errors and the story continues`() throws {
        let story = try refusedStory(Self.refusals[2])
        try #require(story.currentErrors.isEmpty == false)

        try story.moveToKnot("elsewhere")

        #expect(story.currentErrors.isEmpty)
        #expect(playUntilStopped(story) == ["Somewhere else."])
        #expect(story.currentChoices.map(\.text) == ["Leave"])
    }

    @Test(arguments: ["slice-t1-tunnels", "slice-t2-nested-tunnels", "slice-c3-functions",
                      "engine-function-conditional-branch"])
    func `well-formed tunnels and functions report no errors`(fixture: String) throws {
        let story = try Story(json: try CompilerOracle.oracleJSON(fixture))

        let lines = try CompilerOracle.play(story)

        #expect(lines.isEmpty == false)
        #expect(story.currentErrors.isEmpty)
    }
}
