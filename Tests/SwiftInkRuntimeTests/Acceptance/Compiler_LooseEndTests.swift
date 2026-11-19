// @acceptance @real-io
//
// #28 / ADR-021 (step 02-05) — native loose ends match inklecate: `done` only
// for the root weave.
//
// inklecate adds `done` only after the top-level flow (compiler `Story.cs:193`,
// plus the final gather it gives the root weave). A knot or stitch whose flow
// runs out gets nothing, so the runtime stops without a safe exit and, with
// ADR-020's epilogue (step 02-04), reports "ran out of content". The native
// compiler used to end every weave with `done`, so a knot whose choices were all
// used up stopped safely natively and ran out on inklecate's JSON.
//
// Each scenario plays the story natively and from inklecate's committed JSON on
// the InkSwift runtime and compares the lines and how the flow stopped.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct Compiler_LooseEndTests {

    private enum Stop: Equatable {
        case choices([String])
        case end(didSafeExit: Bool)
    }

    private static let fixture = "loose-end-weave-in-knot"
    private static let maximumStops = 12
    private static let maximumContinues = 500

    /// Play `story` along `script` (then always the first choice), recording each
    /// stop until the flow ends without choices.
    private static func stops(of story: Story, script: [Int]) throws -> [Stop] {
        var stops: [Stop] = []
        var continues = 0
        while stops.count < maximumStops {
            while story.canContinue, continues < maximumContinues {
                _ = story.continue()
                continues += 1
            }
            let choices = story.currentChoices.map(\.text)
            guard choices.isEmpty == false else {
                stops.append(.end(didSafeExit: story.engine.didSafeExit))
                break
            }
            try story.chooseChoice(at: stops.count < script.count ? script[stops.count] : 0)
            stops.append(.choices(choices))
        }
        return stops
    }

    private static func nativeStory(_ name: String) throws -> Story {
        Story(blueprint: try InkCompiler.compile(source: try CompilerOracle.source(name)))
    }

    private static func referenceStory(_ name: String) throws -> Story {
        try Story(json: try CompilerOracle.oracleJSON(name))
    }

    // MARK: Criterion 1 — the "sipping" rejoin plays once

    /// TheIntercept's `{ teacup: … <>, sipping at my tea … }` block sits in a
    /// gather whose continuation leads into the next weave of the knot. Its line
    /// must play exactly once, as on inklecate's JSON: a rejoin that fell back
    /// into content already played would repeat it.
    @Test func `TheIntercept's sipping at my tea line plays exactly once, as on inklecate's JSON`() throws {
        let script = [0, 2, 1, 0, 0, 1, 2, 0, 1, 0]
        let (native, oracle) = try CompilerOracle.compileAndPlay("TheIntercept", choiceScript: script)

        let sipping: ([String]) -> Int = { lines in lines.filter { $0.contains("sipping at my tea") }.count }
        #expect(sipping(oracle) == 1)
        #expect(sipping(native) == sipping(oracle))
        #expect(native == oracle)
    }
}
