import Testing
@testable import SwiftInkRuntime

// Step 02-02 — "Discovery pre-pass and weaveLabelPaths table" (weave-label
// read-count addressing slice, EXTEND #3: the inklecate phase-1 analogue —
// `ResolveWeavePointNaming`). Internal codegen-mechanism step with no port-level
// acceptance test; these are example-based AST-shape / table-content oracle tests
// (object-oriented paradigm per CLAUDE.md) driving the discovery pre-pass +
// resolver keying directly — the legitimate unit-level driving port for this
// internal mechanism (PORT-TO-PORT note: correct here, not an escalation).
//
// They pin all five criteria:
//   1. The pre-pass records labelled-only `label -> absolute-path` entries into
//      the result table before expression lowering runs.
//   2. The pre-pass collects the SET of labels that are read-count-referenced
//      (a dotted condition subject naming a known label) for later flagging.
//   3. `WeaveResolver.resolve` writes `label -> path` at its existing keying site
//      reusing the already-computed keyPrefix (the table from `lower` matches the
//      pre-pass table — same arithmetic, no re-derivation).
//   4. Forward references resolve: a label referenced before it is lowered in
//      source order still maps to its path (order-independence).
//   5. Unlabelled containers (`g-N`/`c-N`) are NOT registered in the table
//      (labelled-only addressability).
@Suite("WeaveEmitter — discovery pre-pass and weaveLabelPaths table")
struct WeaveDiscoveryPrePassTests {

    /// Run the discovery pre-pass over a source body's parsed weave.
    private func discover(
        _ source: String
    ) throws -> (labelPaths: [String: [String]], referencedLabels: Set<String>) {
        let statements = try InkParser.parse(source)
        return WeaveEmitter.discover(statements)
    }

    /// Lower a source body's weave through the real WeaveEmitter, returning the
    /// resolver-written label->path table (criterion 3 surface).
    private func lowerLabelPaths(_ source: String) throws -> [String: [String]] {
        let statements = try InkParser.parse(source)
        return try WeaveEmitter.lowerWithLabelPaths(statements) { _ in [] }.labelPaths
    }

    // Criterion 1 — the pre-pass records a labelled choice at its absolute path.
    @Test func `records a labelled choice container at its absolute path`() throws {
        let discovered = try discover("* (door) Open the door")
        #expect(discovered.labelPaths["door"] == ["door"])
    }

    // Criterion 1 — the pre-pass records a labelled gather at its absolute path.
    @Test func `records a labelled gather container at its absolute path`() throws {
        let discovered = try discover(
            """
            * pick
            - (after) onward
            """
        )
        #expect(discovered.labelPaths["after"] == ["after"])
    }

    // Criterion 5 — unlabelled `c-N` / `g-N` containers are NOT registered.
    @Test func `does not register unlabelled c-N or g-N containers`() throws {
        let discovered = try discover(
            """
            * plain choice
            - plain gather
            """
        )
        #expect(discovered.labelPaths.isEmpty)
    }

    // Criterion 5 — only the labelled container is registered when labelled and
    // unlabelled containers are mixed.
    @Test func `registers only the labelled container among mixed containers`() throws {
        let discovered = try discover(
            """
            * (start) first
            * second
            """
        )
        #expect(discovered.labelPaths["start"] == ["start"])
        #expect(discovered.labelPaths.keys.count == 1)
    }

    // Criterion 1 — a nested labelled choice is recorded at its qualified
    // absolute path (parent label prefix + own label).
    @Test func `records a nested labelled choice at its qualified absolute path`() throws {
        let discovered = try discover(
            """
            * (outer) first
            * * (inner) deeper
            """
        )
        #expect(discovered.labelPaths["outer"] == ["outer"])
        #expect(discovered.labelPaths["inner"] == ["outer", "inner"])
    }

    // Criterion 2 — a dotted read-count reference naming a known label is
    // collected into the referenced-label SET.
    @Test func `collects a dotted read-count reference naming a known label`() throws {
        let discovered = try discover(
            """
            * (cant_talk) {cant_talk: again} body
            """
        )
        #expect(discovered.referencedLabels.contains("cant_talk"))
    }

    // Criterion 2 — a bare (non-dotted) variable that is not a known label is NOT
    // collected as a read-count reference.
    @Test func `does not collect a plain variable reference as a read-count label`() throws {
        let discovered = try discover(
            """
            * (cant_talk) {drugged: again} body
            """
        )
        #expect(discovered.referencedLabels.contains("drugged") == false)
    }

    // Criterion 4 — a forward reference resolves: the label referenced before it
    // is defined in source order still maps to its path (pre-pass runs before
    // lowering, so order does not matter).
    @Test func `resolves a forward reference to a later-defined label`() throws {
        let discovered = try discover(
            """
            * {later: seen} first
            * (later) second
            """
        )
        #expect(discovered.labelPaths["later"] == ["later"])
        #expect(discovered.referencedLabels.contains("later"))
    }

    // Criterion 3 — the resolver writes label->path at its existing keying site
    // reusing keyPrefix: the table produced by lowering matches the pre-pass
    // table (same path arithmetic, labelled-only, no re-derivation).
    @Test func `resolver writes label to path matching the pre-pass table`() throws {
        let source = """
            * (outer) first
            * * (inner) deeper
            * plain
            """
        let lowered = try lowerLabelPaths(source)
        #expect(lowered["outer"] == ["outer"])
        #expect(lowered["inner"] == ["outer", "inner"])
        #expect(lowered.keys.count == 2)
    }
}
