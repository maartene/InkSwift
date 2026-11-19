// @acceptance @real-io
//
// Issue #32 — a story that uses an ink feature the runtime does not support is
// refused when it is loaded, for the whole story, instead of playing on with the
// feature printed as text ("FLOOR1.5", "rnd") or skipped. Decided on #32: fail at
// load, because a feature in a rarely visited knot is exactly the one that
// surprises a player late and is hardest to trace.
//
// Every fixture is compiled by inklecate 1.2.1 and puts its feature inside a knot
// `k`, followed by more content, so the reported location and the "nothing
// played" guarantee are both pinned. A list value lives in the `VAR`
// declaration, which is the top level (`""`).

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Engine — unsupported features are refused at load")
struct Engine_UnsupportedFeatureLoadTests {

    struct Refusal: CustomTestStringConvertible, Sendable {
        let fixture: String
        let feature: String
        let locations: [String]
        var testDescription: String { fixture }
    }

    static let refusals = [
        Refusal(fixture: "list", feature: "LIST", locations: [""]),
        Refusal(fixture: "thread", feature: "threads (<-)", locations: ["k"]),
        Refusal(fixture: "random", feature: "RANDOM()", locations: ["k"]),
        Refusal(fixture: "shuffle", feature: "shuffle {~a|b}", locations: ["k"]),
        Refusal(fixture: "external", feature: "EXTERNAL functions", locations: ["k"]),
        Refusal(fixture: "pow", feature: "POW()", locations: ["k"]),
        Refusal(fixture: "turns", feature: "TURNS()", locations: ["k"]),
        Refusal(fixture: "turns-since", feature: "TURNS_SINCE()", locations: ["k"]),
        Refusal(fixture: "choice-count", feature: "CHOICE_COUNT()", locations: ["k"]),
        Refusal(fixture: "read-count-variable", feature: "READ_COUNT() of a divert-target variable", locations: ["k"]),
        Refusal(fixture: "contains", feature: "? (contains)", locations: ["k"]),
        Refusal(fixture: "does-not-contain", feature: "!? (does not contain)", locations: ["k"]),
    ]

    private func load(_ fixture: String) throws -> Story {
        try Story(json: try CompilerOracle.oracleJSON(fixture))
    }

    @Test(arguments: refusals)
    func `a story using an unsupported feature is refused at load, naming it and where it is`(refusal: Refusal) throws {
        #expect(throws: StoryError.unsupportedFeatures([
            UnsupportedFeature(name: refusal.feature, locations: refusal.locations)
        ])) {
            try load("runtime-unsupported-\(refusal.fixture)")
        }
    }

    // One load reports every feature, grouped by name and sorted, with every
    // place each is used — including a knot no playthrough reaches.
    @Test func `every unsupported feature in the story is reported at once, even in a knot never visited`() throws {
        #expect(throws: StoryError.unsupportedFeatures([
            UnsupportedFeature(name: "LIST", locations: [""]),
            UnsupportedFeature(name: "POW()", locations: [""]),
            UnsupportedFeature(name: "RANDOM()", locations: ["never_visited", "shop.haggle"]),
            UnsupportedFeature(name: "threads (<-)", locations: ["never_visited"]),
        ])) {
            try load("runtime-unsupported-several")
        }
    }

    // FLOOR, INT, CEILING and FLOAT were implemented under names inklecate never
    // emits, so they printed as text. SEED_RANDOM is accepted: with every RNG
    // feature refused, a seed changes nothing a player can observe. FLOAT is
    // checked through a division (`FLOAT(1) / 2` is 0.5, integer division 0),
    // since a whole float prints as `2.0` here and `2` in inklecate, a separate
    // formatting gap.
    @Test func `FLOOR, INT, CEILING, FLOAT and SEED_RANDOM play as inklecate plays them`() throws {
        let story = try load("runtime-floor-int-ceiling-float")

        #expect(try CompilerOracle.play(story) == ["Floor: 1 Int: 1 Ceil: 2 Float: 0.5.", "After the numbers."])
    }

    // A token outside ink's JSON format is malformed JSON, not an unsupported
    // feature, as in the reference ("Failed to convert token to runtime object").
    // Hand-written: inklecate never emits such a token.
    @Test(arguments: [
        #"{"inkVersion":21,"root":[["^Before.","\n","notAnInkToken","^After.","\n","end",null],"done",null],"listDefs":{}}"#,
        #"{"inkVersion":21,"root":[["^Before.","\n",{"notAnInkKey":1},"^After.","\n","end",null],"done",null],"listDefs":{}}"#,
    ])
    func `a token that is not ink JSON is invalid JSON`(json: String) {
        #expect(throws: StoryError.invalidJSON) {
            try Story(json: json)
        }
    }

    // inkVersion 20 wrote a tag as one object, `{"#": "text"}`; version 21 uses
    // `"#"` … `"/#"`. The runtime only reads the new form, so an old tag would be
    // dropped. Hand-written: the current inklecate cannot produce version 20.
    @Test func `a tag in the inkVersion 20 format is refused, asking for a recompile`() {
        let json = ##"{"inkVersion":20,"root":[["^Tagged.",{"#":"old"},"\n","end",null],"done",null],"listDefs":{}}"##

        #expect(throws: StoryError.unsupportedFeatures([
            UnsupportedFeature(name: "tags in the inkVersion 20 format (recompile with a current inklecate)", locations: [""])
        ])) {
            try Story(json: json)
        }
    }
}
