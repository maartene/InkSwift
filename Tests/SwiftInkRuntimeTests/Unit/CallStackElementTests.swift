import Testing
import Foundation
@testable import SwiftInkRuntime

// Test Budget: 4 distinct behaviors x 2 = 8 max unit tests
// Behaviors:
//   B1 — a legacy return-stack string decodes to the matching call kind and
//        re-encodes byte-identically (ADR-018 wire)
//   B2 — a string that fits neither legacy form is rejected
//   B3 — the golden mid-tunnel save's return stack decodes to a tunnel element
//        and re-encodes as the same legacy strings
//   B4 — a pop only removes an element of the requested kind (C# CallStack.CanPop/Pop)
//
// The cross-build guarantee for the function-return form ("fnret:path|N") is
// codec-only: these round-trip tests, not a golden save. No save can hold a
// function element — ink allows no choices inside a function, function bodies
// run synchronously inside continue(), and a save is only taken between
// continue() calls (see TypedPaths_LegacySaveCompatibilityTests).

/// A legacy return-stack entry and the element it stands for.
struct LegacyReturnEntry: Sendable, CustomTestStringConvertible {
    let wire: String
    let kind: CallKind
    let returnPath: [String]
    let returnIndex: Int

    var testDescription: String { wire }

    var element: CallStackElement {
        CallStackElement(kind: kind, returnPath: ContainerPath(savedComponents: returnPath), returnIndex: returnIndex)
    }
}

private let legacyReturnEntries: [LegacyReturnEntry] = [
    LegacyReturnEntry(wire: "knot.3", kind: .tunnel, returnPath: ["knot"], returnIndex: 3),
    LegacyReturnEntry(wire: "7", kind: .tunnel, returnPath: [], returnIndex: 7),
    LegacyReturnEntry(wire: "start.waited.0.g-6.2.4.b.2", kind: .tunnel,
                      returnPath: ["start", "waited", "0", "g-6", "2", "4", "b"], returnIndex: 2),
    LegacyReturnEntry(wire: "fnret:knot|4", kind: .function, returnPath: ["knot"], returnIndex: 4),
    LegacyReturnEntry(wire: "fnret:|0", kind: .function, returnPath: [], returnIndex: 0),
    LegacyReturnEntry(wire: "fnret:knot.stitch.0.g-2|11", kind: .function,
                      returnPath: ["knot", "stitch", "0", "g-2"], returnIndex: 11),
]

private let tunnel = CallStackElement(kind: .tunnel, returnPath: ContainerPath(savedComponents: ["a"]), returnIndex: 1)
private let function = CallStackElement(kind: .function, returnPath: ContainerPath(savedComponents: ["f"]), returnIndex: 2)

@Suite struct CallStackElementTests {

    private func decodeStack(_ wire: [String]) throws -> [CallStackElement] {
        try JSONDecoder().decode([CallStackElement].self, from: JSONEncoder().encode(wire))
    }

    private func encodeStack(_ stack: [CallStackElement]) throws -> [String] {
        try JSONDecoder().decode([String].self, from: JSONEncoder().encode(stack))
    }

    // GIVEN: a legacy return-stack string ("path.N" tunnel or "fnret:path|N" function)
    // WHEN: it is decoded and encoded again
    // THEN: it is the matching typed element and re-encodes to the identical string

    @Test(arguments: legacyReturnEntries)
    func `a legacy return-stack entry decodes to its call kind and re-encodes identically`(
        entry: LegacyReturnEntry
    ) throws {
        let decoded = try decodeStack([entry.wire])

        #expect(decoded == [entry.element])
        #expect(try encodeStack(decoded) == [entry.wire])
    }

    // GIVEN: a string that is neither "path.N" nor "fnret:path|N"
    // WHEN: it is decoded as a return-stack entry
    // THEN: decoding fails rather than inventing a return position

    @Test(arguments: ["", "knot", "knot.x", "fnret:knot", "fnret:knot|x", "knot.007"])
    func `a string that fits neither legacy form is rejected`(wire: String) {
        #expect(throws: DecodingError.self) { try decodeStack([wire]) }
    }

    // GIVEN: the golden save taken inside The Intercept's `missing_reel` tunnel
    // WHEN: it is decoded as a StoryState and encoded again
    // THEN: its return stack is the one tunnel element and persists as the same legacy strings

    @Test func `the golden mid-tunnel save's return stack is a tunnel element that re-encodes identically`() throws {
        let url = try #require(Bundle.module.url(forResource: "legacy-save-mid-tunnel", withExtension: "json"))
        let golden = try Data(contentsOf: url)

        let state = try JSONDecoder().decode(StoryState.self, from: golden)
        let resaved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
        let original = try JSONSerialization.jsonObject(with: golden) as? [String: Any]

        #expect(state.returnStack == [
            CallStackElement(kind: .tunnel,
                             returnPath: ContainerPath(savedComponents: ["start", "waited", "0", "g-6", "2", "4", "b"]),
                             returnIndex: 2),
        ])
        #expect(resaved?["returnStack"] as? [String] == original?["returnStack"] as? [String])
    }

    // GIVEN: a return stack (empty, tunnel on top, or function on top)
    // WHEN: an element of a given kind is popped
    // THEN: only a matching top element is returned and removed; otherwise nothing changes

    @Test(arguments: [
        ([], CallKind.tunnel, nil),
        ([], CallKind.function, nil),
        ([function, tunnel], CallKind.tunnel, tunnel),
        ([function, tunnel], CallKind.function, nil),
        ([tunnel, function], CallKind.function, function),
        ([tunnel, function], CallKind.tunnel, nil),
    ] as [([CallStackElement], CallKind, CallStackElement?)])
    func `a pop only removes a top element of the requested kind`(
        stack: [CallStackElement], kind: CallKind, expected: CallStackElement?
    ) {
        var popped = stack

        let element = popped.pop(kind)

        #expect(element == expected)
        #expect(popped == (expected == nil ? stack : Array(stack.dropLast())))
    }
}
