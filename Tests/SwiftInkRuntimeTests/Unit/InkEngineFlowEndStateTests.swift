// Test Budget: 3 distinct behaviors x 2 = 6 max unit tests
// Behaviors:
//   B1 — the stop reason is ranOut when the root frame pops empty or a
//        choice-continuation root exhausts (no safe exit)
//   B2 — done / end / a refused pop stop with a safe exit (C# didSafeExit)
//   B3 — the stop reason and safe exit are reset at the start of every step()
//
// ADR-020 §3-4: transient engine state, never saved.

import Testing
import Foundation
@testable import SwiftInkRuntime

private func makeContainer(_ children: NodeKind..., named: [String: ContainerNode] = [:]) -> ContainerNode {
    ContainerNode(children: children, namedContent: named, flags: 0, name: nil)
}

@Suite struct InkEngineFlowEndStateTests {

    @Test func `the stop reason is ranOut when the root frame pops empty`() {
        let engine = InkEngine(root: makeContainer(.text("Hello"), .newline))

        engine.step()

        #expect(engine.stopReason == .ranOut)
        #expect(engine.didSafeExit == false)
    }

    @Test func `the stop reason is ranOut when a choice-continuation root exhausts`() throws {
        let body = makeContainer(.text("Picked"), .newline)
        let root = makeContainer(
            .choicePoint(target: PathReference(parsing: ".^.c-0"), flags: .isOnceOnly),
            named: ["c-0": body])
        let engine = InkEngine(root: root)
        engine.step()
        try #require(engine.currentChoices.count == 1)

        try engine.chooseChoice(at: 0)
        engine.step()

        #expect(engine.currentText == "Picked\n")
        #expect(engine.stopReason == .ranOut)
        #expect(engine.didSafeExit == false)
    }

    @Test(arguments: [
        NodeKind.controlCommand("done"),
        NodeKind.controlCommand("end"),
        NodeKind.controlCommand("->->"),
    ])
    func `done, end and a refused pop stop with a safe exit`(stop: NodeKind) {
        let engine = InkEngine(root: makeContainer(.text("Hello"), .newline, stop, .text("Never"), .newline))

        engine.step()

        #expect(engine.currentText == "Hello\n")
        #expect(engine.stopReason == .safeExit)
        #expect(engine.didSafeExit)
    }

    @Test func `a refused pop ends through the forced end with exactly one error`() {
        let engine = InkEngine(root: makeContainer(.controlCommand("~ret"), .text("Never"), .newline))

        engine.step()

        #expect(engine.currentErrors.count == 1)
        #expect(engine.state.isEnded)
        #expect(engine.state.pointer.index == Int.max)
        #expect(engine.canContinue == false)
    }

    @Test(arguments: [
        makeContainer(.text("Hello"), .newline),
        makeContainer(.text("Hello"), .newline, .controlCommand("end")),
    ])
    func `the stop reason and safe exit are reset at the start of every step`(root: ContainerNode) {
        let engine = InkEngine(root: root)
        engine.step()
        #expect(engine.stopReason != nil)

        engine.step()

        #expect(engine.stopReason == nil)
        #expect(engine.didSafeExit == false)
    }
}
