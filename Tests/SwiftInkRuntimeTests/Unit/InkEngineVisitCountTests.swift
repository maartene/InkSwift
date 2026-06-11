// Test Budget: 4 distinct behaviors x 2 = 8 max unit tests
// Behaviors:
//   B1 — visitCount returns 0 for absent key
//   B2 — visitCount returns stored count for known key
//   B3 — setVisitCount writes value for a knot that exists in root.namedContent
//   B4 — setVisitCount is pure no-op for a knot absent from root.namedContent

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("InkEngine visitCount and setVisitCount")
struct InkEngineVisitCountTests {

    private func makeEmptyEngine() -> InkEngine {
        let root = ContainerNode(children: [], namedContent: [:], flags: 0, name: nil)
        return InkEngine(root: root)
    }

    private func makeEngineWithKnot(_ knotName: String) -> InkEngine {
        let knot = ContainerNode(children: [], namedContent: [:], flags: 1, name: knotName)
        let root = ContainerNode(children: [], namedContent: [knotName: knot], flags: 0, name: nil)
        return InkEngine(root: root)
    }

    // B1: visitCount returns 0 for absent key
    @Test func `visitCount returns 0 for absent key`() {
        let engine = makeEmptyEngine()
        #expect(engine.visitCount(forKnot: "prologue") == 0)
    }

    // B2: visitCount returns stored count for known key
    @Test func `visitCount returns stored count for known key`() {
        let engine = makeEmptyEngine()
        engine.state.visitCounts["prologue"] = 3
        #expect(engine.visitCount(forKnot: "prologue") == 3)
    }

    // B3: setVisitCount writes value for a knot that exists in root.namedContent
    @Test func `setVisitCount writes value for knot existing in root namedContent`() {
        let engine = makeEngineWithKnot("prologue")
        engine.setVisitCount(forKnot: "prologue", to: 5)
        #expect(engine.visitCount(forKnot: "prologue") == 5)
    }

    // B4: setVisitCount is pure no-op for a knot absent from root.namedContent
    @Test func `setVisitCount for knot absent from root namedContent does not create key`() {
        let engine = makeEmptyEngine()
        engine.setVisitCount(forKnot: "nonexistent", to: 5)
        #expect(engine.visitCount(forKnot: "nonexistent") == 0)
        #expect(engine.state.visitCounts["nonexistent"] == nil)
    }
}
