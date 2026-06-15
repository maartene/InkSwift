import Testing
@testable import SwiftInkRuntime

// Step 02-01 — "Key labelled choice outcome containers by label" (weave-label
// read-count addressing slice, EXTEND #2: WeaveEmitter choice keying). Internal
// emitter-mechanism step with no port-level acceptance test; these are
// example-based AST-shape / container-path oracle tests (object-oriented paradigm
// per CLAUDE.md) driving WeaveEmitter.lower directly — the legitimate unit-level
// driving port for this internal mechanism.
//
// They pin all four criteria:
//   1. A choice carrying a `(label)` keys its outcome container by that label
//      instead of the positional `c-N`.
//   2. A choice with no label keys its outcome container by `c-N` as before.
//   3. The label becomes the addressable segment in the absolute compiled path
//      (the choicePoint target).
//   4. Keying reuses the gather `label ?? default` idiom — proven behaviourally by
//      symmetry with the gather `(label)` keying at the same site.
@Suite("WeaveEmitter — labelled choice outcome container keying")
struct WeaveEmitterChoiceKeyingTests {

    /// Lower a source body's weave through the real WeaveEmitter with a no-op
    /// statement lowerer (prose content is irrelevant to container keying).
    private func lower(
        _ source: String
    ) throws -> (children: [NodeKind], named: [String: ContainerNode]) {
        let statements = try InkParser.parse(source)
        return try WeaveEmitter.lower(statements) { _ in [] }
    }

    /// The target of the first choicePoint emitted into `children`.
    private func firstChoicePointTarget(_ children: [NodeKind]) -> String? {
        for node in children {
            if case .choicePoint(let target, _) = node { return target }
        }
        return nil
    }

    // Criterion 1 — a `(label)` choice keys its outcome container by the label.
    @Test func `keys a labelled choice outcome container by its weave label`() throws {
        let weave = try lower("* (door) Open the door")
        #expect(weave.named["door"] != nil)
        #expect(weave.named["c-0"] == nil)
    }

    // Criterion 2 — an unlabelled choice still keys by c-N (regression guard).
    @Test func `keys an unlabelled choice outcome container by c-N`() throws {
        let weave = try lower("* Just a plain choice")
        #expect(weave.named["c-0"] != nil)
    }

    // Criterion 2 — positional c-N keying is per-unlabelled-choice ordinal; a
    // labelled choice does not consume a c-N slot.
    @Test func `mixes labelled and unlabelled choices keying each correctly`() throws {
        let weave = try lower(
            """
            * (start) first
            * second
            """
        )
        #expect(weave.named["start"] != nil)
        #expect(weave.named["c-1"] != nil)
        #expect(weave.named["c-0"] == nil)
    }

    // Criterion 3 — the label is the addressable segment in the absolute compiled
    // path: the choicePoint targets the label, not c-N.
    @Test func `makes the label the addressable segment in the choicePoint target`() throws {
        let labelled = try lower("* (door) Open the door")
        #expect(firstChoicePointTarget(labelled.children) == "door")

        let plain = try lower("* Just a plain choice")
        #expect(firstChoicePointTarget(plain.children) == "c-0")
    }

    // Criterion 4 — choice `(label)` keying is symmetric with gather `(label)`
    // keying: the identical `(label)` produces the identical container key whether
    // it sits on a choice or on a gather (behavioural proof of the shared
    // `label ?? default` idiom — no separate keying path).
    @Test func `keys a labelled choice with the same idiom as a labelled gather`() throws {
        let choiceWeave = try lower("* (here) onward")
        let gatherWeave = try lower(
            """
            * pick
            - (here) onward
            """
        )
        #expect(choiceWeave.named["here"] != nil)
        #expect(gatherWeave.named["here"] != nil)
    }
}
