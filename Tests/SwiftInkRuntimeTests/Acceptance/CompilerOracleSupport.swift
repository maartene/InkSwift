// Shared execution-equivalence oracle harness for the native-ink-compiler
// acceptance suite (DISTILL). Reuses the established committed-fixture pattern
// (Milestone5b): inklecate compiles each supported `.ink` source OFFLINE into a
// committed `.ink.json` (REGEN-gated, test-only); CI never invokes inklecate.
//
// The compiler equivalence assertion compiles the SAME `.ink` source NATIVELY
// (InkCompiler.compile → StoryBlueprint), plays it through the production
// runtime, and compares it line-for-line / choice-for-choice against the
// inklecate oracle played through the SAME runtime along the SAME choice path
// (KPI #1 — execution-equivalence; D5 Level-1 correctness).
//
// inklecate is test-only/offline (DDD-10). Regeneration: re-run
//   inklecate -o <name>.ink.json <name>.ink
// for each supported fixture and commit the result.

import Testing
import Foundation
@testable import SwiftInkRuntime

enum CompilerOracle {

    // MARK: Fixture loading

    /// The `.ink` SOURCE the native compiler consumes (the driving-port input).
    static func source(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "ink"),
            "Missing source fixture \(name).ink"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The committed inklecate oracle (`.ink.json`) for a supported fixture.
    static func oracleJSON(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "ink.json"),
            "Missing oracle fixture \(name).ink.json — regenerate offline with `inklecate -o \(name).ink.json \(name).ink` and commit it."
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Deterministic playthrough

    /// Drive a story along a fixed choice script, capturing trimmed non-empty
    /// output lines until `maxLines` are collected, the story ends, or the step
    /// ceiling trips (infinite-loop guard). An empty script always picks 0.
    static func play(
        _ story: Story,
        choiceScript: [Int] = [],
        maxLines: Int = 200,
        stepCeiling: Int = 5000
    ) throws -> [String] {
        var lines: [String] = []
        var cursor = 0
        var steps = 0
        while lines.count < maxLines && steps < stepCeiling {
            if story.canContinue {
                let trimmed = story.`continue`()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { lines.append(trimmed) }
            } else if !story.currentChoices.isEmpty {
                let count = story.currentChoices.count
                let raw = choiceScript.isEmpty ? 0 : choiceScript[cursor % choiceScript.count]
                try story.chooseChoice(at: raw % count)
                cursor += 1
            } else {
                break
            }
            steps += 1
        }
        return lines
    }

    // MARK: Execution-equivalence

    /// Compile `name`.ink NATIVELY and play it; play the inklecate oracle
    /// (`name`.ink.json) through the same runtime; return both line lists for the
    /// caller to compare. Native compile is performed AFTER the oracle is built,
    /// so a not-yet-implemented compiler surfaces as a thrown `CompileError`
    /// (RED: missing functionality), never a fixture/setup failure (BROKEN).
    static func compileAndPlay(
        _ name: String,
        choiceScript: [Int] = []
    ) throws -> (native: [String], oracle: [String]) {
        let oracleStory = try Story(json: try oracleJSON(name))
        let oracle = try play(oracleStory, choiceScript: choiceScript)

        let blueprint = try InkCompiler.compile(source: try source(name))
        let native = try play(Story(blueprint: blueprint), choiceScript: choiceScript)

        return (native, oracle)
    }
}
