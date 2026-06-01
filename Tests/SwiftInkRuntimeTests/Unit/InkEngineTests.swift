// Test Budget: 6 distinct behaviors x 2 = 12 max unit tests
// Behaviors:
//   B1 — init(root:) does not crash; canContinue is true for non-empty root
//   B2 — stepToNextLine() returns text collected from .text + .newline nodes
//   B3 — isEnded becomes true after a "done" control command; canContinue is false
//   B4 — chooseChoice(at:) throws StoryError.invalidChoiceIndex for out-of-range index
//   B5 — saveState() returns non-empty Data after initialization
//   B6 — restoreState(_:) throws StoryError.invalidStateData for undecodable input

import Testing
import Foundation
@testable import SwiftInkRuntime

// MARK: - Test helpers

private func makeContainer(_ children: NodeKind...) -> ContainerNode {
    ContainerNode(children: children, namedContent: [:], flags: 0, name: nil)
}

@Suite("InkEngine")
struct InkEngineTests {

    // B1a: init does not crash and canContinue is true for a non-empty root
    @Test("init with non-empty root does not crash and canContinue is true")
    func initWithNonEmptyRootCanContinue() {
        let container = makeContainer(.text("Hello"), .newline)
        let engine = InkEngine(root: container)
        #expect(engine.canContinue == true)
    }

    // B1b: canContinue is false for an empty root container
    @Test("canContinue is false for empty root container")
    func canContinueIsFalseForEmptyRoot() {
        let container = makeContainer()
        let engine = InkEngine(root: container)
        #expect(engine.canContinue == false)
    }

    // B2a: stepToNextLine returns text from a .text + .newline sequence (includes trailing \n)
    @Test("stepToNextLine returns text from text and newline nodes")
    func stepToNextLineReturnsText() {
        let container = makeContainer(.text("Hello, world"), .newline)
        let engine = InkEngine(root: container)
        let line = engine.stepToNextLine()
        #expect(line == "Hello, world\n")
    }

    // B2b: currentText reflects the last completed line after step() (includes trailing \n)
    @Test("step advances and currentText is the last completed line")
    func stepAdvancesAndCurrentTextIsLastCompletedLine() {
        let container = makeContainer(.text("First line"), .newline)
        let engine = InkEngine(root: container)
        engine.step()
        #expect(engine.currentText == "First line\n")
    }

    // B3a: isEnded is true after a "done" control command; canContinue is false
    @Test("canContinue is false after done control command")
    func canContinueIsFalseAfterDone() {
        let container = makeContainer(.controlCommand("done"))
        let engine = InkEngine(root: container)
        engine.step()
        #expect(engine.canContinue == false)
    }

    // B3b: canContinue is false after an "end" control command
    @Test("canContinue is false after end control command")
    func canContinueIsFalseAfterEnd() {
        let container = makeContainer(.controlCommand("end"))
        let engine = InkEngine(root: container)
        engine.step()
        #expect(engine.canContinue == false)
    }

    // B4a: chooseChoice(at:) throws invalidChoiceIndex for index beyond range
    @Test("chooseChoice throws invalidChoiceIndex for out-of-range index")
    func chooseChoiceThrowsForOutOfRangeIndex() throws {
        let container = makeContainer(.text("Start"), .newline)
        let engine = InkEngine(root: container)
        #expect(throws: StoryError.invalidChoiceIndex(99)) {
            try engine.chooseChoice(at: 99)
        }
    }

    // B4b: chooseChoice(at:) throws invalidChoiceIndex for negative index
    @Test("chooseChoice throws invalidChoiceIndex for negative index")
    func chooseChoiceThrowsForNegativeIndex() throws {
        let container = makeContainer(.text("Start"), .newline)
        let engine = InkEngine(root: container)
        #expect(throws: StoryError.invalidChoiceIndex(-1)) {
            try engine.chooseChoice(at: -1)
        }
    }

    // B5: saveState() returns non-empty Data
    @Test("saveState returns non-empty Data after initialization")
    func saveStateReturnsNonEmptyData() throws {
        let container = makeContainer(.text("Hello"), .newline)
        let engine = InkEngine(root: container)
        let data = try engine.saveState()
        #expect(data.count > 0)
    }

    // B6: restoreState(_:) throws invalidStateData for garbage bytes
    @Test("restoreState throws invalidStateData for undecodable input")
    func restoreStateThrowsForGarbageBytes() {
        let container = makeContainer(.text("Hello"), .newline)
        let engine = InkEngine(root: container)
        let garbage = Data([0xFF, 0xFE, 0xAB, 0xCD])
        #expect(throws: StoryError.invalidStateData) {
            try engine.restoreState(garbage)
        }
    }
}
