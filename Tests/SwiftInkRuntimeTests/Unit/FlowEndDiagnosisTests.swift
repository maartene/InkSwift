// Test Budget: 3 distinct behaviors x 2 = 6 max unit tests
// Behaviors:
//   B1 — a ran-out stop with no choices reports the C# message chosen by the
//        return-stack top (tunnel, function, empty)
//   B2 — a safe exit, a stop at a choice point, or no stop at all reports nothing
//   B3 — a choice-continuation root that exhausts is a ran-out stop on an empty
//        stack, so the engine reports the empty-stack message
//
// ADR-020 §5, C# Story.cs ContinueInternal ~502-516.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite struct FlowEndDiagnosisTests {

    // The function message is covered here only. The C# runtime pops a function
    // frame when its body runs out (Story.cs NextContent ~2676-2705) and so does
    // InkEngine (returnFromExhaustedFunctionBody); inklecate rejects diverts and
    // choices inside a function, so a function body cannot leave its frame by any
    // other route. Probed in step 02-04 by instrumenting the epilogue over the full
    // test suite, the conformance backlog included: no well-formed story stops
    // ran-out with a function frame on top.
    @Test(arguments: [
        (CallKind?.some(.tunnel), "unexpectedly reached end of content. Do you need a '->->' to return from a tunnel?"),
        (CallKind?.some(.function), "unexpectedly reached end of content. Do you need a '~ return'?"),
        (CallKind?.none, "ran out of content. Do you need a '-> DONE' or '-> END'?"),
    ])
    func `a ran-out stop without choices reports the message chosen by the return-stack top`(
        top: CallKind?, expected: String
    ) {
        let message = FlowEndDiagnosis.message(stopReason: .ranOut, returnStackTop: top, choicesEmpty: true)

        #expect(message == expected)
    }

    @Test(arguments: [
        (InkEngine.FlowStop?.some(.safeExit), true),
        (InkEngine.FlowStop?.some(.ranOut), false),
        (InkEngine.FlowStop?.none, true),
    ])
    func `a safe exit, a stop at a choice point or no stop reports nothing`(
        stop: InkEngine.FlowStop?, choicesEmpty: Bool
    ) {
        for top in [CallKind?.none, .tunnel, .function] {
            #expect(FlowEndDiagnosis.message(stopReason: stop, returnStackTop: top, choicesEmpty: choicesEmpty) == nil)
        }
    }

    // The C# named-container null-pointer case: a choice body (named content
    // only) runs out, so IncrementContentPointer stops with an empty call stack.
    // Probed in step 02-04 by instrumenting this path over the full test suite,
    // the conformance backlog included: the only well-formed stories that reach
    // it are the deliberate loose ends of loose-end-weave-in-knot and
    // loose-end-root-choices-hidden, where `inklecate -p` reports the same
    // "ran out of content" error.
    @Test func `a choice-continuation root that exhausts reports the empty-stack message`() throws {
        let body = ContainerNode(children: [.text("Picked"), .newline], namedContent: [:], flags: 0, name: nil)
        let root = ContainerNode(
            children: [.choicePoint(target: PathReference(parsing: ".^.c-0"), flags: .isOnceOnly)],
            namedContent: ["c-0": body], flags: 0, name: nil)
        let engine = InkEngine(root: root)
        engine.step()
        try #require(engine.currentChoices.count == 1)
        try #require(engine.currentErrors.isEmpty)

        try engine.chooseChoice(at: 0)
        engine.step()

        #expect(engine.currentText == "Picked\n")
        #expect(engine.currentErrors == ["ran out of content. Do you need a '-> DONE' or '-> END'?"])
    }
}
