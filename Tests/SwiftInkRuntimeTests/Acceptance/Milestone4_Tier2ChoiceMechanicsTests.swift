// @real-io
// Acceptance tests for Tier 2 choice mechanics.
// Covers Slices 01–04 from docs/feature/tier2-choice-mechanics/.
//
// Each behaviour is verified in two modes:
//   • in-memory:       single Story instance played continuously to the assertion point
//   • save/restore:    state saved after each significant action and restored into a
//                      fresh Story instance (the InkTest / SharedWorldYourStory pattern)
//
// Driving port: Story facade — init(json:), continue(), chooseChoice(at:),
//               currentChoices, saveState(), restoreState(_:)
// Oracle: InkSwift.InkStory (JavaScript bridge) — macOS only
//
// All fixtures are compiled from real Ink source using inklecate.
// See Tests/SwiftInkRuntimeTests/slice0*.ink for the source files.

import Testing
import Foundation
@testable import SwiftInkRuntime
#if os(macOS)
import InkSwift
#endif

// MARK: - Slice 01 — Once-Only and Sticky Choices

@Suite("Slice 01 — Once-Only and Sticky Choices")
struct Slice01_OnceOnlyStickyTests {

    private func makeStory() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "slice01-once-only", withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func loadJSON() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "slice01-once-only", withExtension: "ink.json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // AC1: once-only is removed after pick (in-memory)
    @Test func `once-only choice absent from currentChoices after being picked`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        try #require(story.currentChoices.contains { $0.text == "Ask about the shop." })

        let idx = try #require(story.currentChoices.firstIndex { $0.text == "Ask about the shop." })
        try story.chooseChoice(at: idx)
        while story.canContinue { _ = story.`continue`() }

        #expect(!story.currentChoices.contains { $0.text == "Ask about the shop." })
    }

    // AC1 + AC5: once-only stays gone after save/restore
    @Test func `once-only choice absent after pick — save restore variant`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        while s.canContinue { _ = s.`continue`() }
        let idx = try #require(s.currentChoices.firstIndex { $0.text == "Ask about the shop." })
        try s.chooseChoice(at: idx)
        let saved = try s.saveState()

        let r = try Story(json: json)
        try r.restoreState(saved)
        while r.canContinue { _ = r.`continue`() }

        #expect(!r.currentChoices.contains { $0.text == "Ask about the shop." })
    }

    // AC2: sticky persists after pick (in-memory)
    @Test func `sticky choice remains in currentChoices after being picked`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        let idx = try #require(story.currentChoices.firstIndex { $0.text == "Order a coffee." })
        try story.chooseChoice(at: idx)
        while story.canContinue { _ = story.`continue`() }

        #expect(story.currentChoices.contains { $0.text == "Order a coffee." })
    }

    // AC2 + AC6: sticky stays available after save/restore
    @Test func `sticky choice remains after pick — save restore variant`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        while s.canContinue { _ = s.`continue`() }
        let idx = try #require(s.currentChoices.firstIndex { $0.text == "Order a coffee." })
        try s.chooseChoice(at: idx)
        let saved = try s.saveState()

        let r = try Story(json: json)
        try r.restoreState(saved)
        while r.canContinue { _ = r.`continue`() }

        #expect(r.currentChoices.contains { $0.text == "Order a coffee." })
    }

    // AC3: picking one once-only removes only that choice, not the others
    @Test func `picking one once-only choice removes only that choice`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        let idx = try #require(story.currentChoices.firstIndex { $0.text == "Ask about the shop." })
        try story.chooseChoice(at: idx)
        while story.canContinue { _ = story.`continue`() }

        let texts = story.currentChoices.map { $0.text }
        #expect(!texts.contains("Ask about the shop."))
        #expect(texts.contains("Ask what he needs."))
        #expect(texts.contains("Order a coffee."))
    }

    // AC4: mixed list converges to only the sticky choice (in-memory)
    @Test func `all once-only choices picked leaves only the sticky choice`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }

        for title in ["Ask about the shop.", "Ask what he needs."] {
            guard let idx = story.currentChoices.firstIndex(where: { $0.text == title }) else { continue }
            try story.chooseChoice(at: idx)
            while story.canContinue { _ = story.`continue`() }
        }

        #expect(story.currentChoices.map { $0.text } == ["Order a coffee."])
    }

    // AC4: mixed list convergence via successive save/restore
    @Test func `mixed list convergence — save restore variant`() throws {
        let json = try loadJSON()

        // First pick
        let s1 = try Story(json: json)
        while s1.canContinue { _ = s1.`continue`() }
        let i1 = try #require(s1.currentChoices.firstIndex { $0.text == "Ask about the shop." })
        try s1.chooseChoice(at: i1)
        let save1 = try s1.saveState()

        // Restore, second pick
        let s2 = try Story(json: json)
        try s2.restoreState(save1)
        while s2.canContinue { _ = s2.`continue`() }
        let i2 = try #require(s2.currentChoices.firstIndex { $0.text == "Ask what he needs." })
        try s2.chooseChoice(at: i2)
        let save2 = try s2.saveState()

        // Restore final state — only sticky should remain
        let s3 = try Story(json: json)
        try s3.restoreState(save2)
        while s3.canContinue { _ = s3.`continue`() }

        #expect(s3.currentChoices.map { $0.text } == ["Order a coffee."])
    }

    // Oracle: choice suppression matches JS bridge (macOS only)
    #if os(macOS)
    @Test func `once-only suppression matches JavaScript oracle after first pick`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice01-once-only", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        // Native: pick "Ask about the shop.", loop back, observe choices
        let native = try Story(json: json)
        while native.canContinue { _ = native.`continue`() }
        let nIdx = try #require(native.currentChoices.firstIndex { $0.text == "Ask about the shop." })
        try native.chooseChoice(at: nIdx)
        while native.canContinue { _ = native.`continue`() }
        let nativeTexts = Set(native.currentChoices.map { $0.text })

        // Oracle: drive to same state
        let oracle = InkStory()
        oracle.loadStory(json: json)
        while oracle.canContinue && oracle.options.isEmpty { _ = oracle.continueStory() }
        let oIdx = try #require(oracle.options.firstIndex { $0.text == "Ask about the shop." })
        oracle.chooseChoiceIndex(oIdx)
        while oracle.canContinue && oracle.options.isEmpty { _ = oracle.continueStory() }
        let oracleTexts = Set(oracle.options.map { $0.text })

        #expect(nativeTexts == oracleTexts)
    }
    #endif
}

// MARK: - Slice 02 — Conditional Choice Gating

@Suite("Slice 02 — Conditional Choice Gating")
struct Slice02_ConditionalChoiceTests {

    private func makeStory() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "slice02-conditional", withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func loadJSON() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "slice02-conditional", withExtension: "ink.json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // AC1: false condition excludes the choice
    @Test func `conditional choice absent from currentChoices when condition is false`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        // metCass starts false — conditional choice must not appear
        #expect(!story.currentChoices.contains { $0.text == "Thank you for the coffee." })
    }

    // AC1 + AC5: absent choice stays absent after save/restore with false condition
    @Test func `conditional choice absent after restore when condition is false`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        while s.canContinue { _ = s.`continue`() }
        let saved = try s.saveState()

        let r = try Story(json: json)
        try r.restoreState(saved)

        #expect(!r.currentChoices.contains { $0.text == "Thank you for the coffee." })
    }

    // AC2 + AC3: picking the trigger choice makes condition true, conditional choice appears
    @Test func `conditional choice appears in currentChoices after condition is set to true`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }

        // "Hello for the first time." sets metCass = true and loops back
        let idx = try #require(story.currentChoices.firstIndex { $0.text == "Hello for the first time." })
        try story.chooseChoice(at: idx)
        while story.canContinue { _ = story.`continue`() }

        #expect(story.currentChoices.contains { $0.text == "Thank you for the coffee." })
    }

    // AC3 + AC6: present choice stays present after save/restore with true condition
    @Test func `conditional choice present after restore when condition is true`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        while s.canContinue { _ = s.`continue`() }
        let idx = try #require(s.currentChoices.firstIndex { $0.text == "Hello for the first time." })
        try s.chooseChoice(at: idx)
        let saved = try s.saveState()

        let r = try Story(json: json)
        try r.restoreState(saved)
        while r.canContinue { _ = r.`continue`() }

        #expect(r.currentChoices.contains { $0.text == "Thank you for the coffee." })
    }

    // AC4: choices without a condition are unaffected by variable state
    @Test func `unconditional choices always appear regardless of variable state`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        #expect(story.currentChoices.contains { $0.text == "Leave." })

        // After setting metCass = true, "Leave." must still be present
        let idx = try #require(story.currentChoices.firstIndex { $0.text == "Hello for the first time." })
        try story.chooseChoice(at: idx)
        while story.canContinue { _ = story.`continue`() }
        #expect(story.currentChoices.contains { $0.text == "Leave." })
    }

    // Oracle: conditional gating matches JS bridge for false-condition case (macOS only)
    #if os(macOS)
    @Test func `conditional gating matches JavaScript oracle for false condition at story start`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice02-conditional", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        // Native: condition starts false
        let native = try Story(json: json)
        while native.canContinue { _ = native.`continue`() }
        let nativeHas = native.currentChoices.contains { $0.text == "Thank you for the coffee." }

        // Oracle: condition starts false
        let oracle = InkStory()
        oracle.loadStory(json: json)
        while oracle.canContinue && oracle.options.isEmpty { _ = oracle.continueStory() }
        let oracleHas = oracle.options.contains { $0.text == "Thank you for the coffee." }

        #expect(nativeHas == oracleHas)
    }
    #endif
}

// MARK: - Slice 03 — Visit Count Logic

@Suite("Slice 03 — Visit Count Logic")
struct Slice03_VisitCountTests {

    private func makeStory() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "slice03-read-counts", withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func loadJSON() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "slice03-read-counts", withExtension: "ink.json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // AC1 + AC2: first visit shows no recognition text; entry text always present
    @Test func `first visit to location shows no visit-count conditional text`() throws {
        let story = try makeStory()
        var lines: [String] = []
        while story.canContinue {
            let line = story.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
        }
        #expect(!lines.contains { $0.contains("You recognise the smell now.") })
        #expect(lines.contains { $0.contains("You enter the caf\u{00E9}.") })
    }

    // AC1 + AC3: second visit shows the count-conditional text
    @Test func `second visit to location shows visit-count conditional text`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }

        // Pick "Leave and come back." to trigger a second visit
        let idx = try #require(story.currentChoices.firstIndex { $0.text == "Leave and come back." })
        try story.chooseChoice(at: idx)

        var lines: [String] = []
        while story.canContinue {
            let line = story.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
        }
        #expect(lines.contains { $0.contains("You recognise the smell now.") })
    }

    // AC4: visit counts accumulate — third visit also shows count-conditional text
    @Test func `third visit to location still shows visit-count conditional text`() throws {
        let story = try makeStory()

        // Visit 1 → drain to choices
        while story.canContinue { _ = story.`continue`() }
        let i1 = try #require(story.currentChoices.firstIndex { $0.text == "Leave and come back." })
        try story.chooseChoice(at: i1)

        // Visit 2 → drain to choices
        while story.canContinue { _ = story.`continue`() }
        let i2 = try #require(story.currentChoices.firstIndex { $0.text == "Leave and come back." })
        try story.chooseChoice(at: i2)

        // Visit 3 — collect output
        var lines: [String] = []
        while story.canContinue {
            let line = story.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
        }
        #expect(lines.contains { $0.contains("You recognise the smell now.") })
    }

    // AC5: visit counts survive save/restore
    @Test func `visit-count conditional text correct after save and restore`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        while s.canContinue { _ = s.`continue`() }

        // First visit complete; choose to come back (second visit will be restored)
        let idx = try #require(s.currentChoices.firstIndex { $0.text == "Leave and come back." })
        try s.chooseChoice(at: idx)
        let saved = try s.saveState()

        // Restore and continue into the second visit
        let r = try Story(json: json)
        try r.restoreState(saved)

        var lines: [String] = []
        while r.canContinue {
            let line = r.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(line)
            }
        }
        #expect(lines.contains { $0.contains("You recognise the smell now.") })
    }

    // Oracle: visit-count conditional text on second visit matches JS bridge (macOS only)
    #if os(macOS)
    @Test func `visit-count conditional text on second visit matches JavaScript oracle`() throws {
        let url = try #require(Bundle.module.url(forResource: "slice03-read-counts", withExtension: "ink.json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        // Native: second visit
        let native = try Story(json: json)
        while native.canContinue { _ = native.`continue`() }
        let nIdx = try #require(native.currentChoices.firstIndex { $0.text == "Leave and come back." })
        try native.chooseChoice(at: nIdx)
        var nativeLines: [String] = []
        while native.canContinue {
            let line = native.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { nativeLines.append(line) }
        }
        let nativeHasRevisit = nativeLines.contains { $0.contains("You recognise the smell now.") }

        // Oracle: second visit
        let oracle = InkStory()
        oracle.loadStory(json: json)
        while oracle.canContinue && oracle.options.isEmpty { _ = oracle.continueStory() }
        let oIdx = try #require(oracle.options.firstIndex { $0.text == "Leave and come back." })
        oracle.chooseChoiceIndex(oIdx)
        var oracleLines: [String] = []
        let afterText = oracle.currentText
        if !afterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { oracleLines.append(afterText) }
        while oracle.canContinue && oracle.options.isEmpty {
            let line = oracle.continueStory()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { oracleLines.append(line) }
        }
        let oracleHasRevisit = oracleLines.contains { $0.contains("You recognise the smell now.") }

        #expect(nativeHasRevisit == oracleHasRevisit)
    }
    #endif
}

// MARK: - Slice 04 — Invisible Default Fallthrough

@Suite("Slice 04 — Invisible Default Fallthrough")
struct Slice04_InvisibleDefaultTests {

    private func makeStory() throws -> Story {
        let url = try #require(Bundle.module.url(forResource: "slice04-invisible-defaults", withExtension: "ink.json"))
        return try Story(json: String(contentsOf: url, encoding: .utf8))
    }

    private func loadJSON() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "slice04-invisible-defaults", withExtension: "ink.json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // AC1: invisible default never appears in currentChoices — even as empty text
    @Test func `invisible default choice never appears in currentChoices`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        let texts = story.currentChoices.map { $0.text }
        // Only the visible once-only choice should be present
        #expect(story.currentChoices.count == 1)
        #expect(texts.contains("Ask about the shop."))
        #expect(!texts.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    // AC2: story auto-continues through invisible default when all visible choices are exhausted
    @Test func `story auto-continues through invisible default after all visible choices are exhausted`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }

        // Pick the only visible once-only choice
        let idx = try #require(story.currentChoices.firstIndex { $0.text == "Ask about the shop." })
        try story.chooseChoice(at: idx)

        // The story should now auto-continue — no chooseChoice call needed
        var lines: [String] = []
        while story.canContinue {
            let line = story.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append(line) }
        }
        #expect(lines.contains { $0.contains("The conversation drifts naturally to a close.") })
    }

    // AC3: when visible choices exist, invisible default does not fire prematurely
    @Test func `visible choices take priority over invisible default`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        // Invisible default must not have fired; we must still be at the choice point
        #expect(!story.currentChoices.isEmpty)
        #expect(story.currentChoices.count == 1)
        #expect(story.currentChoices[0].text == "Ask about the shop.")
    }

    // AC4: no empty-choice hang after all visible choices exhausted
    @Test func `no empty-text choice appears in currentChoices after all visible choices exhausted`() throws {
        let story = try makeStory()
        while story.canContinue { _ = story.`continue`() }
        let idx = try #require(story.currentChoices.firstIndex { $0.text == "Ask about the shop." })
        try story.chooseChoice(at: idx)
        while story.canContinue { _ = story.`continue`() }

        // Must not have an empty-text choice trapping the story
        let hasEmptyChoice = story.currentChoices.contains {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        #expect(!hasEmptyChoice)
    }

    // AC5: auto-continuation through invisible default produces same text after save/restore
    @Test func `invisible default fallthrough text correct after save and restore`() throws {
        let json = try loadJSON()
        let s = try Story(json: json)
        while s.canContinue { _ = s.`continue`() }
        let idx = try #require(s.currentChoices.firstIndex { $0.text == "Ask about the shop." })
        try s.chooseChoice(at: idx)
        let saved = try s.saveState()

        let r = try Story(json: json)
        try r.restoreState(saved)

        var lines: [String] = []
        while r.canContinue {
            let line = r.`continue`()
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append(line) }
        }
        #expect(lines.contains { $0.contains("The conversation drifts naturally to a close.") })
    }
}
