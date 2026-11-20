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

    enum Stop: Equatable {
        case line(String)
        case choices([String])
        case end(didSafeExit: Bool)
    }

    private static let fixture = "loose-end-weave-in-knot"
    private static let maximumStops = 12
    private static let maximumContinues = 500

    /// Play `story` along `script` (then always the first choice), recording each
    /// non-empty line and each stop until the flow ends without choices.
    static func stops(of story: Story, script: [Int]) throws -> [Stop] {
        var stops: [Stop] = []
        var continues = 0
        while stops.count < maximumStops {
            while story.canContinue, continues < maximumContinues {
                let line = story.continue().trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty == false { stops.append(.line(line)) }
                continues += 1
            }
            let choices = story.currentChoices.map(\.text)
            guard choices.isEmpty == false else {
                stops.append(.end(didSafeExit: story.engine.didSafeExit))
                break
            }
            let taken = stops.filter { if case .choices = $0 { return true } else { return false } }.count
            try story.chooseChoice(at: taken < script.count ? script[taken] : 0)
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

    // MARK: Criteria 2 and 3 — knots run out, the root ends safely

    /// `loose-end-weave-in-knot`: root choice 0 runs a knot's weave to the prose
    /// after its gather; choice 1 revisits a knot whose only choice is used up, so
    /// the second visit offers nothing; choice 2 does the same in a knot whose
    /// weave follows a block conditional, so the weave sits in the block's rejoin
    /// and must not fall back into the content before it; choice 3 stays in the
    /// root weave, which ends without `-> END`. Each path plays the same lines natively and from
    /// inklecate's JSON and stops the same way: the knots run out (no safe exit),
    /// the root reaches its `done`.
    @Test(arguments: [
        (0, false),
        (1, false),
        (2, false),
        (3, true),
    ])
    func `a knot's loose end runs out and the root weave ends safely, as on inklecate's JSON`(
        rootChoice: Int, endsSafely: Bool
    ) throws {
        let (native, oracle) = try CompilerOracle.compileAndPlay(Self.fixture, choiceScript: [rootChoice, 0, 0])
        #expect(native == oracle)

        let nativeStops = try Self.stops(of: try Self.nativeStory(Self.fixture), script: [rootChoice])
        let referenceStops = try Self.stops(of: try Self.referenceStory(Self.fixture), script: [rootChoice])
        #expect(nativeStops.last == .end(didSafeExit: endsSafely))
        #expect(nativeStops == referenceStops)
    }

    /// `loose-end-root-choices-hidden`: the root weave's only choice is offered
    /// when the host sets `open`. Closed, the flow falls out of the root weave
    /// after its choice points and reaches the root's `done`: a safe exit. Open,
    /// the choice's nested weave offers nothing, and a nested weave has no `done`,
    /// so the flow runs out, as in inklecate's JSON.
    @Test(arguments: [
        (false, true),
        (true, false),
    ])
    func `a root weave that offers no choice ends safely and a nested one runs out, as on inklecate's JSON`(
        open: Bool, endsSafely: Bool
    ) throws {
        let name = "loose-end-root-choices-hidden"
        let native = try Self.nativeStory(name)
        let reference = try Self.referenceStory(name)
        native.setVariable("open", to: open)
        reference.setVariable("open", to: open)

        let nativeStops = try Self.stops(of: native, script: [])
        let referenceStops = try Self.stops(of: reference, script: [])
        #expect(nativeStops.last == .end(didSafeExit: endsSafely))
        #expect(nativeStops == referenceStops)
    }

    // MARK: Step 02-07 — a labelled root gather's choice points

    /// `divert-to-labelled-root-gather`: the story opens with `- (top)`, which
    /// inklecate auto-enters (no choice before it, C# `Weave.AddRuntimeForGather`)
    /// and so keeps inline in the root's content: when its choices are all used
    /// up, the flow falls out into the root's `done`. Choice 0 plays on to the
    /// next gather; choice 1 diverts back to `top` with its choices used up.
    /// Both stop safely, natively and on inklecate's JSON.
    @Test(arguments: [0, 1])
    func `a labelled root gather whose choices are used up ends safely, as on inklecate's JSON`(
        rootChoice: Int
    ) throws {
        let name = "divert-to-labelled-root-gather"
        let nativeStops = try Self.stops(of: try Self.nativeStory(name), script: [rootChoice])
        let referenceStops = try Self.stops(of: try Self.referenceStory(name), script: [rootChoice])
        #expect(nativeStops.last == .end(didSafeExit: true))
        #expect(nativeStops == referenceStops)
    }

    /// Only an auto-entered gather of the top-level weave falls out into the
    /// root's `done`. inklecate keeps a gather that follows a choice named-only,
    /// and a gather nested in a choice inline in that named-only outcome, so
    /// when their choices are hidden the flow runs out; a gather that opens the
    /// root weave, with or without a block conditional in its body, sits inline
    /// in the root and ends safely. Each expected stop is what inklecate's JSON
    /// for that source plays on the InkSwift runtime (probed in step 02-07).
    @Test(arguments: [
        ("VAR f = false\nStart.\n* [a]\n- (mid) Mid.\n* {f} [b]\n- After.\n",
         [Stop.line("Start."), .choices(["a"]), .line("Mid."), .end(didSafeExit: false)]),
        ("VAR f = false\nStart.\n* [a]\n- - (inner) Inner.\n** {f} [b]\n",
         [Stop.line("Start."), .choices(["a"]), .line("Inner."), .end(didSafeExit: false)]),
        ("VAR f = false\nStart.\n* [a]\n- (mid) Mid.\n{ f:\n  Yes.\n}\nAfter cond.\n* {f} [b]\n",
         [Stop.line("Start."), .choices(["a"]), .line("Mid."), .line("After cond."), .end(didSafeExit: false)]),
        ("VAR f = false\nStart.\n- (top) Top.\n{ f:\n  Yes.\n}\nAfter cond.\n* {f} [b]\n- After.\n",
         [Stop.line("Start."), .line("Top."), .line("After cond."), .end(didSafeExit: true)]),
    ])
    func `only a gather that opens the root weave ends safely when its choices are hidden`(
        source: String, expected: [Stop]
    ) throws {
        let story = Story(blueprint: try InkCompiler.compile(source: source))
        #expect(try Self.stops(of: story, script: []) == expected)
    }
}
