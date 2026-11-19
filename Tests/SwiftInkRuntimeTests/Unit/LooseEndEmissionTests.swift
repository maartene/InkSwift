// #28 (step 02-03): a loose end is not `end`.
//
// inklecate 1.2.1 emits nothing where a knot's flow runs out: the rejoin after
// a block conditional and a choice body with no gather both just end (probed
// with `inklecate -o`). The native compiler emitted `end` there, which now
// discards a choice generated earlier in the same continue (C# ForceEnd) —
// e.g. a choice inside a conditional arm. An explicit `-> END` still lowers
// to `end`.

import Testing
@testable import SwiftInkRuntime

@Suite struct LooseEndEmissionTests {

    private static func containsEnd(_ container: ContainerNode) -> Bool {
        container.children.contains { node in
            if case .controlCommand("end") = node { return true }
            if case .container(let inner) = node { return containsEnd(inner) }
            return false
        } || container.namedContent.values.contains(where: containsEnd)
    }

    private static func knot(_ source: String) throws -> ContainerNode {
        let root = try InkCompiler.compile(source: source).root
        return try #require(root.namedContent["k"])
    }

    @Test(arguments: [
        """
        VAR x = 0
        -> k
        === k ===
        { x == 0:
            Zero.
            * From the arm
                -> elsewhere
        }
        After the block.

        === elsewhere ===
        Elsewhere.
        -> END
        """,
        """
        -> k
        === k ===
        Top.
        * A
            Body A.
        * B
            Body B.
        """,
    ])
    func `a knot's loose end emits no end control command`(source: String) throws {
        #expect(Self.containsEnd(try Self.knot(source)) == false)
    }

    @Test func `an explicit -> END in a knot still emits end`() throws {
        let source = """
        -> k
        === k ===
        Top.
        -> END
        """
        #expect(Self.containsEnd(try Self.knot(source)))
    }
}
