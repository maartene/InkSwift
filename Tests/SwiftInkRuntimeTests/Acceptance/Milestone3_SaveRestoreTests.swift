// @real-io
// Exercises: Story.saveState() and Story.restoreState(_:)

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct Milestone3_SaveRestoreTests {

    func loadStory() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "test.ink", withExtension: "json"))
        let json = try String(contentsOf: url, encoding: .utf8)
        return try Story(json: json)
    }

    // GIVEN: a story has been continued to a mid-story point
    // WHEN: saveState() is called, a new story is restored from that data
    // THEN: the restored story's canContinue matches the original story's canContinue

    @Test
    func `save and restore preserves the story position`() throws {
        // Given: a story continued to a mid-story point
        let story = try loadStory()
        _ = story.continue()
        let savedData = try story.saveState()

        // When: a new story is loaded and state restored
        let restored = try loadStory()
        try restored.restoreState(savedData)

        // Then: restored story continues from same position
        #expect(restored.canContinue == story.canContinue)
    }

    // GIVEN: a story saved at a specific point (choice point or mid-story)
    // WHEN: restoreState(_:) is called on a new Story instance from the same JSON
    // THEN: the restored instance's canContinue matches the original saved state

    @Test
    func `restore places the story at the saved choice point`() throws {
        // test.ink.json has a Choice knot — continue into it via the root to reach choices
        let story = try loadStory()
        // Exhaust the root passage; story lands at choice or end
        while story.canContinue { _ = story.continue() }

        let savedData = try story.saveState()

        let restored = try loadStory()
        try restored.restoreState(savedData)

        // canContinue and currentChoices count must match after restore
        #expect(restored.canContinue == story.canContinue)
        #expect(restored.currentChoices.count == story.currentChoices.count)
    }

    // GIVEN: arbitrary bytes that do not encode a valid StoryState
    // WHEN: restoreState(_:) is called
    // THEN: StoryError.invalidStateData is thrown

    @Test
    func `restoring with invalid data throws StoryError invalidStateData`() throws {
        let story = try loadStory()
        #expect(throws: StoryError.invalidStateData) {
            try story.restoreState(Data("not valid state data".utf8))
        }
    }

    // GIVEN: a story mid-playback with state saved twice at the same point
    // WHEN: both snapshots are restored and continued
    // THEN: both produce identical continuation state

    @Test
    func `save-restore round trip is stable across repeated saves`() throws {
        // Given: a story mid-playback, save twice at same point
        let story = try loadStory()
        _ = story.continue()
        let save1 = try story.saveState()
        let save2 = try story.saveState()

        // When: both snapshots are restored
        let restored1 = try loadStory()
        try restored1.restoreState(save1)

        let restored2 = try loadStory()
        try restored2.restoreState(save2)

        // Then: both produce identical continuation state
        #expect(restored1.canContinue == restored2.canContinue)
        if restored1.canContinue {
            let text1 = restored1.continue()
            let text2 = restored2.continue()
            #expect(text1 == text2)
        }
    }
}
