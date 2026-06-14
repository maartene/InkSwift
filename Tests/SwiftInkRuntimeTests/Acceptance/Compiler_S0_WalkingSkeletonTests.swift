// @walking_skeleton @driving_adapter @real-io @us-01 @kpi-1
//
// S0 / US-01 — the thinnest end-to-end vertical: compile one line of plain text
// IN-PROCESS (no external inklecate) into a runnable story, play it, and confirm
// the emitted line matches the inklecate oracle. Proves the whole spine
// (source → parse → codegen → runnable StoryBlueprint → execute → oracle match)
// on the smallest possible input.
//
// Driving port (DDD-10): InkCompiler.compile(source:) → StoryBlueprint, plus the
// Story(inkSource:) convenience surface (DWD-1). Both are exercised here.
//
// STATUS: RED by design. No SPIKE promoted a walking skeleton for this feature,
// so DISTILL authors S0 RED-scaffolded; it goes GREEN in DELIVER S0 (DWD-2).

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler S0 — Walking Skeleton (compile and play one line)")
struct Compiler_S0_WalkingSkeletonTests {

    @Test func `a one-line plain-text story compiles in-process and plays, matching the oracle`() throws {
        let result = try CompilerOracle.compileAndPlay("compile-skeleton-hello")

        #expect(result.oracle == ["Hello, world."])
        #expect(result.native == result.oracle)
    }

    @Test func `the convenience compile surface yields a playable story from source`() throws {
        let source = try CompilerOracle.source("compile-skeleton-hello")

        let story = try Story(inkSource: source)
        let lines = try CompilerOracle.play(story)

        #expect(lines == ["Hello, world."])
    }

    @Test func `an empty source compiles to a story that ends cleanly, matching the oracle`() throws {
        // The empty-source boundary (US-01 example 3). Compiled in-process; the
        // story produces no output and ends, exactly as the oracle does.
        let blueprint = try InkCompiler.compile(source: "")
        let lines = try CompilerOracle.play(Story(blueprint: blueprint))

        #expect(lines.isEmpty)
    }

    // Secondary driving port (D4): the optional Ink-JSON sink. Lower priority than
    // the no-round-trip primary path; covered here so the entry point is not TBU.
    @Test func `the secondary JSON sink emits Ink-JSON for a supported source`() throws {
        let json = try InkCompiler.emitJSON(source: "Hello, world.")

        #expect(json.contains("inkVersion"))
        #expect(json.contains("Hello, world."))
    }
}
