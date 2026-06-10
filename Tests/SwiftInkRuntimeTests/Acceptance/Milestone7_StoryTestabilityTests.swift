// @real-io @driving_adapter
// Acceptance tests for story-testability — US-01 through US-04.
//
// Driving port: Story facade — getVariable, setVariable, visitCount, continueMaximally
// Driving port (setVisitCount): SwiftInkRuntimeTestSupport extension on Story
//
// Strategy C: all adapters use real inklecate-compiled JSON fixtures from the test bundle.
// Walking skeleton: Slice 01 — getVariable initial value (first new API on the Story facade).
//
// Fixture: slice-story-testability.ink.json
//   Knots: start, score_setup, reward_check, locked_door, greeting, prologue, multi_line, with_choices, left, right
//   Variables: score (Int=0), badge_awarded (Bool=false), player_name (String="unnamed"), has_key (Bool=false)

import Testing
import Foundation
@testable import SwiftInkRuntime
import SwiftInkRuntimeTestSupport

// MARK: - Fixture helper

private func makeStory() throws -> Story {
    let url = try #require(Bundle.module.url(forResource: "slice-story-testability", withExtension: "ink.json"))
    return try Story(json: String(contentsOf: url, encoding: .utf8))
}

// MARK: - Walking Skeleton (Slice 01)

@Suite("Walking Skeleton — getVariable initial value")
struct StoryTestability_WalkingSkeleton {

    // @walking_skeleton @real-io
    // Minimum e2e: Story(json:) → getVariable → value returned as Any?
    // Driving port: Story.getVariable(_:)
    @Test func `initial integer variable value is readable via getVariable`() throws {
        let story = try makeStory()
        let result = story.getVariable("score")
        #expect(result as? Int == 0)
    }
}

// MARK: - US-01: Read a Story Variable

@Suite("US-01 — getVariable")
struct US01_GetVariableTests {

    // AC: getVariable returns Int for .int InkValue
    @Test func `integer variable reads as Int`() throws {
        let story = try makeStory()
        let result = story.getVariable("score")
        #expect(result as? Int == 0)
    }

    // AC: getVariable returns Bool for .bool InkValue
    @Test func `boolean variable reads as Bool`() throws {
        let story = try makeStory()
        let result = story.getVariable("badge_awarded")
        #expect(result as? Bool == false)
    }

    // AC: getVariable returns String for .string InkValue
    @Test func `string variable reads as String`() throws {
        let story = try makeStory()
        let result = story.getVariable("player_name")
        #expect(result as? String == "unnamed")
    }

    // AC: getVariable returns the updated value after engine execution changes it
    @Test func `integer variable reads updated value after engine sets it via score_setup`() throws {
        let story = try makeStory()
        try story.moveToKnot("score_setup")
        _ = story.`continue`()
        let result = story.getVariable("score")
        #expect(result as? Int == 42)
    }

    // AC: getVariable returns updated bool after engine assignment in reward_check (score >= 10)
    @Test func `boolean variable is true after story logic sets it during execution`() throws {
        let story = try makeStory()
        try story.moveToKnot("score_setup")
        _ = story.`continue`()
        try story.moveToKnot("reward_check")
        _ = story.`continue`()
        let result = story.getVariable("badge_awarded")
        #expect(result as? Bool == true)
    }

    // AC: getVariable returns nil for an unknown variable name (no throw)
    @Test func `unknown variable name returns nil without throwing`() throws {
        let story = try makeStory()
        let result = story.getVariable("ghost_variable")
        #expect(result == nil)
    }

    // AC: method signature — public func getVariable(_ name: String) -> Any?
    // (verified structurally — if this compiles, the signature is correct)
    @Test func `getVariable compiles with the correct public signature`() throws {
        let story = try makeStory()
        let _: Any? = story.getVariable("score")
    }
}

// MARK: - US-02: Write a Story Variable

@Suite("US-02 — setVariable")
struct US02_SetVariableTests {

    // AC: setVariable writes an Int; subsequent getVariable returns the same value
    @Test func `setVariable for Int is readable back via getVariable`() throws {
        let story = try makeStory()
        story.setVariable("score", to: 42)
        #expect(story.getVariable("score") as? Int == 42)
    }

    // AC: setVariable writes a Bool; subsequent getVariable returns the same value
    @Test func `setVariable for Bool is readable back via getVariable`() throws {
        let story = try makeStory()
        story.setVariable("badge_awarded", to: true)
        #expect(story.getVariable("badge_awarded") as? Bool == true)
    }

    // AC: setVariable writes a String; subsequent getVariable returns the same value
    @Test func `setVariable for String is readable back via getVariable`() throws {
        let story = try makeStory()
        story.setVariable("player_name", to: "Raya")
        #expect(story.getVariable("player_name") as? String == "Raya")
    }

    // AC: injected Int variable changes story output at reward_check (score >= 10 → gold badge)
    @Test func `setVariable with score 10 causes reward_check to output gold badge line`() throws {
        let story = try makeStory()
        story.setVariable("score", to: 10)
        try story.moveToKnot("reward_check")
        let output = story.continueMaximally()
        #expect(output.contains("You earned the gold badge."))
    }

    // AC: injected Bool true for has_key causes locked_door to output "door swings open"
    @Test func `setVariable with has_key true causes locked_door to output door opens line`() throws {
        let story = try makeStory()
        story.setVariable("has_key", to: true)
        try story.moveToKnot("locked_door")
        let output = story.continueMaximally()
        #expect(output.contains("The door swings open."))
        #expect(!output.contains("You need a key."))
    }

    // AC: injected String for player_name personalises start knot output
    @Test func `setVariable for player_name personalises start knot output`() throws {
        let story = try makeStory()
        story.setVariable("player_name", to: "Raya")
        try story.moveToKnot("start")
        let output = story.continueMaximally()
        #expect(output.contains("Raya"))
    }

    // AC: setting an unknown variable name does not throw
    @Test func `setVariable for unknown variable does not throw`() throws {
        let story = try makeStory()
        story.setVariable("nonexistent_variable", to: 99)
        #expect(story.getVariable("nonexistent_variable") == nil)
    }

    // AC: setVariable does not affect canContinue or currentChoices
    @Test func `setVariable does not change canContinue or currentChoices`() throws {
        let story = try makeStory()
        let canContinueBefore = story.canContinue
        let choicesBefore = story.currentChoices.count
        story.setVariable("score", to: 99)
        #expect(story.canContinue == canContinueBefore)
        #expect(story.currentChoices.count == choicesBefore)
    }
}

// MARK: - US-03: Read and Write Knot Visit Counts

@Suite("US-03 — visitCount and setVisitCount")
struct US03_VisitCountTests {

    // AC: visitCount returns 0 for a knot that has not been visited
    @Test func `visitCount returns 0 for unvisited knot`() throws {
        let story = try makeStory()
        #expect(story.visitCount(forKnot: "prologue") == 0)
    }

    // AC: visitCount returns at least 1 after natural navigation into prologue
    @Test func `visitCount returns 1 after natural execution of prologue knot`() throws {
        let story = try makeStory()
        try story.moveToKnot("prologue")
        _ = story.`continue`()
        #expect(story.visitCount(forKnot: "prologue") >= 1)
    }

    // AC: setVisitCount write + visitCount read-back returns injected value
    @Test func `setVisitCount write is readable back via visitCount`() throws {
        let story = try makeStory()
        story.setVisitCount(forKnot: "prologue", to: 3)
        #expect(story.visitCount(forKnot: "prologue") == 3)
    }

    // AC: injected visit count > 1 causes greeting to output "Welcome back!"
    @Test func `setVisitCount to 2 causes greeting to output welcome back line`() throws {
        let story = try makeStory()
        story.setVisitCount(forKnot: "prologue", to: 2)
        try story.moveToKnot("greeting")
        let output = story.continueMaximally()
        #expect(output.contains("Welcome back!"))
        #expect(!output.contains("Hello, stranger."))
    }

    // AC: greeting shows "Hello, stranger." when prologue visit count is 0
    @Test func `greeting shows hello stranger when prologue visit count is 0`() throws {
        let story = try makeStory()
        try story.moveToKnot("greeting")
        let output = story.continueMaximally()
        #expect(output.contains("Hello, stranger."))
    }

    // AC: visitCount returns 0 for unknown knot name, no throw
    @Test func `visitCount for unknown knot returns 0 without throwing`() throws {
        let story = try makeStory()
        #expect(story.visitCount(forKnot: "nonexistent_knot") == 0)
    }

    // AC: setVisitCount for unknown knot is a no-op, no throw
    @Test func `setVisitCount for unknown knot does not throw`() throws {
        let story = try makeStory()
        story.setVisitCount(forKnot: "nonexistent_knot", to: 5)
        #expect(story.visitCount(forKnot: "nonexistent_knot") == 0)
    }
}

// MARK: - US-04: Drain All Story Output with continueMaximally

@Suite("US-04 — continueMaximally")
struct US04_ContinueMaximallyTests {

    // AC: continueMaximally drains all lines from a multi-line knot
    @Test func `continueMaximally collects all lines from multi_line knot`() throws {
        let story = try makeStory()
        try story.moveToKnot("multi_line")
        let output = story.continueMaximally()
        #expect(output.contains("Line one."))
        #expect(output.contains("Line two."))
        #expect(output.contains("Line three."))
    }

    // AC: output equals manual while-loop (equivalence invariant)
    @Test func `continueMaximally output equals manual while-canContinue loop output`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice-story-testability", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        let storyA = try Story(json: json)
        let storyB = try Story(json: json)
        try storyA.moveToKnot("multi_line")
        try storyB.moveToKnot("multi_line")

        var manualOutput = ""
        while storyA.canContinue { manualOutput += storyA.`continue`() }
        let maximalOutput = storyB.continueMaximally()

        #expect(manualOutput == maximalOutput)
    }

    // AC: continueMaximally stops at a choice point; currentChoices is non-empty
    @Test func `continueMaximally stops at choice point and currentChoices is non-empty`() throws {
        let story = try makeStory()
        try story.moveToKnot("with_choices")
        let output = story.continueMaximally()
        #expect(output.contains("At the crossroads."))
        #expect(!story.currentChoices.isEmpty)
    }

    // AC: when canContinue is already false, returns "" and does not throw
    @Test func `continueMaximally on ended story returns empty string`() throws {
        let story = try makeStory()
        try story.moveToKnot("multi_line")
        _ = story.continueMaximally()
        #expect(!story.canContinue)
        let second = story.continueMaximally()
        #expect(second == "")
    }

    // AC: @discardableResult — return value may be ignored
    @Test func `continueMaximally return value may be discarded without compiler warning`() throws {
        let story = try makeStory()
        try story.moveToKnot("multi_line")
        story.continueMaximally()
    }

    // AC: canContinue is false after draining a terminal knot
    @Test func `canContinue is false after continueMaximally drains terminal knot`() throws {
        let story = try makeStory()
        try story.moveToKnot("prologue")
        _ = story.continueMaximally()
        #expect(!story.canContinue)
    }
}
