// @real-io
// Tier-3 follow-on acceptance test — a NON-TRIVIAL partial playthrough of
// The Intercept driven by a hard-coded choice script. The previous
// "always-pick-choice-0" Intercept oracle test in Milestone5_* exits early
// on every nested choice (it picks "Think", loops back, picks "Think" again,
// never reaching the Plan / Wait branches that exercise the function call
// and ref-parameter mechanisms). This suite drives the engine through a
// deterministic varied path so the assertion is meaningful.
//
// Driving port: Story facade — init(json:), continue(), chooseChoice(at:)
// Oracle: the committed TheIntercept_oracle_walkthrough.json fixture, derived
//         once from InkSwift.InkStory (JS bridge) on the same choice script.
//
// Regeneration: set REGEN_INTERCEPT_ORACLE=1 in the environment, run the
// "regenerate The Intercept oracle walkthrough fixture" test, then commit
// the produced JSON. See DWD-07 in distill/wave-decisions.md.

import Testing
import Foundation
@testable import SwiftInkRuntime
#if os(macOS)
import InkSwift
#endif

// MARK: - Walkthrough specification (single source of truth)

/// Deterministic, non-trivial choice index sequence. At each choice point,
/// the i-th entry (modulo the choice count, modulo the sequence length)
/// selects the branch. The sequence intentionally avoids "always 0":
/// it picks Plan (2) early to exercise the C3 function call (`lower(forceful)`),
/// then drifts through Dissemble / Divert variants in later turns to hit
/// `raise(forceful)` and `raise(evasive)`. Reference-parameter mutation
/// (T3) is exercised by every function call.
private let interceptChoiceScript: [Int] =
    [0, 2, 1, 0, 0, 1, 2, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]

/// Maximum number of non-empty output lines to capture (the user-requested
/// upper bound of the 50-100 range).
private let interceptMaxOutputLines = 100

/// Hard safety ceiling on engine step iterations — protects against an
/// infinite-loop regression in the engine. The Intercept's first 100 lines
/// take well under this many steps under any reasonable choice path.
private let interceptStepCeiling = 2000

// MARK: - Fixture format

private struct InterceptOracleWalkthrough: Codable {
    let choiceScript: [Int]
    let maxOutputLines: Int
    let expectedLines: [String]
}

// MARK: - Shared helpers

private func collectExpectedFromFixture() throws -> InterceptOracleWalkthrough {
    let url = try #require(
        Bundle.module.url(forResource: "TheIntercept_oracle_walkthrough", withExtension: "json"),
        "Fixture TheIntercept_oracle_walkthrough.json is missing — regenerate by running the 'regenerate The Intercept oracle walkthrough fixture' test with REGEN_INTERCEPT_ORACLE=1 set in the environment, then commit the produced file."
    )
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(InterceptOracleWalkthrough.self, from: data)
}

/// Drive the native Story through the choice script, capturing trimmed
/// non-empty output lines until `interceptMaxOutputLines` are collected,
/// the story ends, or the step ceiling is reached.
private func playNativeWalkthrough(json: String) throws -> [String] {
    let story = try Story(json: json)
    var lines: [String] = []
    var choiceCursor = 0
    var steps = 0
    while lines.count < interceptMaxOutputLines && steps < interceptStepCeiling {
        if story.canContinue {
            let trimmed = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append(trimmed) }
        } else if !story.currentChoices.isEmpty {
            let count = story.currentChoices.count
            let raw = interceptChoiceScript[choiceCursor % interceptChoiceScript.count]
            let pick = raw % count
            try story.chooseChoice(at: pick)
            choiceCursor += 1
        } else {
            break
        }
        steps += 1
    }
    return lines
}

// MARK: - The Intercept — Non-Trivial Playthrough Acceptance

@Suite("The Intercept — Non-Trivial Playthrough Acceptance")
struct TheInterceptNonTrivialPlaythroughTests {

    // The native engine, driven by the same choice script that produced the
    // committed oracle fixture, must reproduce the oracle's first
    // `interceptMaxOutputLines` lines exactly.
    @Test func `The Intercept non-trivial playthrough matches the committed oracle walkthrough line-for-line`() throws {
        let url = try #require(Bundle.module.url(forResource: "TheIntercept", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        let expected = try collectExpectedFromFixture()

        // Defensive: the committed fixture must be derived from the same
        // choice script and length that the test is about to replay.
        // A mismatch means the fixture is stale and must be regenerated.
        #expect(expected.choiceScript == interceptChoiceScript,
                "Fixture choiceScript does not match interceptChoiceScript — regenerate the fixture")
        #expect(expected.maxOutputLines == interceptMaxOutputLines,
                "Fixture maxOutputLines does not match interceptMaxOutputLines — regenerate the fixture")

        let nativeLines = try playNativeWalkthrough(json: json)

        // The native run must collect a meaningful number of lines.
        // (Under-shooting would mean the engine stalled — the assertion
        // below would also catch that, but this gives a clearer failure
        // message in that case.)
        #expect(nativeLines.count >= 50,
                "Native playthrough produced only \(nativeLines.count) lines (<50) — the engine likely stalled before reaching the requested depth")

        // Line-for-line equality on the captured prefix.
        let prefix = min(nativeLines.count, expected.expectedLines.count)
        for i in 0..<prefix {
            #expect(nativeLines[i] == expected.expectedLines[i],
                    "Line \(i) mismatch:\n  native:   \(nativeLines[i])\n  expected: \(expected.expectedLines[i])")
        }
        #expect(nativeLines.count == expected.expectedLines.count,
                "Native produced \(nativeLines.count) lines but oracle fixture has \(expected.expectedLines.count) lines")
    }
}

// MARK: - Fixture regeneration (manual, REGEN_INTERCEPT_ORACLE=1)

// This suite contains a single test that drives the JS-bridge oracle through
// the same choice script and writes the resulting fixture next to the test
// source file. It is gated on REGEN_INTERCEPT_ORACLE=1 so it is a no-op in
// normal `swift test` runs and never affects CI.
//
// Usage:
//   REGEN_INTERCEPT_ORACLE=1 swift test --filter "regenerate The Intercept oracle walkthrough fixture"
//   git add Tests/SwiftInkRuntimeTests/TheIntercept_oracle_walkthrough.json
//
// After regeneration, ensure Package.swift's SwiftInkRuntimeTests resources
// list includes the file.

#if os(macOS)
@Suite("The Intercept — Oracle Walkthrough Fixture Regeneration")
struct TheInterceptOracleFixtureRegenerationTests {

    @Test func `regenerate The Intercept oracle walkthrough fixture`() throws {
        guard ProcessInfo.processInfo.environment["REGEN_INTERCEPT_ORACLE"] != nil else {
            // No-op in normal runs. Exit early without failure.
            return
        }
        let filePath = #filePath

        let url = try #require(Bundle.module.url(forResource: "TheIntercept", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        let oracle = InkStory()
        oracle.loadStory(json: json)

        var oracleLines: [String] = []
        var choiceCursor = 0

        // Capture the initial line emitted by loadStory().
        let initial = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !initial.isEmpty { oracleLines.append(initial) }

        var steps = 0
        while oracleLines.count < interceptMaxOutputLines && steps < interceptStepCeiling {
            if oracle.canContinue {
                let trimmed = oracle.continueStory().trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { oracleLines.append(trimmed) }
            } else if !oracle.options.isEmpty {
                let count = oracle.options.count
                let raw = interceptChoiceScript[choiceCursor % interceptChoiceScript.count]
                let pick = raw % count
                oracle.chooseChoiceIndex(pick)
                choiceCursor += 1
                // chooseChoiceIndex calls continueStory() internally, which
                // emits the next line into currentText. Capture it.
                let afterChoice = oracle.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !afterChoice.isEmpty { oracleLines.append(afterChoice) }
            } else {
                break
            }
            steps += 1
        }

        let trimmed = Array(oracleLines.prefix(interceptMaxOutputLines))
        let fixture = InterceptOracleWalkthrough(
            choiceScript: interceptChoiceScript,
            maxOutputLines: interceptMaxOutputLines,
            expectedLines: trimmed
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(fixture)

        // Write next to the existing test resources (one level up from
        // this file's Acceptance/ folder).
        let testSourceDir = (filePath as NSString).deletingLastPathComponent
        let testTargetDir = (testSourceDir as NSString).deletingLastPathComponent
        let outURL = URL(fileURLWithPath: testTargetDir)
            .appendingPathComponent("TheIntercept_oracle_walkthrough.json")
        try data.write(to: outURL, options: .atomic)

        #expect(trimmed.count >= 50,
                "Oracle only produced \(trimmed.count) lines (<50) — choice script or oracle is broken")
    }
}
#endif
