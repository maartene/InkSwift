// WHY-NEW-FILE: Sources/SwiftInkRuntime/Compiler/Codegen/StoryOutline.swift
//   CLOSEST-EXISTING: Sources/SwiftInkRuntime/Compiler/Codegen/RuntimeObjectEmitter.swift
//   EXTENSION-COST: grouping the statement stream into knots / stitches /
//     functions, and deriving the label and path tables from those groups, lived
//     in RuntimeObjectEmitter (past 1,400 lines) and returned a four-way tuple.
//   PARALLEL-RATIONALE: StoryOutline is built once, before any lowering, from the
//     parser's flat statement stream. RuntimeObjectEmitter lowers its sections;
//     LoweringContext reads its label and path tables. It does no lowering itself.

import Foundation

/// The story's top-level structure: the root body, the stitches declared before
/// the first knot, the knots (each with its stitches), and the functions.
struct StoryOutline {

    /// A knot and its body, plus the stitches declared inside it.
    struct Knot {
        let name: String
        let body: [InkStatement]
        let stitches: [Stitch]
    }

    /// A stitch and its body.
    struct Stitch {
        let name: String
        let body: [InkStatement]
    }

    /// A function definition and the body lines that follow its header.
    struct Function {
        let name: String
        let parameters: [FunctionParameter]
        let body: [InkStatement]
    }

    let rootBody: [InkStatement]
    let rootStitches: [Stitch]
    let knots: [Knot]
    let functions: [Function]

    /// Split the flat stream into the pre-stitch root body, the ordered TOP-LEVEL
    /// stitches, the ordered knots, and the ordered function definitions. Knot and
    /// function headers terminate the preceding group; a top-level stitch header
    /// (`= name` before the first knot) opens an addressable root section whose body
    /// runs until the next stitch/knot/function header — mirroring how `readKnot`
    /// groups a knot's own stitches, so a `-> name` divert resolves to a real
    /// container instead of dead-ending in the flattened root body.
    init(_ statements: [InkStatement]) {
        var root = SectionAccumulator()
        var knots: [Knot] = []
        var functions: [Function] = []
        var index = 0
        while index < statements.count {
            switch statements[index].kind {
            case .functionDefinition(let name, let parameters, _):
                root.closeStitch()
                let (body, nextIndex) = Self.readDefinitionBody(after: index, in: statements)
                functions.append(Function(name: name, parameters: parameters, body: body))
                index = nextIndex
            case .knot(let name):
                root.closeStitch()
                let (knot, nextIndex) = Self.readKnot(named: name, after: index, in: statements)
                knots.append(knot)
                index = nextIndex
            case .stitch(let name):
                root.openStitch(name)
                index += 1
            default:
                root.append(statements[index])
                index += 1
            }
        }
        root.closeStitch()
        self.rootBody = root.body
        self.rootStitches = root.stitches
        self.knots = knots
        self.functions = functions
    }

    // MARK: - Label and path tables

    /// The weave-label addressing table: dotted source name -> absolute compiled
    /// container path.
    ///
    /// Discovery pre-pass (ADR-011 EXTEND #3): record the labelled weave-point
    /// paths before lowering so read-count references resolve order-independently.
    /// Weave labels live in the root body AND inside knot/stitch bodies (e.g.
    /// TheIntercept's `(delay)` under `start`, `(tellme)` under `start.waited`);
    /// each is keyed by its enclosing knot/stitch prefix so a dotted read-count
    /// (`start.delay`) resolves to the absolute container path. A top-level stitch
    /// is a root section, so its weave labels are keyed by the bare stitch name
    /// prefix (`[stitch]`) — the same way a knot's own body labels are keyed by
    /// `[knot]` — so a read-count reference into one resolves.
    ///
    /// Bare-name local resolution (step 01-04): a read-count subject spelled by
    /// its BARE label (`{lift_up_cup:he|Harris}` referencing the `(lift_up_cup)`
    /// choice in the same stitch) resolves in inklecate's local scope. Each bare
    /// label that is UNIQUE story-wide is registered so the bare reference resolves;
    /// duplicated bare labels (e.g. `opts`/`yes` reused across knots) stay
    /// dotted-only — registering them would mis-resolve to the last knot's path.
    func weaveLabelPaths() -> [String: [String]] {
        var table = WeaveEmitter.discover(rootBody).labelPaths
        // Keys are prefixed by their section, so sections only collide when a
        // root stitch shares a knot's name; the root stitch is registered last.
        for section in sections {
            for (key, path) in WeaveEmitter.discoverLabelPaths(section.body, keyPrefix: section.keyPrefix) {
                table[key] = path
            }
        }
        for (label, path) in uniqueBareLabelPaths() where table[label] == nil {
            table[label] = path
        }
        return table
    }

    /// The knot/stitch read-count path table (ADR-011 EXTEND #2). A knot is
    /// addressed by `[knot.name]`; a stitch nested under it by `[knot.name,
    /// stitch.name]` — the same namedContent path `emitKnot`/`emitStitch` key their
    /// containers by. The dotted source name (`knot.stitch`) is the lookup key. A
    /// top-level stitch is addressed by its bare name (`[stitch]`) directly under
    /// root — so a `-> stitch` divert (or `knot.stitch`-style read-count) resolves
    /// to the container `emitRoot` keys it by.
    func knotStitchPaths() -> [String: [String]] {
        var paths: [String: [String]] = [:]
        for section in sections {
            paths[section.keyPrefix.joined(separator: ".")] = section.keyPrefix
        }
        return paths
    }

    /// Every knot body, knot stitch body and top-level stitch body, with the key
    /// prefix its containers are addressed by: knots (each followed by its
    /// stitches) first, then the top-level stitches.
    private var sections: [(body: [InkStatement], keyPrefix: [String])] {
        var sections: [(body: [InkStatement], keyPrefix: [String])] = []
        for knot in knots {
            sections.append((knot.body, [knot.name]))
            for stitch in knot.stitches {
                sections.append((stitch.body, [knot.name, stitch.name]))
            }
        }
        for stitch in rootStitches {
            sections.append((stitch.body, [stitch.name]))
        }
        return sections
    }

    /// Each BARE weave label that occurs in exactly one body story-wide, with its
    /// path. A bare name occurring in two or more bodies is ambiguous and omitted.
    private func uniqueBareLabelPaths() -> [String: [String]] {
        var occurrences: [String: [[String]]] = [:]
        for section in [(body: rootBody, keyPrefix: [String]())] + sections {
            for (label, path) in WeaveEmitter.discoverBareLabelPaths(section.body, keyPrefix: section.keyPrefix) {
                occurrences[label, default: []].append(path)
            }
        }
        return occurrences.compactMapValues { $0.count == 1 ? $0[0] : nil }
    }

    // MARK: - Grouping

    /// Read one knot starting just after its header at `headerIndex`, consuming
    /// statements up to (but not including) the next knot/function header.
    private static func readKnot(
        named name: String,
        after headerIndex: Int,
        in statements: [InkStatement]
    ) -> (knot: Knot, nextIndex: Int) {
        var knot = SectionAccumulator()
        var index = headerIndex + 1
        while index < statements.count, isDefinitionHeader(statements[index].kind) == false {
            if case .stitch(let stitchName) = statements[index].kind {
                knot.openStitch(stitchName)
            } else {
                knot.append(statements[index])
            }
            index += 1
        }
        knot.closeStitch()
        return (Knot(name: name, body: knot.body, stitches: knot.stitches), index)
    }

    /// Read a function body just after its header at `headerIndex`, consuming
    /// statements up to (but not including) the next knot/function header.
    private static func readDefinitionBody(
        after headerIndex: Int,
        in statements: [InkStatement]
    ) -> (body: [InkStatement], nextIndex: Int) {
        var body: [InkStatement] = []
        var index = headerIndex + 1
        while index < statements.count, isDefinitionHeader(statements[index].kind) == false {
            body.append(statements[index])
            index += 1
        }
        return (body, index)
    }

    /// True when a statement kind opens a top-level definition (knot or function),
    /// terminating the preceding knot/function body.
    private static func isDefinitionHeader(_ kind: InkStatementKind) -> Bool {
        switch kind {
        case .knot, .functionDefinition:
            return true
        default:
            return false
        }
    }

    /// Collects a section's own body and the stitches declared inside it: a
    /// stitch header closes the previous stitch and opens a new one; any other
    /// statement goes to the open stitch, or to the section body before the first.
    private struct SectionAccumulator {
        private(set) var body: [InkStatement] = []
        private(set) var stitches: [Stitch] = []
        private var pending: (name: String, body: [InkStatement])?

        mutating func openStitch(_ name: String) {
            closeStitch()
            pending = (name, [])
        }

        mutating func append(_ statement: InkStatement) {
            if pending != nil {
                pending?.body.append(statement)
            } else {
                body.append(statement)
            }
        }

        mutating func closeStitch() {
            if let pending {
                stitches.append(Stitch(name: pending.name, body: pending.body))
            }
            pending = nil
        }
    }
}
