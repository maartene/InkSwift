// Tests for the stateless path resolver (D5): navigation over the immutable story
// tree against a passed-in current path, verified without constructing an engine.
// Driving port: ContainerPathResolver over a root decoded from real inklecate JSON.
//
// Fixture shapes relied on (see the .ink.json files):
// - slice03-read-counts: knot `café` keeps its content in the anonymous `café.0`,
//   with `c-0`/`c-1` named there and the conditional's `b` at `café.0.5.b`.
// - issue33-loop-with-choice: labelled gather `loop` is child 0 of `0` and also
//   named there, so it is both `0.0` and `0.loop`; its first child is an unnamed
//   sequence container; `g-0` is named-only content of `0`.
// - slice-bug-glue-after-choice: `$r1` / `$r2` anchors at `waited.0.g-0.15.$r1`
//   (child 5) and `waited.0.g-0.c-2.$r2` (child 5); gather `g-1` in `waited.0`.

import Foundation
import Testing
@testable import SwiftInkRuntime

@Suite("ContainerPathResolver")
struct ContainerPathResolverTests {

    // Test Budget:
    // Behavior 1: absolute paths walk the tree by index and by name
    // Behavior 2: relative paths apply the caret rule and the knot-namespace "0" fallback
    // Behavior 3: $-anchor paths resolve to the anchor's parent and the index past it
    // Behavior 4: read-count keys resolve like targets, falling back to concatenation
    // Behavior 5: the ancestor chain gives each ancestor's resume index
    // Behavior 6: every spelling of a container has one canonical path (name where named)
    // Behavior 7: a position's enclosing containers and a path's lineage, for divert counting
    // Budget = 7 behaviors × 2 = 14 unit tests max

    private static func resolver(for fixture: String) throws -> ContainerPathResolver {
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "ink.json"))
        return ContainerPathResolver(root: try InkDecoder().decode(Data(contentsOf: url)))
    }

    private static func path(_ dotted: String) -> ContainerPath {
        guard case .absolute(let path) = PathReference(parsing: dotted) else {
            preconditionFailure("not an absolute path: \(dotted)")
        }
        return path
    }

    // MARK: - Behavior 1: absolute navigation

    @Test(arguments: ["", "café", "café.0", "café.0.c-1", "café.0.5.b"])
    func `an absolute path to an existing container resolves to it`(dotted: String) throws {
        let resolver = try Self.resolver(for: Self.cafe)

        let node = try #require(resolver.node(at: Self.path(dotted)))

        #expect(resolver.absolutePath(of: PathReference(parsing: dotted), from: Self.path("")) == Self.path(dotted))
        #expect(node.children.isEmpty == false)
    }

    @Test(arguments: ["nowhere", "café.c-1", "café.0.99", "café.0.6", "café.0.007"])
    func `an absolute path that names no container resolves to nothing`(dotted: String) throws {
        let resolver = try Self.resolver(for: Self.cafe)

        #expect(resolver.node(at: Self.path(dotted)) == nil)
        #expect(resolver.absolutePath(of: PathReference(parsing: dotted), from: Self.path("")) == nil)
    }

    // MARK: - Behavior 2: relative resolution

    private static let cafe = "slice03-read-counts"
    private static let waited = "slice-bug-glue-after-choice"
    private static let labelledLoop = "issue33-loop-with-choice"

    @Test(arguments: [
        // first caret leaves the object for its container: no component dropped
        (cafe, ".^.c-0", "café.0", "café.0.c-0"),
        // nothing after the carets: the anchor itself
        (cafe, ".^.^", "café.0.c-0", "café.0"),
        // each further caret drops one component
        (waited, ".^.^.^.g-1", "waited.0.g-0.c-0", "waited.0.g-1"),
        (waited, ".^.^.15.s", "waited.0.g-0.c-2", "waited.0.g-0.15.s"),
    ])
    func `a relative path resolves against the current path`(
        fixture: String, target: String, current: String, expected: String
    ) throws {
        let resolver = try Self.resolver(for: fixture)

        #expect(resolver.absolutePath(of: PathReference(parsing: target), from: Self.path(current)) == Self.path(expected))
    }

    @Test func `a relative path that climbs above the root or misses resolves to nothing`() throws {
        let resolver = try Self.resolver(for: Self.cafe)

        #expect(resolver.anchorPath(parentSteps: 4, from: Self.path("café.0")) == nil)
        #expect(resolver.anchorPath(parentSteps: 3, from: Self.path("café.0")) == Self.path(""))
        #expect(resolver.anchorPath(parentSteps: 2, from: Self.path("café.0")) == Self.path("café"))
        #expect(resolver.absolutePath(of: PathReference(parsing: ".^.^.^.x"), from: Self.path("café.0")) == nil)
        #expect(resolver.absolutePath(of: PathReference(parsing: ".^.nowhere"), from: Self.path("café.0")) == nil)
    }

    // MARK: - Behavior 3: $-anchors

    @Test(arguments: [("waited.0.g-0.15.$r1", "waited.0.g-0.15", 6), ("waited.0.g-0.c-2.$r2", "waited.0.g-0.c-2", 6)])
    func `an anchor path resolves to its parent and the index just past the anchor`(
        dotted: String, parent: String, resumeIndex: Int
    ) throws {
        let resolver = try Self.resolver(for: Self.waited)

        let target = try #require(resolver.anchorTarget(of: Self.path(dotted)))

        #expect(target.resumeIndex == resumeIndex)
        #expect(target.container.children.count == resolver.node(at: Self.path(parent))?.children.count)
    }

    @Test(arguments: ["$r1", "waited.0.g-0.15", "waited.0.g-0.15.$r9", "waited.0.g-0.c-2.$r1"])
    func `a path that is not a resolvable anchor has no anchor target`(dotted: String) throws {
        let resolver = try Self.resolver(for: Self.waited)

        #expect(resolver.anchorTarget(of: Self.path(dotted)) == nil)
    }

    // MARK: - Behavior 4: read-count keys

    // A relative key whose destination does not exist names no visit count (C#
    // Story.cs resolves CNT? with ResolvePath(pathForCount).container; there is no
    // path concatenation), so it is nil like an unresolvable divert target.
    @Test func `a read-count key resolves relative keys and has no key for a missing destination`() throws {
        let resolver = try Self.resolver(for: Self.cafe)
        let current = Self.path("café.0.c-0")

        #expect(resolver.readCountKey(for: PathReference(parsing: "café"), from: current) == Self.path("café"))
        #expect(resolver.readCountKey(for: PathReference(parsing: ".^.^.c-1"), from: current) == Self.path("café.0.c-1"))
        #expect(resolver.readCountKey(for: PathReference(parsing: ".^.^.ghost"), from: current) == nil)
        #expect(resolver.readCountKey(for: PathReference(parsing: ".^.^.^.^.^"), from: current) == nil)
    }

    // MARK: - Behavior 5: ancestor chain

    @Test func `the ancestor chain lists each ancestor with the index its frame resumes at`() throws {
        let resolver = try Self.resolver(for: Self.waited)

        let chain = resolver.ancestors(along: Self.path("waited.0.g-0.15"))

        #expect(chain.map(\.path) == ["", "waited", "waited.0", "waited.0.g-0"].map(Self.path))
        // named children resume at the parent's end, numeric children just past themselves
        #expect(chain.map(\.resumeIndex) == [
            try #require(resolver.node(at: Self.path(""))).children.count, 1, 1, 16,
        ])
        #expect(resolver.ancestors(along: Self.path("waited.nowhere.0")).map(\.path) == [Self.path("")])
    }

    // MARK: - Behavior 6: canonical path

    // C# Object.path names a child wherever it has a name and indexes it otherwise
    // (Object.cs:86-89), so the index and the name spelling of one labelled gather
    // are one container with one path.
    @Test(arguments: [
        ("0.0", "0.loop"), ("0.loop", "0.loop"),
        ("0.0.0", "0.loop.0"), ("0.loop.0", "0.loop.0"),
        ("0.0.c-0", "0.loop.c-0"), ("0.g-0", "0.g-0"), ("0", "0"), ("", ""),
    ])
    func `every spelling of a container has the same canonical path`(dotted: String, canonical: String) throws {
        let resolver = try Self.resolver(for: Self.labelledLoop)

        #expect(resolver.canonicalPath(of: Self.path(dotted)) == Self.path(canonical))
    }

    @Test(arguments: ["nowhere", "0.7", "0.loop.nowhere"])
    func `a path that names no container has no canonical path`(dotted: String) throws {
        let resolver = try Self.resolver(for: Self.labelledLoop)

        #expect(resolver.canonicalPath(of: Self.path(dotted)) == nil)
    }

    // MARK: - Behavior 7: enclosures and lineage

    @Test(arguments: [
        // the labelled gather: first child of `0`, which is first child of the root
        ("0.0", 0, [("0.loop", true), ("0", true), ("", true)]),
        // mid-way into it: not at its start; the chain above is unchanged
        ("0.loop", 1, [("0.loop", false), ("0", true), ("", true)]),
        // `g-0` is named-only content of `0`: never its first child
        ("0.g-0", 0, [("0.g-0", true), ("0", false), ("", true)]),
        // past the last child: nothing resolves
        ("0.loop", 99, []),
    ])
    func `a position's enclosures run from its container to the root, canonically`(
        dotted: String, index: Int, expected: [(String, Bool)]
    ) throws {
        let resolver = try Self.resolver(for: Self.labelledLoop)

        let chain = resolver.enclosures(ofChild: index, in: Self.path(dotted))

        #expect(chain.map(\.path) == expected.map { Self.path($0.0) })
        #expect(chain.map(\.entersAtFirstChild) == expected.map(\.1))
    }

    @Test func `a path's lineage is its canonical path and every ancestor, the root included`() throws {
        let resolver = try Self.resolver(for: Self.labelledLoop)

        #expect(resolver.lineage(of: Self.path("0.0")) == [Self.path(""), Self.path("0"), Self.path("0.loop")])
    }
}
