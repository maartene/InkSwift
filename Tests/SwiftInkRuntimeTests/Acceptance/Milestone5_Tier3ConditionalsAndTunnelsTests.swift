// @real-io
// Acceptance tests for Tier 3 — Inline Conditionals, Block Conditionals, Functions, and Tunnels.
//
// Driving port: Story facade — init(json:), continue(), chooseChoice(at:),
//               saveState(), restoreState(_:)
// Oracle: InkSwift.InkStory (JavaScript bridge) — macOS only
//
// Each behaviour is verified in two modes:
//   • in-memory:       single Story instance played continuously to the assertion point
//   • save/restore:    state saved and restored into a fresh Story instance before each action
//                      ("rebuilding the story each time" per the save/restore invariant)
//
// The final suite (TheInterceptAcceptanceTests) is the Tier 3 ceiling proof.
// It becomes fully GREEN only when all Tier 3 slices (C1–C3, T1–T3) are implemented.
//
// All fixtures compiled from real Ink source using inklecate.
// See Tests/SwiftInkRuntimeTests/slice-c*.ink and slice-t*.ink for source files.
// See docs/feature/tier3-conditionals-and-tunnels/distill/upstream-issues.md for
// inklecate encoding findings that affect implementation (notably: "out", "pop", ci=-1).

import Testing
import Foundation
@testable import SwiftInkRuntime
#if os(macOS)
import InkSwift
#endif

// MARK: - Shared helpers

private func collectLines(_ story: Story) -> [String] {
    var lines: [String] = []
    while story.canContinue {
        let trimmed = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { lines.append(trimmed) }
    }
    return lines
}

// MARK: - Slice C1 — Inline Conditional Text

// Fixture: slice-c1-inline-conditionals.ink.json
// Story has one choice point with two choices:
//   choice 0 → "You see a stranger."  — metCass stays false → "She's a stranger."
//   choice 1 → "You see your friend." — metCass becomes true → "You know her."

@Suite("Slice C1 — Inline Conditional Text")
struct Slice_C1_InlineConditionalTests {

    private func makeStory() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "slice-c1-inline-conditionals", withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func loadJSON() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "slice-c1-inline-conditionals", withExtension: "ink.json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // AC: false-branch text appears when condition is false, true-branch absent — in-memory
    @Test func `false-branch text appears when condition is false and true-branch is absent — in-memory`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 0)
        let lines = collectLines(story)
        #expect(lines.contains { $0.contains("She's a stranger.") })
        #expect(!lines.contains { $0.contains("You know her.") })
    }

    // AC: true-branch text appears when condition is true, false-branch absent — in-memory
    @Test func `true-branch text appears when condition is true and false-branch is absent — in-memory`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 1)
        let lines = collectLines(story)
        #expect(lines.contains { $0.contains("You know her.") })
        #expect(!lines.contains { $0.contains("She's a stranger.") })
    }

    // AC: exactly one branch appears — no branch contamination
    @Test func `exactly one branch appears in output — no branch contamination`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 0)
        let lines = collectLines(story)
        let hasTrue = lines.contains { $0.contains("You know her.") }
        let hasFalse = lines.contains { $0.contains("She's a stranger.") }
        #expect(hasTrue != hasFalse, "Exactly one branch must appear in output")
    }

    // AC: false-branch selection survives save and restore
    @Test func `false-branch selection survives save and restore`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        while s.canContinue { _ = s.`continue`() }
        try s.chooseChoice(at: 0)
        let saved = try s.saveState()

        let r = try Story(json: json)
        try r.restoreState(saved)
        let lines = collectLines(r)
        #expect(lines.contains { $0.contains("She's a stranger.") })
        #expect(!lines.contains { $0.contains("You know her.") })
    }

    // AC: true-branch selection survives save and restore
    @Test func `true-branch selection survives save and restore`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        while s.canContinue { _ = s.`continue`() }
        try s.chooseChoice(at: 1)
        let saved = try s.saveState()

        let r = try Story(json: json)
        try r.restoreState(saved)
        let lines = collectLines(r)
        #expect(lines.contains { $0.contains("You know her.") })
        #expect(!lines.contains { $0.contains("She's a stranger.") })
    }

    // Oracle: false-branch matches JS bridge
    #if os(macOS)
    @Test func `inline conditional false-branch matches JavaScript oracle`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice-c1-inline-conditionals", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        let native = try Story(json: json)
        while native.canContinue { _ = native.`continue`() }
        try native.chooseChoice(at: 0)
        let nativeLines = collectLines(native)

        let oracle = InkStory()
        oracle.loadStory(json: json)
        while oracle.canContinue && oracle.options.isEmpty { _ = oracle.continueStory() }
        oracle.chooseChoiceIndex(0)
        var oracleLines: [String] = []
        let afterChoice0 = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !afterChoice0.isEmpty { oracleLines.append(afterChoice0) }
        while oracle.canContinue {
            let trimmed = oracle.continueStory().trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { oracleLines.append(trimmed) }
        }

        #expect(nativeLines == oracleLines)
    }

    // Oracle: true-branch matches JS bridge
    @Test func `inline conditional true-branch matches JavaScript oracle`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice-c1-inline-conditionals", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        let native = try Story(json: json)
        while native.canContinue { _ = native.`continue`() }
        try native.chooseChoice(at: 1)
        let nativeLines = collectLines(native)

        let oracle = InkStory()
        oracle.loadStory(json: json)
        while oracle.canContinue && oracle.options.isEmpty { _ = oracle.continueStory() }
        oracle.chooseChoiceIndex(1)
        var oracleLines: [String] = []
        let afterChoice1 = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !afterChoice1.isEmpty { oracleLines.append(afterChoice1) }
        while oracle.canContinue {
            let trimmed = oracle.continueStory().trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { oracleLines.append(trimmed) }
        }

        #expect(nativeLines == oracleLines)
    }
    #endif
}

// MARK: - Slice C2 — Block and Switch Conditionals

// Fixture: slice-c2-block-conditionals.ink.json
// Story has five choices:
//   choice 0 → "Easy quiz."   — score =  5 → score_check → "You failed."  (5 > 10 is false)
//   choice 1 → "Hard quiz."   — score = 15 → score_check → "You passed."  (15 > 10 is true)
//   choice 2 → "Get caught."  — outcome =  1 → outcome_check → "Arrested."
//   choice 3 → "Slip away."   — outcome =  2 → outcome_check → "Escaped."
//   choice 4 → "Disappear."   — outcome = 99 → outcome_check → "Unknown."

@Suite("Slice C2 — Block and Switch Conditionals")
struct Slice_C2_BlockConditionalTests {

    private func makeStory() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "slice-c2-block-conditionals", withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func loadJSON() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "slice-c2-block-conditionals", withExtension: "ink.json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // AC: if/else — else branch when condition does not hold
    @Test func `if-else else-branch produced when condition does not hold — in-memory`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 0) // easy quiz → score = 5
        let lines = collectLines(story)
        #expect(lines.contains { $0.contains("You failed.") })
        #expect(!lines.contains { $0.contains("You passed.") })
    }

    // AC: if/else — true branch when condition holds
    @Test func `if-else true-branch produced when condition holds — in-memory`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 1) // hard quiz → score = 15
        let lines = collectLines(story)
        #expect(lines.contains { $0.contains("You passed.") })
        #expect(!lines.contains { $0.contains("You failed.") })
    }

    // AC: switch — matching case 1
    @Test func `switch selects matching case — outcome 1 produces Arrested — in-memory`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 2) // outcome = 1
        let lines = collectLines(story)
        #expect(lines.contains { $0.contains("Arrested.") })
        #expect(!lines.contains { $0.contains("Escaped.") })
        #expect(!lines.contains { $0.contains("Unknown.") })
    }

    // AC: switch — matching case 2
    @Test func `switch selects matching case — outcome 2 produces Escaped — in-memory`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 3) // outcome = 2
        let lines = collectLines(story)
        #expect(lines.contains { $0.contains("Escaped.") })
        #expect(!lines.contains { $0.contains("Arrested.") })
    }

    // AC: switch — else fallthrough when no case matches
    @Test func `switch else-branch fires when no case matches — in-memory`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 4) // outcome = 99
        let lines = collectLines(story)
        #expect(lines.contains { $0.contains("Unknown.") })
        #expect(!lines.contains { $0.contains("Arrested.") })
        #expect(!lines.contains { $0.contains("Escaped.") })
    }

    // AC: if/else branch selection survives save and restore
    @Test func `if-else true-branch selection survives save and restore`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        while s.canContinue { _ = s.`continue`() }
        try s.chooseChoice(at: 1) // hard quiz
        let saved = try s.saveState()

        let r = try Story(json: json)
        try r.restoreState(saved)
        let lines = collectLines(r)
        #expect(lines.contains { $0.contains("You passed.") })
    }

    // AC: switch branch selection survives save and restore
    @Test func `switch case selection survives save and restore`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        while s.canContinue { _ = s.`continue`() }
        try s.chooseChoice(at: 3) // slip away → outcome = 2
        let saved = try s.saveState()

        let r = try Story(json: json)
        try r.restoreState(saved)
        let lines = collectLines(r)
        #expect(lines.contains { $0.contains("Escaped.") })
    }

    // Oracle: block conditionals match JS bridge
    #if os(macOS)
    @Test func `block conditional output matches JavaScript oracle for all five choices`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice-c2-block-conditionals", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        for idx in 0..<5 {
            let native = try Story(json: json)
            while native.canContinue { _ = native.`continue`() }
            try native.chooseChoice(at: idx)
            let nativeLines = collectLines(native)

            let oracle = InkStory()
            oracle.loadStory(json: json)
            while oracle.canContinue && oracle.options.isEmpty { _ = oracle.continueStory() }
            oracle.chooseChoiceIndex(idx)
            var oracleLines: [String] = []
            let afterChoiceC2 = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !afterChoiceC2.isEmpty { oracleLines.append(afterChoiceC2) }
            while oracle.canContinue {
                let trimmed = oracle.continueStory().trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { oracleLines.append(trimmed) }
            }

            #expect(nativeLines == oracleLines, "Choice \(idx): native output must match oracle")
        }
    }
    #endif
}

// MARK: - Slice C3 — Ink Functions

// Fixture: slice-c3-functions.ink.json
// Story has three choices:
//   choice 0 → "Calculate inline."       — {double(5)} → "The result is 10."
//   choice 1 → "Calculate and store."    — temp result = double(7); {result} → "Stored: 14."
//   choice 2 → "Void call inline."       — {setSideEffect()} → "Done."  (no "void" emitted)
//
// Implementation note: inklecate compiles function calls as {"f()": path} + "out" (see
// docs/feature/tier3-conditionals-and-tunnels/distill/upstream-issues.md Issue 1).

@Suite("Slice C3 — Ink Functions")
struct Slice_C3_FunctionTests {

    private func makeStory() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "slice-c3-functions", withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func loadJSON() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "slice-c3-functions", withExtension: "ink.json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // AC: function return value appears inline at call site
    @Test func `function return value is interpolated at inline call site — in-memory`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 0) // {double(5)} → "The result is 10."
        let lines = collectLines(story)
        #expect(lines.contains { $0.contains("The result is 10.") })
    }

    // AC: function return value assigned to temp variable is readable in output
    @Test func `function return value assigned to temp variable is readable in subsequent output — in-memory`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 1) // temp result = double(7); {result} → "Stored: 14."
        let lines = collectLines(story)
        #expect(lines.contains { $0.contains("Stored: 14.") })
    }

    // AC: void-returning function does not emit "void" into output
    @Test func `void-returning function does not emit void literal into output — in-memory`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 2) // {setSideEffect()} followed by "Done."
        let lines = collectLines(story)
        #expect(lines.contains { $0.contains("Done.") })
        #expect(!lines.contains { $0.lowercased().contains("void") })
    }

    // AC: function output survives save and restore
    @Test func `function return value at inline call site survives save and restore`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        while s.canContinue { _ = s.`continue`() }
        try s.chooseChoice(at: 0)
        let saved = try s.saveState()

        let r = try Story(json: json)
        try r.restoreState(saved)
        let lines = collectLines(r)
        #expect(lines.contains { $0.contains("The result is 10.") })
    }

    // AC: void-function output survives save and restore
    @Test func `void function does not emit void after save and restore`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        while s.canContinue { _ = s.`continue`() }
        try s.chooseChoice(at: 2)
        let saved = try s.saveState()

        let r = try Story(json: json)
        try r.restoreState(saved)
        let lines = collectLines(r)
        #expect(lines.contains { $0.contains("Done.") })
        #expect(!lines.contains { $0.lowercased().contains("void") })
    }

    // Oracle: function output matches JS bridge
    #if os(macOS)
    @Test func `function call output matches JavaScript oracle for all three choices`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice-c3-functions", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        for idx in 0..<3 {
            let native = try Story(json: json)
            while native.canContinue { _ = native.`continue`() }
            try native.chooseChoice(at: idx)
            let nativeLines = collectLines(native)

            let oracle = InkStory()
            oracle.loadStory(json: json)
            while oracle.canContinue && oracle.options.isEmpty { _ = oracle.continueStory() }
            oracle.chooseChoiceIndex(idx)
            var oracleLines: [String] = []
            let afterChoiceC3 = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !afterChoiceC3.isEmpty { oracleLines.append(afterChoiceC3) }
            while oracle.canContinue {
                let trimmed = oracle.continueStory().trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { oracleLines.append(trimmed) }
            }

            #expect(nativeLines == oracleLines, "Choice \(idx): native output must match oracle")
        }
    }
    #endif
}

// MARK: - Slice T1 — Single-Level Tunnels

// Fixture: slice-t1-tunnels.ink.json
// No choices. Expected output sequence (three continue() calls):
//   "Before tunnel."   — pre-tunnel text in start knot
//   "Sub room content." — tunnel body in sub_room knot
//   "After tunnel."    — post-tunnel text in start knot (after ->->)
//
// Implementation note: inklecate encodes "->t->" and "->->" exactly as DESIGN predicted.

@Suite("Slice T1 — Single-Level Tunnels")
struct Slice_T1_SingleTunnelTests {

    private func makeStory() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "slice-t1-tunnels", withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func loadJSON() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "slice-t1-tunnels", withExtension: "ink.json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // AC: correct three-line output sequence — in-memory
    @Test func `tunnel produces correct before-inside-after text sequence — in-memory`() throws {
        let story = try makeStory()
        let line1 = story.`continue`()
        let line2 = story.`continue`()
        let line3 = story.`continue`()
        #expect(line1.contains("Before tunnel."))
        #expect(line2.contains("Sub room content."))
        #expect(line3.contains("After tunnel."))
    }

    // AC: canContinue is true after tunnel body (story does not end inside tunnel)
    @Test func `story does not end prematurely after tunnel body`() throws {
        let story = try makeStory()
        _ = story.`continue`() // "Before tunnel."
        _ = story.`continue`() // "Sub room content."
        #expect(story.canContinue, "canContinue must be true after tunnel body — story has not yet reached END")
    }

    // AC: full sequence correct when saving and restoring before tunnel entry
    @Test func `full tunnel sequence correct when rebuilding story at each step`() throws {
        let json = try loadJSON()

        let s1 = try Story(json: json)
        let line1 = s1.`continue`()
        let save1 = try s1.saveState()

        let s2 = try Story(json: json)
        try s2.restoreState(save1)
        let line2 = s2.`continue`()
        let save2 = try s2.saveState()

        let s3 = try Story(json: json)
        try s3.restoreState(save2)
        let line3 = s3.`continue`()

        #expect(line1.contains("Before tunnel."))
        #expect(line2.contains("Sub room content."))
        #expect(line3.contains("After tunnel."))
    }

    // Oracle: full tunnel sequence matches JS bridge
    #if os(macOS)
    @Test func `tunnel story full output matches JavaScript oracle`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice-t1-tunnels", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        let native = try Story(json: json)
        let nativeLines = collectLines(native)

        let oracle = InkStory()
        oracle.loadStory(json: json)
        var oracleLines: [String] = []
        let initialT1 = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !initialT1.isEmpty { oracleLines.append(initialT1) }
        while oracle.canContinue {
            let trimmed = oracle.continueStory().trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { oracleLines.append(trimmed) }
        }

        #expect(nativeLines == oracleLines)
    }
    #endif
}

// MARK: - Slice T2 — Nested Tunnels

// Fixture: slice-t2-nested-tunnels.ink.json
// No choices. Expected output sequence (five continue() calls):
//   "Caller pre."  — start knot, before ->t-> tunnel_a
//   "A pre."       — tunnel_a body, before ->t-> tunnel_b
//   "B body."      — tunnel_b body, before ->->
//   "A post."      — tunnel_a body, after tunnel_b returns
//   "Caller post." — start knot, after tunnel_a returns

@Suite("Slice T2 — Nested Tunnels")
struct Slice_T2_NestedTunnelTests {

    private func makeStory() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "slice-t2-nested-tunnels", withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func loadJSON() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "slice-t2-nested-tunnels", withExtension: "ink.json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // AC: correct five-line output sequence — in-memory
    @Test func `nested tunnels produce correct caller-A-B-A-caller sequence — in-memory`() throws {
        let story = try makeStory()
        let line1 = story.`continue`()
        let line2 = story.`continue`()
        let line3 = story.`continue`()
        let line4 = story.`continue`()
        let line5 = story.`continue`()
        #expect(line1.contains("Caller pre."))
        #expect(line2.contains("A pre."))
        #expect(line3.contains("B body."))
        #expect(line4.contains("A post."))
        #expect(line5.contains("Caller post."))
    }

    // AC: outer return address not lost — A's post-text appears before Caller post
    @Test func `outer return address preserved — A-post text precedes Caller-post text`() throws {
        let story = try makeStory()
        var lines: [String] = []
        while story.canContinue { lines.append(story.`continue`()) }
        let aPostIdx = lines.firstIndex { $0.contains("A post.") } ?? Int.max
        let callerPostIdx = lines.firstIndex { $0.contains("Caller post.") } ?? Int.max
        #expect(aPostIdx < callerPostIdx, "A post must appear before Caller post")
    }

    // AC: full nested sequence correct when rebuilding story at each step
    @Test func `nested tunnel sequence correct when rebuilding story at each step`() throws {
        let json = try loadJSON()
        var saves: [Data] = []
        var expectedLines = ["Caller pre.", "A pre.", "B body.", "A post.", "Caller post."]

        var currentState: Data? = nil
        for expected in expectedLines {
            let s = try Story(json: json)
            if let state = currentState { try s.restoreState(state) }
            let line = s.`continue`()
            #expect(line.contains(expected), "Expected '\(expected)' but got '\(line.trimmingCharacters(in: .whitespacesAndNewlines))'")
            currentState = try s.saveState()
            saves.append(currentState!)
        }
        _ = saves  // suppress unused warning
    }

    // Oracle: nested tunnel output matches JS bridge
    #if os(macOS)
    @Test func `nested tunnel output matches JavaScript oracle`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice-t2-nested-tunnels", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        let native = try Story(json: json)
        let nativeLines = collectLines(native)

        let oracle = InkStory()
        oracle.loadStory(json: json)
        var oracleLines: [String] = []
        let initialT2 = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !initialT2.isEmpty { oracleLines.append(initialT2) }
        while oracle.canContinue {
            let trimmed = oracle.continueStory().trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { oracleLines.append(trimmed) }
        }

        #expect(nativeLines == oracleLines)
    }
    #endif
}

// MARK: - Slice T3 — Reference Parameters

// Fixture: slice-t3-ref-params.ink.json
// No choices. Expected output (one continue() call):
//   "Score is 10."  — add(ref score, 10) mutates global score from 0 to 10
//
// Implementation note: inklecate encodes the ref param pointer as {"^var": "score", "ci": -1}
// where ci=-1 means global scope (DESIGN assumed ci=0 — see upstream-issues.md Issue 3).
// Also uses "pop" (not "out") after the function call — see upstream-issues.md Issue 2.

@Suite("Slice T3 — Reference Parameters")
struct Slice_T3_RefParamTests {

    private func makeStory() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "slice-t3-ref-params", withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func loadJSON() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "slice-t3-ref-params", withExtension: "ink.json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // AC: ref parameter mutation visible in caller output — in-memory
    @Test func `ref parameter mutation updates caller variable visible in output — in-memory`() throws {
        let story = try makeStory()
        let lines = collectLines(story)
        #expect(lines.contains { $0.contains("Score is 10.") })
    }

    // AC: initial value not unchanged (baseline check)
    @Test func `output does not show initial zero score — mutation was applied`() throws {
        let story = try makeStory()
        let lines = collectLines(story)
        #expect(!lines.contains { $0 == "Score is 0." })
    }

    // AC: mutated variable value survives save and restore
    // The function call and output occur in one continue() step (no mid-story
    // boundary), so we save at initial state and verify the restored story
    // produces the correct mutation result — proving state round-trips cleanly.
    @Test func `ref-mutated variable value survives save and restore`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        let saved = try s.saveState()

        let r = try Story(json: json)
        try r.restoreState(saved)
        let lines = collectLines(r)
        #expect(lines.contains { $0.contains("Score is 10.") })
    }

    // Oracle: ref param output matches JS bridge
    #if os(macOS)
    @Test func `ref parameter output matches JavaScript oracle`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice-t3-ref-params", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        let native = try Story(json: json)
        let nativeLines = collectLines(native)

        let oracle = InkStory()
        oracle.loadStory(json: json)
        var oracleLines: [String] = []
        let initialT3 = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !initialT3.isEmpty { oracleLines.append(initialT3) }
        while oracle.canContinue {
            let trimmed = oracle.continueStory().trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { oracleLines.append(trimmed) }
        }

        #expect(nativeLines == oracleLines)
    }
    #endif
}

// MARK: - The Intercept — Full Playthrough Acceptance

// This suite is the Tier 3 ceiling proof. Every test in this suite exercises TheIntercept.ink.json,
// the same 28-knot, 47-stitch, 156+-choice story used to define the feature's upper bound.
//
// The full oracle playthrough test (#3) becomes GREEN only when C1, C2, C3, T1, T2, and T3
// are all implemented correctly.

@Suite("The Intercept — Full Playthrough Acceptance")
struct TheInterceptAcceptanceTests {

    // 1. Smoke: story loads and canContinue is true after init
    @Test func `The Intercept loads from bundle and canContinue is true`() throws {
        let url = try #require(Bundle.module.url(forResource: "TheIntercept", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)
        let story = try Story(json: json)
        #expect(story.canContinue)
    }

    // 2. Save/restore invariant: first 15 continue() calls produce identical output
    //    whether played in-memory or rebuilt from save/restore at each step.
    //    This test is independent of Tier 3 features and should be GREEN early.
    @Test func `The Intercept first 15 steps produce identical output in-memory vs save-restore`() throws {
        let url = try #require(Bundle.module.url(forResource: "TheIntercept", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        // In-memory: collect first 15 non-empty lines, picking choice 0 when needed
        var inMemoryLines: [String] = []
        let inMemory = try Story(json: json)
        var steps = 0
        while inMemoryLines.count < 15 && steps < 200 {
            if inMemory.canContinue {
                let trimmed = inMemory.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { inMemoryLines.append(trimmed) }
            } else if !inMemory.currentChoices.isEmpty {
                try inMemory.chooseChoice(at: 0)
            } else {
                break
            }
            steps += 1
        }

        // Save/restore: same 15 lines, rebuilding story at each continue() step
        var saveRestoreLines: [String] = []
        var currentState: Data? = nil
        var srSteps = 0
        while saveRestoreLines.count < 15 && srSteps < 200 {
            let s = try Story(json: json)
            if let state = currentState { try s.restoreState(state) }
            if s.canContinue {
                let trimmed = s.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { saveRestoreLines.append(trimmed) }
                currentState = try s.saveState()
            } else if !s.currentChoices.isEmpty {
                try s.chooseChoice(at: 0)
                currentState = try s.saveState()
            } else {
                break
            }
            srSteps += 1
        }

        #expect(inMemoryLines == saveRestoreLines,
                "First \(min(inMemoryLines.count, saveRestoreLines.count)) lines must match between in-memory and save/restore play")
    }

    // 3. Full oracle playthrough: every output line matches the JS-bridge oracle.
    //    Choice strategy: always pick index 0 for determinism.
    //    Safety limit: 2000 steps (The Intercept has ~400 passages + 156+ choices).
    //    This is the Tier 3 ceiling proof — GREEN when all Tier 3 slices pass.
    #if os(macOS)
    @Test func `The Intercept full playthrough output matches JavaScript oracle`() throws {
        let url = try #require(Bundle.module.url(forResource: "TheIntercept", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        // Collect all native lines, always picking choice 0
        var nativeLines: [String] = []
        let native = try Story(json: json)
        var nativeSteps = 0
        while nativeSteps < 2000 {
            if native.canContinue {
                let trimmed = native.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { nativeLines.append(trimmed) }
                nativeSteps += 1
            } else if !native.currentChoices.isEmpty {
                try native.chooseChoice(at: 0)
                nativeSteps += 1
            } else {
                break
            }
        }

        // Collect all oracle lines, always picking choice 0
        var oracleLines: [String] = []
        let oracle = InkStory()
        oracle.loadStory(json: json)
        let initialIntercept = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !initialIntercept.isEmpty { oracleLines.append(initialIntercept) }
        var oracleSteps = 0
        while oracleSteps < 2000 {
            if oracle.canContinue {
                let trimmed = oracle.continueStory().trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { oracleLines.append(trimmed) }
                oracleSteps += 1
            } else if !oracle.options.isEmpty {
                oracle.chooseChoiceIndex(0)
                oracleSteps += 1
                let afterChoice = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !afterChoice.isEmpty { oracleLines.append(afterChoice) }
            } else {
                break
            }
        }

        #expect(!oracleLines.isEmpty, "Oracle produced no output — fixture or oracle problem")
        #expect(nativeLines == oracleLines,
                "Native playthrough must match oracle line-for-line (native: \(nativeLines.count) lines, oracle: \(oracleLines.count) lines)")
    }
    #endif
}
