// @regression @real-io
//
// Engine regression — a nested container inside a FUNCTION BODY must pop one
// level when it exhausts, not end the function.
//
// `stepToNextLine`'s implicit-void-return branch fired whenever ANY container
// exhausted while a `fnret:` return address was pending. An inline conditional
// lowers to two sibling sub-containers — a conditional divert into the true
// branch, then an unconditional divert into the else branch — so when the
// condition was FALSE, exhausting the first sub-container was mistaken for the
// function body finishing. Execution returned to the caller immediately,
// skipping the else branch and everything after it in the function.
//
// Traced on the false path before the fix (node, frame path):
//
//   divert(".^.b", conditional) path=["say","4"]   <- not taken
//   controlCommand("pop")       path=["0"] idx=4   <- already back in the caller
//
// so `^no`, the function's trailing `nop` and its newline never ran.
//
// This is an ENGINE defect: it reproduces playing the committed inklecate json
// with no native compile involved, and affects anyone loading inklecate/Inky
// output. Ground truth from `inklecate -p`: yes / no / Done.
//
// NOTE: the natively compiled path for this same source is separately broken —
// it stops after the function call — and is deliberately NOT asserted here. See
// docs/reference/native-compiler-known-gaps.md; fixing it is compiler-side work
// tracked apart from this engine fix.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Engine — nested containers inside a function body")
struct Engine_FunctionBodyContainerTests {

    private func play(_ story: Story) -> [String] {
        var lines: [String] = []
        while story.canContinue {
            let line = story.`continue`().trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty == false { lines.append(line) }
        }
        return lines
    }

    // Scenario: both branches of a conditional inside a function emit their text,
    // and execution continues past the call — matching `inklecate -p`.
    @Test func `both branches of a conditional inside a function emit their text`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON("engine-function-conditional-branch"))

        #expect(play(story) == ["yes", "no", "Done."])
    }

    // Scenario: the false branch alone. Pinned separately because the true branch
    // never relied on container fall-through — it is reached by a taken divert —
    // so a true-only test would have passed against the defect.
    @Test func `a function whose conditional takes the false branch still emits and returns`() throws {
        let story = try Story(json: try CompilerOracle.oracleJSON("engine-function-conditional-branch"))
        let lines = play(story)

        #expect(lines.contains("no"))
        #expect(lines.last == "Done.")
    }
}
