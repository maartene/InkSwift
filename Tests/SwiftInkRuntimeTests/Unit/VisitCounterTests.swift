// Tests for VisitCounter (ADR-022 §2): the one reader and writer of
// StoryState.visitCounts. The engine's recordVisit, `.readCount`, the `visit`
// control command and the host visit-count API all go through it.
//
// Test Budget: 5 behaviors x 2 = 10 unit tests max
//   B1 — record counts a visit to a container that tracks visits, and only then
//   B2 — read returns the count recorded under a key, 0 when none is
//   B3 — set overwrites the count under a key
//   B4 — canonicalising restored keys keeps a key that names no container
//        (merging split spellings is pinned by Engine_LegacyVisitCountRestoreTests)
//   B5 — a divert counts the containers it enters up to one the flow was in,
//        walking on through count-start-only ones entered at their start
//        (C# VisitChangedContainersDueToDivert; story-level: Engine_DivertVisitCountTests)

import Testing
@testable import SwiftInkRuntime

@Suite("VisitCounter")
struct VisitCounterTests {

    // An empty story tree: no key resolves, so every key keeps its spelling.
    private let counter = VisitCounter(
        resolver: ContainerPathResolver(root: ContainerNode(children: [], namedContent: [:], flags: 0, name: nil))
    )
    private let knot = ContainerPath(components: [.name("knot")])

    private func container(flags: Int) -> ContainerNode {
        ContainerNode(children: [], namedContent: [:], flags: flags, name: nil)
    }

    // MARK: - B1: record

    @Test func `recording two visits to a counted container reads back 2`() {
        var state = StoryState()

        counter.recordVisit(to: container(flags: 0x1), at: knot, in: &state)
        counter.recordVisit(to: container(flags: 0x1), at: knot, in: &state)

        #expect(counter.count(at: knot, in: state) == 2)
    }

    @Test(arguments: [0x0, 0x2, 0x4])
    func `recording a visit to a container without the count-visits flag counts nothing`(flags: Int) {
        var state = StoryState()

        counter.recordVisit(to: container(flags: flags), at: knot, in: &state)

        #expect(counter.count(at: knot, in: state) == 0)
    }

    // MARK: - B2: read

    @Test func `reading a key that was never visited gives 0`() {
        #expect(counter.count(at: knot, in: StoryState()) == 0)
    }

    @Test func `a count recorded under one key is not read under another`() {
        var state = StoryState()
        let byIndex = ContainerPath(components: [.index(0)])

        counter.recordVisit(to: container(flags: 0x1), at: knot, in: &state)

        #expect(counter.count(at: byIndex, in: state) == 0)
    }

    // MARK: - B3: set

    @Test func `setting a count overwrites it and later visits add to it`() {
        var state = StoryState()
        counter.recordVisit(to: container(flags: 0x1), at: knot, in: &state)

        counter.setCount(5, at: knot, in: &state)
        #expect(counter.count(at: knot, in: state) == 5)

        counter.recordVisit(to: container(flags: 0x1), at: knot, in: &state)
        #expect(counter.count(at: knot, in: state) == 6)
    }

    // MARK: - B4: canonicalise restored keys

    @Test func `canonicalising keys that name no container keeps each spelling and count`() {
        var state = StoryState()
        state.visitCounts = [knot: 2, ContainerPath(savedKey: "0.loop"): 1]

        counter.canonicaliseKeys(in: &state)

        #expect(state.visitCounts == [knot: 2, ContainerPath(savedKey: "0.loop"): 1])
    }

    // MARK: - B5: record a divert

    // root ─(named)─ knot [#f 1]: [gather, "b"]; gather [#f 5, "g"]: ["a", "a2"]
    private static let gather = ContainerNode(
        children: [.text("a"), .text("a2")], namedContent: [:], flags: 0x5, name: "g")
    private static let tree = ContainerNode(
        children: [.text("x")],
        namedContent: ["knot": ContainerNode(
            children: [.container(gather), .text("b")], namedContent: ["g": gather], flags: 0x1, name: "knot")],
        flags: 0, name: nil)
    private let divertCounter = VisitCounter(resolver: ContainerPathResolver(root: Self.tree))
    private let knotGather = ContainerPath(components: [.name("knot"), .name("g")])

    @Test(arguments: [
        // from the top level into the knot: the knot is new, so it counts
        (ContainerPath.root as ContainerPath?, 1),
        // from nowhere (moveToKnot): the same
        (nil, 1),
        // from inside the knot to the knot itself: nothing changed, nothing counts
        (ContainerPath(components: [.name("knot"), .name("g")]), 0),
    ])
    func `a divert to a knot counts it only when the flow was not already inside it`(
        previous: ContainerPath?, expected: Int
    ) {
        var state = StoryState()

        divertCounter.recordDivert(from: previous, landingAt: 0, in: knot, state: &state)

        #expect(divertCounter.count(at: knot, in: state) == expected)
        #expect(divertCounter.count(at: knotGather, in: state) == 0)
    }

    @Test(arguments: [(0, 1), (1, 0)])
    func `a divert back into a count-start-only gather counts it only when it lands at its start`(
        index: Int, expected: Int
    ) {
        var state = StoryState()

        divertCounter.recordDivert(from: knotGather, landingAt: index, in: knotGather, state: &state)

        #expect(divertCounter.count(at: knotGather, in: state) == expected)
        #expect(divertCounter.count(at: knot, in: state) == 0)
    }
}
