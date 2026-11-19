// Tests for VisitCounter (ADR-022 §2): the one reader and writer of
// StoryState.visitCounts. The engine's recordVisit, `.readCount`, the `visit`
// control command and the host visit-count API all go through it.
//
// Test Budget: 4 behaviors x 2 = 8 unit tests max
//   B1 — record counts a visit to a container that tracks visits, and only then
//   B2 — read returns the count recorded under a key, 0 when none is
//   B3 — set overwrites the count under a key
//   B4 — canonicalising restored keys keeps a key that names no container
//        (merging split spellings is pinned by Engine_LegacyVisitCountRestoreTests)

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
}
