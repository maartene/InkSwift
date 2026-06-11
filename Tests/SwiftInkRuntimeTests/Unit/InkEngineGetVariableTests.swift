// Test Budget: 5 distinct behaviors x 2 = 10 max unit tests
// Behaviors:
//   B1 — .int(n)   bridges to Swift Int
//   B2 — .float(f) bridges to Swift Double
//   B3 — .string(s) bridges to Swift String
//   B4 — .bool(b)  bridges to Swift Bool
//   B5 — absent key (and .variablePointer) returns nil

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("InkEngine getVariable bridging")
struct InkEngineGetVariableTests {

    // B1-B4: each InkValue case bridges to the correct Swift native type
    @Test(arguments: [
        ("score",        InkValue.int(7),         7     as Any, "Int"),
        ("ratio",        InkValue.float(3.5),      3.5   as Any, "Double"),
        ("name",         InkValue.string("hero"),  "hero" as Any, "String"),
        ("flag",         InkValue.bool(true),      true  as Any, "Bool"),
    ] as [(String, InkValue, Any, String)])
    func `getVariable bridges InkValue to native Swift type`(
        key: String, inkValue: InkValue, expected: Any, label: String
    ) {
        let root = ContainerNode(children: [], namedContent: [:], flags: 0, name: nil)
        let engine = InkEngine(root: root)
        engine.state.variablesState[key] = inkValue
        let result = engine.getVariable(key)
        switch label {
        case "Int":    #expect(result as? Int    == expected as? Int)
        case "Double": #expect(result as? Double == expected as? Double)
        case "String": #expect(result as? String == expected as? String)
        case "Bool":   #expect(result as? Bool   == expected as? Bool)
        default: Issue.record("Unexpected label: \(label)")
        }
    }

    // B5: absent key returns nil
    @Test func `getVariable returns nil for absent key`() {
        let root = ContainerNode(children: [], namedContent: [:], flags: 0, name: nil)
        let engine = InkEngine(root: root)
        #expect(engine.getVariable("ghost") == nil)
    }
}
