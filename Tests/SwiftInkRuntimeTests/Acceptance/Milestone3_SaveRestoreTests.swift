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

    // GIVEN: a story has been continued so currentText is non-empty
    // WHEN: state is saved and restored into a fresh Story
    // THEN: currentText on the restored story equals the original story's currentText

    @Test
    func `currentText is preserved across save and restore`() throws {
        let story = try loadStory()
        _ = story.continue()
        let textBeforeSave = story.currentText

        let savedData = try story.saveState()
        let restored = try loadStory()
        try restored.restoreState(savedData)

        #expect(restored.currentText == textBeforeSave)
    }

    // GIVEN: a real-compiler story where a choice has been made and partially continued
    // WHEN: state is saved after the first continue() post-choice, then restored
    // THEN: continuing the restored story still produces the gather text
    // Regression for: rebuildStackFromFrames always used root for frame 0, losing the
    // non-root container set by applyDivert after choice navigation.

    @Test
    func `gather text appears after save-restore between choice and gather`() throws {
        let json = #"""
        {"inkVersion":21,"root":[["^Once upon a time...","\n",["ev",{"^->":"0.2.$r1"},{"temp=":"$r"},"str",{"->":".^.s"},[{"#n":"$r1"}],"/str","/ev",{"*":"0.c-0","flg":18},{"s":["^There were two choices.",{"->":"$r","var":true},null]}],["ev",{"^->":"0.3.$r1"},{"temp=":"$r"},"str",{"->":".^.s"},[{"#n":"$r1"}],"/str","/ev",{"*":"0.c-1","flg":18},{"s":["^There were four lines of content.",{"->":"$r","var":true},null]}],{"c-0":["ev",{"^->":"0.c-0.$r2"},"/ev",{"temp=":"$r"},{"->":"0.2.s"},[{"#n":"$r2"}],"\n",{"->":"0.g-0"},{"#f":5}],"c-1":["ev",{"^->":"0.c-1.$r2"},"/ev",{"temp=":"$r"},{"->":"0.3.s"},[{"#n":"$r2"}],"\n",{"->":"0.g-0"},{"#f":5}],"g-0":["^They lived happily ever after.","\n","end",["done",{"#f":5,"#n":"g-1"}],{"#f":5}]}],"done",{"#f":1}],"listDefs":{}}
        """#

        let story = try Story(json: json)
        while story.canContinue { _ = story.`continue`() }
        try #require(story.currentChoices.count == 2)
        try story.chooseChoice(at: 0)

        // Simulate what SharedWorldYourStory does: one continue() then save, then restore, then continue()
        _ = story.`continue`()   // produces choice text, leaves engine positioned for gather divert
        let savedData = try story.saveState()

        let restored = try Story(json: json)
        try restored.restoreState(savedData)

        var lines: [String] = []
        while restored.canContinue {
            let line = restored.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
        }
        #expect(lines.contains { $0.contains("They lived happily ever after.") })
    }

    // GIVEN: a real-compiler story where a choice with a relative path (.^.^.c-N) is selected
    //        and the chosen continuation lives inside a NAMED parent container
    // WHEN: state is saved immediately after chooseChoice and restored on a fresh Story
    // THEN: the restored story can continue and produces the choice's continuation text
    // Regression for: rebuildStackFromFrames using childIndex into parent.children for the
    // top frame, even though chooseChoice entered the continuation via parent.namedContent.
    // This is what InkTest's blueprint+state-per-iteration loop exercises.

    @Test
    func `save-restore after chooseChoice with nested named continuation produces continuation text`() throws {
        // Cass shop fragment: cass_opening is named (root[0] itself is cass_opening),
        // and c-2 (Order a coffee) lives at root[0].namedContent["c-2"] — i.e. nested.
        // Choice target ".^.^.c-2" must resolve via parent.namedContent, not parent.children[16].
        let json = #"""
        {"inkVersion":21,"root":[["^Intro line.","\n",["ev","str","^Ask question.","/str","/ev",{"*":".^.c-0","flg":20},["ev",{"^->":"0.cass_opening.6.$r1"},{"temp=":"$r"},"str",{"->":".^.s"},[{"#n":"$r1"}],"/str","/ev",{"*":".^.^.c-1","flg":2},{"s":["^Order coffee.",{"->":"$r","var":true},null]}],{"c-0":["\n","^You asked.","\n",{"->":".^.^"},{"->":"0.g-0"},{"#f":5}],"c-1":["ev",{"^->":"0.cass_opening.c-1.$r2"},"/ev",{"temp=":"$r"},{"->":".^.^.6.s"},[{"#n":"$r2"}],"\n","^Here you go.","\n",{"->":".^.^"},{"->":"0.g-0"},null],"#n":"cass_opening"}],{"g-0":["end",["done",{"#n":"g-1"}],null]}],"done",null],"listDefs":{}}
        """#

        // Simulate InkTest: save after chooseChoice, restore in fresh story.
        let story = try Story(json: json)
        while story.canContinue { _ = story.`continue`() }
        try #require(story.currentChoices.count == 2)
        try story.chooseChoice(at: 1)  // Order coffee
        let savedData = try story.saveState()

        let restored = try Story(json: json)
        try restored.restoreState(savedData)

        var lines: [String] = []
        var safety = 0
        while restored.canContinue && safety < 50 {
            let line = restored.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
            safety += 1
        }
        #expect(lines.contains { $0.contains("Here you go.") })
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
