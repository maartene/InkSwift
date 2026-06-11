// Test Budget: 4 distinct behaviors x 2 = 8 max unit tests
// Behaviors:
//   B1 — Swift Int  → .int(n)   written to variablesState
//   B2 — Swift Bool → .bool(b)  written to variablesState (Bool checked before Int)
//   B3 — Swift String → .string(s) written to variablesState
//   B4 — unknown key → pure no-op (key count unchanged)

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("InkEngine setVariable bridging")
struct InkEngineSetVariableTests {

    // B1-B3: each Swift native type is bridged to the correct InkValue case
    // B2 implicit: Bool variant below verifies .bool (not .int) is stored
    @Test(arguments: [
        ("score",       42    as Any, InkValue.int(42)),
        ("ratio",       3.14  as Any, InkValue.float(3.14)),
        ("player_name", "Raya" as Any, InkValue.string("Raya")),
    ] as [(String, Any, InkValue)])
    func `setVariable bridges Swift value to correct InkValue`(
        key: String, value: Any, expected: InkValue
    ) {
        let root = ContainerNode(children: [], namedContent: [:], flags: 0, name: nil)
        let engine = InkEngine(root: root)
        engine.state.variablesState[key] = .int(0)  // pre-seed so key exists
        engine.setVariable(key, to: value)
        #expect(engine.state.variablesState[key] == expected)
    }

    // B2 explicit: Bool must be stored as .bool(true), not .int(1)
    // Swift's Bool conforms to BinaryInteger on some platforms; the check must be Bool-first.
    @Test func `setVariable stores Bool as bool InkValue not int`() {
        let root = ContainerNode(children: [], namedContent: [:], flags: 0, name: nil)
        let engine = InkEngine(root: root)
        engine.state.variablesState["flag"] = .bool(false)
        engine.setVariable("flag", to: true)
        #expect(engine.state.variablesState["flag"] == .bool(true))
    }

    // B4: unknown key — pure no-op; key count must not change
    @Test func `setVariable for unknown key leaves variablesState unchanged`() {
        let root = ContainerNode(children: [], namedContent: [:], flags: 0, name: nil)
        let engine = InkEngine(root: root)
        engine.state.variablesState["existing"] = .int(1)
        let countBefore = engine.state.variablesState.count
        engine.setVariable("nonexistent", to: 99)
        #expect(engine.state.variablesState.count == countBefore)
        #expect(engine.state.variablesState["nonexistent"] == nil)
    }
}
