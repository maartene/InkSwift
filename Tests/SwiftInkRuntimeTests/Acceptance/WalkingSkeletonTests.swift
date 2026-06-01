// @walking_skeleton @real-io @driving_adapter
// Strategy C: All adapters use real implementations — no fakes or in-memory doubles.
// Driving port: Story.init(json:) and Story.continue()

import Testing
import Foundation
@testable import SwiftInkRuntime
#if os(macOS)
import InkSwift
#endif

@Suite struct WalkingSkeletonTests {

    // GIVEN: a valid Ink JSON story loaded from the test bundle
    // WHEN: Story(json:) is called with the JSON string
    // THEN: canContinue is true
    // AND: calling continue() returns non-empty text

    @Test func `story loads from a real bundle fixture and canContinue is true`() throws {
        let url = try #require(Bundle.module.url(forResource: "test.ink", withExtension: "json"))
        let json = try String(contentsOf: url, encoding: .utf8)

        let story = try Story(json: json)

        #expect(story.canContinue)
        let text = story.`continue`()
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // GIVEN: a string that is not valid JSON
    // WHEN: Story(json:) is called
    // THEN: a StoryError is thrown

    @Test func `Story init throws for malformed JSON`() {
        #expect(throws: (any Error).self) {
            try Story(json: "not valid json at all")
        }
    }
}
