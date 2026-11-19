// @acceptance @real-io
//
// #28 / U13 — native-compiled stories end safely where inklecate's do.
//
// The runtime will report C#'s "ran out of content" error for a flow that stops
// without a safe exit (ADR-020 §5, step 02-04). That error must fire only on
// stories that are broken in inklecate too, so the native emission has to reach
// `done` / `end` wherever inklecate's JSON does. Three emission gaps made native
// flows run out where inklecate's end safely:
//   (a) `-> DONE` outside the root compiled to a divert to a path "DONE" that
//       does not exist, instead of the `done` control command;
//   (b) a conditional's rejoin and (c) a weave's final gather were separate
//       named containers that nothing followed, where inklecate's layout carries
//       on into the enclosing weave's `done`.
//
// Each story is played twice on the InkSwift runtime — compiled natively and
// from inklecate's committed JSON — always taking the first choice, and the two
// must agree on whether every stop was a safe exit. The stories are the
// upstream conformance fixtures 02-04's epilogue found running out natively.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct Compiler_SafeExitEmissionTests {

    /// One stop of a playthrough: the choices it offered, or — when it offered
    /// none, so the flow ended — whether it ended with a safe exit. (A stop at a
    /// choice point is not an end: C# reports "ran out of content" only when no
    /// choice was generated.)
    private enum Stop: Equatable {
        case choices([String])
        case end(didSafeExit: Bool)
    }

    private static let maximumStops = 12
    private static let maximumContinues = 500

    private static func fixture(_ name: String, _ ext: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Play `story` taking choice `firstChoice` at the first choice point and the
    /// first choice after that, recording each stop, until the flow ends without
    /// choices.
    private static func stops(of story: Story, firstChoice: Int = 0) throws -> [Stop] {
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
            try story.chooseChoice(at: stops.isEmpty ? firstChoice : 0)
            stops.append(.choices(choices))
        }
        return stops
    }

    @Test(arguments: [
        "TestImplicitInlineGlueB",
        "TestImplicitInlineGlueC",
        "TestKnotDotGather",
        "TestLeftRightGlueMatching",
        "TestMultipleConstantReferences",
        "TestNewlineAtStartOfMultilineConditional",
        "TestReadCountAcrossCallstack",
        "TestSameLineDivertIsInline",
        "TestTempGlobalConflict",
        "TestTrivialCondition",
        "TestVariableDeclarationInConditional",
        "TestVariableGetSetAPI",
        "TestVisitCountBugDueToNestedContainers",
        "TestWeaveGathers",
        "TestAllSwitchBranchesFailIsClean",
        "TestChoiceWithBracketsOnly",
        "TestConditionalChoiceInWeave2",
        "TestEmptyMultilineConditionalBranch",
    ])
    func `a natively compiled story stops safely wherever inklecate's JSON does`(test: String) throws {
        let name = "upstream-\(test)-0"
        let native = Story(blueprint: try InkCompiler.compile(source: try Self.fixture(name, "ink")))
        let reference = try Story(json: try Self.fixture(name, "ink.json"))

        let nativeStops = try Self.stops(of: native)
        let referenceStops = try Self.stops(of: reference)

        #expect(nativeStops == referenceStops)
    }

    /// `-> DONE` in a stitch, a choice body, a conditional arm and a gather of a
    /// knot (`issue28-done-everywhere`): each compiles to `done`, as inklecate's
    /// `Divert.isDone` does, so every path ends safely. The arm's path also pins
    /// that the prose after its block does not play, and the last path that the
    /// gather after the weave does.
    @Test(arguments: [0, 1, 2, 3])
    func `-> DONE stops the flow safely wherever it is written`(choice: Int) throws {
        let name = "issue28-done-everywhere"
        let (native, oracle) = try CompilerOracle.compileAndPlay(name, choiceScript: [choice])
        #expect(native == oracle)

        let nativeStory = Story(blueprint: try InkCompiler.compile(source: try CompilerOracle.source(name)))
        let nativeStops = try Self.stops(of: nativeStory, firstChoice: choice)
        #expect(nativeStops.last == .end(didSafeExit: true))
        let referenceStops = try Self.stops(of: try Story(json: try CompilerOracle.oracleJSON(name)), firstChoice: choice)
        #expect(nativeStops == referenceStops)
    }
}
