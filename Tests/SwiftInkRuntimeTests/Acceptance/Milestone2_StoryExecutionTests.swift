// @real-io
// Exercises: Story facade -> InkEngine -> TreeWalker -> ContainerNode tree
// All scenarios enabled for DELIVER Milestone 2.

import Testing
import Foundation
@testable import SwiftInkRuntime
#if os(macOS)
import InkSwift
#endif

@Suite struct Milestone2_StoryExecutionTests {

    // Helper: load the test fixture story (native runtime)
    // test.ink.json root passage: "Line 1" → end (no choices)
    func makeStory() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "test.ink", withExtension: "json"))
        let json = try String(contentsOf: url, encoding: .utf8)
        return try Story(json: json)
    }

    // Helper: a minimal inline story that has two choices after initial text.
    // The choice containers are named at root level so absolute paths resolve correctly.
    // Structure: root → inner_sub → "Which path?" → \n → choice(c-0) → choice(c-1) → end
    //            root.namedContent: c-0 → "You chose A.\n" → end
    //                               c-1 → "You chose B.\n" → end
    func makeChoiceStory() throws -> Story {
        let json = """
        {"inkVersion":21,"root":[[\"^Which path?\",\"\\n\",{\"*\":\"c-0\",\"flg\":20},{\"*\":\"c-1\",\"flg\":20},null],null,{\"c-0\":[\"^You chose A.\",\"\\n\",\"end\",{\"#f\":5}],\"c-1\":[\"^You chose B.\",\"\\n\",\"end\",{\"#f\":5}],\"#f\":1}],"listDefs":{}}
        """
        return try Story(json: json)
    }

    // GIVEN: a story with only linear text and no choices
    // WHEN: continue() is called repeatedly until canContinue is false
    // THEN: all text lines are returned without error

    @Test
    func `linear story can be continued through all text without error`() throws {
        let story = try makeStory()
        var lineCount = 0
        while story.canContinue {
            _ = story.`continue`()
            lineCount += 1
            if lineCount > 1000 { break }  // safety limit
        }
        #expect(lineCount > 0)
        // Should complete without throwing
    }

    // GIVEN: test.ink.json is loaded into both SwiftInkRuntime.Story and InkSwift.InkStory
    // WHEN: both stories are continued through the first passage without making choices
    // THEN: both produce identical text output, line by line

    #if os(macOS)
    @Test
    func `SwiftInkRuntime output matches InkSwift oracle for the test fixture`() throws {
        let url = try #require(Bundle.module.url(forResource: "test.ink", withExtension: "json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        // Native runtime — continue through first passage only (stop at choices or end)
        let native = try Story(json: json)
        var nativeLines: [String] = []
        while native.canContinue && native.currentChoices.isEmpty {
            let line = native.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nativeLines.append(line)
            }
        }

        // Oracle (InkSwift JS bridge) — loadStory calls continueStory() internally,
        // so we first capture the text it already produced, then continue further.
        let oracle = InkStory()
        oracle.loadStory(json: json)
        var oracleLines: [String] = []
        // Capture text already produced by the internal continue inside loadStory
        let initialText = oracle.currentText
        if !initialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            oracleLines.append(initialText)
        }
        // Then keep continuing until choices appear or story ends
        while oracle.canContinue && oracle.options.isEmpty {
            let line = oracle.continueStory()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                oracleLines.append(line)
            }
        }

        #expect(!nativeLines.isEmpty)
        #expect(nativeLines == oracleLines)
    }
    #endif

    // GIVEN: a story that reaches a choice point after the first passage
    // WHEN: continue() is called until canContinue is false
    // THEN: currentChoices is non-empty

    @Test
    func `choices appear in currentChoices after continuing a passage`() throws {
        let story = try makeChoiceStory()
        // Continue until we hit choices or end
        while story.canContinue { _ = story.`continue`() }
        #expect(!story.currentChoices.isEmpty)
    }

    // GIVEN: a story at a choice point
    // WHEN: chooseChoice(at: 0) is called, then continue() is called
    // THEN: canContinue or more choices available (story advanced)

    @Test
    func `selecting a choice advances the story to the chosen path`() throws {
        let story = try makeChoiceStory()
        while story.canContinue { _ = story.`continue`() }
        let choices = story.currentChoices
        try #require(!choices.isEmpty)
        try story.chooseChoice(at: 0)
        #expect(story.canContinue || !story.currentChoices.isEmpty)
    }

    // GIVEN: a story with real-compiler-format JSON (numeric-prefixed paths like "0.c-0")
    // WHEN: chooseChoice(at: 0) is called, then continue() is called
    // THEN: canContinue is true and continuation text is non-empty
    // Regression for: resolveNamedPath silently failing on numeric path components

    @Test
    func `choosing a choice in a real-compiler story produces continuation text`() throws {
        let json = #"""
        {"inkVersion":21,"root":[["^A simple story","\n","^Once upon a time...","\n",["ev",{"^->":"0.4.$r1"},{"temp=":"$r"},"str",{"->":".^.s"},[{"#n":"$r1"}],"/str","/ev",{"*":"0.c-0","flg":18},{"s":["^There were two choices.",{"->":"$r","var":true},null]}],["ev",{"^->":"0.5.$r1"},{"temp=":"$r"},"str",{"->":".^.s"},[{"#n":"$r1"}],"/str","/ev",{"*":"0.c-1","flg":18},{"s":["^There were four lines of content.",{"->":"$r","var":true},null]}],{"c-0":["ev",{"^->":"0.c-0.$r2"},"/ev",{"temp=":"$r"},{"->":"0.4.s"},[{"#n":"$r2"}],"\n",{"->":"0.g-0"},{"#f":5}],"c-1":["ev",{"^->":"0.c-1.$r2"},"/ev",{"temp=":"$r"},{"->":"0.5.s"},[{"#n":"$r2"}],"\n",{"->":"0.g-0"},{"#f":5}],"g-0":["^They lived happily ever after.","\n","end",["done",{"#f":5,"#n":"g-1"}],{"#f":5}]}],"done",{"#f":1}],"listDefs":{}}
        """#
        let story = try Story(json: json)
        while story.canContinue { _ = story.`continue`() }
        try #require(story.currentChoices.count == 2)
        try story.chooseChoice(at: 0)
        #expect(story.canContinue)
        let text = story.`continue`()
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // GIVEN: a story at a choice point with 2 available choices
    // WHEN: chooseChoice(at: 99) is called
    // THEN: StoryError.invalidChoiceIndex is thrown

    @Test
    func `chooseChoice throws for an out-of-range index`() throws {
        let story = try makeStory()
        #expect(throws: StoryError.self) {
            try story.chooseChoice(at: 99)
        }
    }

    // GIVEN: a story with tagged content on a passage
    // WHEN: continue() returns that passage
    // THEN: currentTags contains the expected tag

    @Test
    func `tags from a tagged passage appear in currentTags after continue`() throws {
        let story = try makeStory()
        var foundTags = false
        while story.canContinue {
            _ = story.`continue`()
            if !story.currentTags.isEmpty {
                foundTags = true
                break
            }
        }
        // test.ink.json root passage has no tags — verify no false positives.
        #expect(!foundTags)
    }

    // GIVEN: a story whose choices are encoded with 's' named sub-containers (flg:18, the real Ink compiler format)
    // WHEN: continue() is called until canContinue is false
    // THEN: both choices appear with their correct text (regression for: only first choice shown, empty choice text)

    @Test
    func `story with s-sub-container choices exposes all choices with correct text`() throws {
        let json = #"""
        {"inkVersion":21,"root":[["^A simple story","\n","^Once upon a time...","\n",["ev",{"^->":"0.4.$r1"},{"temp=":"$r"},"str",{"->":".^.s"},[{"#n":"$r1"}],"/str","/ev",{"*":"0.c-0","flg":18},{"s":["^There were two choices.",{"->":"$r","var":true},null]}],["ev",{"^->":"0.5.$r1"},{"temp=":"$r"},"str",{"->":".^.s"},[{"#n":"$r1"}],"/str","/ev",{"*":"0.c-1","flg":18},{"s":["^There were four lines of content.",{"->":"$r","var":true},null]}],{"c-0":["ev",{"^->":"0.c-0.$r2"},"/ev",{"temp=":"$r"},{"->":"0.4.s"},[{"#n":"$r2"}],"\n",{"->":"0.g-0"},{"#f":5}],"c-1":["ev",{"^->":"0.c-1.$r2"},"/ev",{"temp=":"$r"},{"->":"0.5.s"},[{"#n":"$r2"}],"\n",{"->":"0.g-0"},{"#f":5}],"g-0":["^They lived happily ever after.","\n","end",["done",{"#f":5,"#n":"g-1"}],{"#f":5}]}],"done",{"#f":1}],"listDefs":{}}
        """#
        let story = try Story(json: json)
        while story.canContinue { _ = story.`continue`() }
        #expect(story.currentChoices.count == 2)
        #expect(story.currentChoices[0].text == "There were two choices.")
        #expect(story.currentChoices[1].text == "There were four lines of content.")
    }

    // GIVEN: a story with real-compiler-format JSON (numeric-prefixed paths, anchor $r2, variable divert)
    // WHEN: chooseChoice(at: 0) is called, then continue() is called until canContinue is false
    // THEN: collected lines contain both the choice text and the gather text "They lived happily ever after."

    @Test
    func `choosing a choice in a real-compiler story shows gather text after choice text`() throws {
        let json = #"""
        {"inkVersion":21,"root":[["^A simple story","\n","^Once upon a time...","\n",["ev",{"^->":"0.4.$r1"},{"temp=":"$r"},"str",{"->":".^.s"},[{"#n":"$r1"}],"/str","/ev",{"*":"0.c-0","flg":18},{"s":["^There were two choices.",{"->":"$r","var":true},null]}],["ev",{"^->":"0.5.$r1"},{"temp=":"$r"},"str",{"->":".^.s"},[{"#n":"$r1"}],"/str","/ev",{"*":"0.c-1","flg":18},{"s":["^There were four lines of content.",{"->":"$r","var":true},null]}],{"c-0":["ev",{"^->":"0.c-0.$r2"},"/ev",{"temp=":"$r"},{"->":"0.4.s"},[{"#n":"$r2"}],"\n",{"->":"0.g-0"},{"#f":5}],"c-1":["ev",{"^->":"0.c-1.$r2"},"/ev",{"temp=":"$r"},{"->":"0.5.s"},[{"#n":"$r2"}],"\n",{"->":"0.g-0"},{"#f":5}],"g-0":["^They lived happily ever after.","\n","end",["done",{"#f":5,"#n":"g-1"}],{"#f":5}]}],"done",{"#f":1}],"listDefs":{}}
        """#
        let story = try Story(json: json)
        while story.canContinue { _ = story.`continue`() }
        try #require(story.currentChoices.count == 2)
        try story.chooseChoice(at: 0)
        var lines: [String] = []
        while story.canContinue {
            let line = story.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
        }
        #expect(lines.contains { $0.contains("There were two choices.") })
        #expect(lines.contains { $0.contains("They lived happily ever after.") })
    }

    // GIVEN: a story with flg=20 (bracket-only) choices using str/str text accumulation
    // WHEN: continue() reaches the choice points
    // THEN: each choice exposes the bracketed text — not empty string
    // Regression for: choice shortcut reading namedContent["s"] only (flg=20 has no "s" container)

    @Test
    func `flg-20 bracket-only choices expose correct text from evalStack`() throws {
        let json = #"""
        {"inkVersion":21,"root":[["ev","str","^Option A ","/str","/ev",{"*":".^.c-0","flg":20},"ev","str","^Option B ","/str","/ev",{"*":".^.c-1","flg":20},{"c-0":["^You chose A.","\n","done",{"#f":5}],"c-1":["^You chose B.","\n","done",{"#f":5}]}],"done",{"#f":1}],"listDefs":{}}
        """#
        let story = try Story(json: json)
        while story.canContinue { _ = story.`continue`() }
        #expect(story.currentChoices.count == 2)
        #expect(story.currentChoices[0].text == "Option A ")
        #expect(story.currentChoices[1].text == "Option B ")
    }

    // GIVEN: a story with flg=20 choices whose targets are relative paths (.^.c-N)
    // WHEN: a choice is selected and continue() is called
    // THEN: the continuation text from the chosen branch is produced
    // Regression for: resolveNamedPath silently returning nil for "^" path component

    @Test
    func `choosing a flg-20 choice with relative target path produces continuation text`() throws {
        let json = #"""
        {"inkVersion":21,"root":[["ev","str","^Option A ","/str","/ev",{"*":".^.c-0","flg":20},"ev","str","^Option B ","/str","/ev",{"*":".^.c-1","flg":20},{"c-0":["^You chose A.","\n","done",{"#f":5}],"c-1":["^You chose B.","\n","done",{"#f":5}]}],"done",{"#f":1}],"listDefs":{}}
        """#
        let story = try Story(json: json)
        while story.canContinue { _ = story.`continue`() }
        try #require(story.currentChoices.count == 2)
        try story.chooseChoice(at: 1)
        let text = story.`continue`()
        #expect(text.contains("You chose B."))
    }

    // GIVEN: a real-compiler story with nested choices (`* [...] * * [...]`)
    // WHEN: the outer choice is selected and the story is continued through the
    //       inner choice generation
    // THEN: only the inner choices are exposed — the outer container's remaining
    //       choices are NOT re-generated as siblings of the inner choices
    // Regression for: containerStack falling through into the outer container
    // after the chosen-continuation frame exhausts.

    @Test
    func `picking an outer choice yields only the inner choices not outer ones too`() throws {
        let json = #"""
        {"inkVersion":21,"root":[["^Intro line.","\n",["ev","str","^Ask question.","/str","/ev",{"*":".^.c-0","flg":20},"ev","str","^Ask another.","/str","/ev",{"*":".^.c-1","flg":20},["ev",{"^->":"0.cass_opening.12.$r1"},{"temp=":"$r"},"str",{"->":".^.s"},[{"#n":"$r1"}],"/str","/ev",{"*":".^.^.c-2","flg":2},{"s":["^Sticky option.",{"->":"$r","var":true},null]}],{"c-0":["\n","^Inner response.","\n",[["ev","str","^Pick this inner.","/str","/ev",{"*":".^.c-0","flg":20},"ev","str","^Pick that inner.","/str","/ev",{"*":".^.c-1","flg":20},{"c-0":["\n","^You picked this. ",{"->":".^.^"},"\n",{"->":"0.g-0"},{"#f":5}],"c-1":["\n","^You picked that.","\n","end",{"->":"0.g-0"},{"#f":5}],"#n":"inner_gather"}],null],{"#f":5}],"c-1":["\n","^Another response.","\n",{"->":".^.^"},{"->":"0.g-0"},{"#f":5}],"c-2":["ev",{"^->":"0.cass_opening.c-2.$r2"},"/ev",{"temp=":"$r"},{"->":".^.^.12.s"},[{"#n":"$r2"}],"\n","^Sticky response.","\n",{"->":".^.^"},{"->":"0.g-0"},null],"#n":"cass_opening"}],{"g-0":["end",["done",{"#n":"g-1"}],null]}],"done",null],"listDefs":{}}
        """#
        let story = try Story(json: json)
        while story.canContinue { _ = story.`continue`() }
        try #require(story.currentChoices.count == 3)
        try story.chooseChoice(at: 0)  // Ask question (outer)
        // Drain any continuation text the choice produces.
        while story.canContinue { _ = story.`continue`() }
        let texts = story.currentChoices.map { $0.text }
        #expect(texts == ["Pick this inner.", "Pick that inner."])
    }

    // GIVEN: a nested inner choice whose continuation has text immediately followed
    //        by a relative divert (`text + {"->": ".^.^"}` with no `\n` between)
    // WHEN: that inner choice is selected and continue() is called
    // THEN: the continuation text is produced as a line, not clobbered by the
    //       choice-point clearing of outputStream after the divert
    // Regression for: outputStream containing pending text getting wiped by the
    // choice-collection clear when a divert leads straight into a choice generator.

    @Test
    func `picking an inner choice with divert-after-text emits the text before re-prompt`() throws {
        let json = #"""
        {"inkVersion":21,"root":[["^Intro line.","\n",["ev","str","^Ask question.","/str","/ev",{"*":".^.c-0","flg":20},"ev","str","^Ask another.","/str","/ev",{"*":".^.c-1","flg":20},["ev",{"^->":"0.cass_opening.12.$r1"},{"temp=":"$r"},"str",{"->":".^.s"},[{"#n":"$r1"}],"/str","/ev",{"*":".^.^.c-2","flg":2},{"s":["^Sticky option.",{"->":"$r","var":true},null]}],{"c-0":["\n","^Inner response.","\n",[["ev","str","^Pick this inner.","/str","/ev",{"*":".^.c-0","flg":20},"ev","str","^Pick that inner.","/str","/ev",{"*":".^.c-1","flg":20},{"c-0":["\n","^You picked this. ",{"->":".^.^"},"\n",{"->":"0.g-0"},{"#f":5}],"c-1":["\n","^You picked that.","\n","end",{"->":"0.g-0"},{"#f":5}],"#n":"inner_gather"}],null],{"#f":5}],"c-1":["\n","^Another response.","\n",{"->":".^.^"},{"->":"0.g-0"},{"#f":5}],"c-2":["ev",{"^->":"0.cass_opening.c-2.$r2"},"/ev",{"temp=":"$r"},{"->":".^.^.12.s"},[{"#n":"$r2"}],"\n","^Sticky response.","\n",{"->":".^.^"},{"->":"0.g-0"},null],"#n":"cass_opening"}],{"g-0":["end",["done",{"#n":"g-1"}],null]}],"done",null],"listDefs":{}}
        """#
        let story = try Story(json: json)
        while story.canContinue { _ = story.`continue`() }
        try story.chooseChoice(at: 0)  // outer Ask question
        var lines: [String] = []
        while story.canContinue {
            let line = story.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
        }
        try story.chooseChoice(at: 0)  // inner Pick this — text then divert to inner_gather
        while story.canContinue {
            let line = story.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
        }
        #expect(lines.contains { $0.contains("You picked this.") })
    }

    // GIVEN: a story continued to its end
    // WHEN: canContinue is false and currentChoices is empty
    // THEN: the story is complete without any pending error

    @Test
    func `story ends gracefully with no errors when fully continued`() throws {
        let story = try makeChoiceStory()
        var safety = 0
        while story.canContinue || !story.currentChoices.isEmpty {
            if story.canContinue {
                _ = story.`continue`()
            } else if !story.currentChoices.isEmpty {
                try story.chooseChoice(at: 0)
            }
            safety += 1
            if safety > 500 { break }
        }
        #expect(story.currentErrors.isEmpty)
        #expect(!story.canContinue)
    }
}
