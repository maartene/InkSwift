// Tests for the typed path values (ADR-016): PathReference parsing and its
// legacy dotted-string description.
// Driving port: PathReference(parsing:) / description — the only way a path
// string from `.ink.json` becomes a typed value.

import Foundation
import Testing
@testable import SwiftInkRuntime

@Suite("ContainerPath")
struct ContainerPathTests {

    // Test Budget:
    // Behavior 1: parse is total and description reproduces the input string
    // Behavior 2: integer-looking components are indices, all others are names
    // Behavior 3: relative and absolute references never compare equal
    // Budget = 3 behaviors × 2 = 6 unit tests max

    // MARK: - Behavior 1: round-trip

    @Test(arguments: [
        "", ".", ".^", ".^.^.x", "a.0.g-2", "0", "007", "99999999999999999999",
        "a.^.b", ".x.^.y", "^", "^.x", ".^.", "a..b", "-1", "+5",
    ])
    func `description reproduces every edge-case path string`(path: String) {
        #expect(PathReference(parsing: path).description == path)
    }

    @Test func `description reproduces every path string in the committed ink json fixtures`() throws {
        let corpus = try FixturePathCorpus.collect()

        #expect(corpus.count > 500)
        for path in corpus {
            #expect(PathReference(parsing: path).description == path)
        }
    }

    // MARK: - Behavior 2: component typing

    @Test func `integer components parse as indices and others as names`() {
        let expected = ContainerPath(components: [.name("a"), .index(0), .name("g-2"), .name("007"), .name("-1")])

        #expect(PathReference(parsing: "a.0.g-2.007.-1") == .absolute(expected))
    }

    @Test func `leading carets of a relative path count as parent steps`() {
        #expect(PathReference(parsing: "") == .absolute(ContainerPath(components: [])))
        #expect(PathReference(parsing: ".^") == .relative(parentSteps: 1, tail: []))
        #expect(PathReference(parsing: ".^.^.x.3") == .relative(parentSteps: 2, tail: [.name("x"), .index(3)]))
        #expect(PathReference(parsing: ".x.^.y") == .relative(parentSteps: 0, tail: [.name("x"), .name("^"), .name("y")]))
    }

    // MARK: - Behavior 3: relative vs absolute

    @Test func `a relative and an absolute reference with equal components compare unequal`() {
        #expect(PathReference(parsing: "hello.1.world") == PathReference(parsing: "hello.1.world"))
        #expect(PathReference(parsing: "hello.1.world") != PathReference(parsing: ".hello.1.world"))
        #expect(PathReference(parsing: "knot.0") != PathReference(parsing: "knot.c-0"))
    }
}

/// Every path string in the committed `.ink.json` fixtures (Fixtures/ and
/// Fixtures/Conformance/, flattened into the test bundle): divert, tunnel and
/// function-call targets, choice targets, pushed divert targets and read-count
/// paths. Variable diverts (`"var": true`) carry variable names, not paths.
private enum FixturePathCorpus {
    private static let pathKeys: Set<String> = ["->", "->t->", "f()", "*", "^->", "CNT?"]

    static func collect() throws -> Set<String> {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        var paths: Set<String> = []
        for url in urls where url.lastPathComponent.hasSuffix(".ink.json") {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url), options: [.fragmentsAllowed])
            walk(json, into: &paths)
        }
        return paths
    }

    private static func walk(_ value: Any, into paths: inout Set<String>) {
        if let array = value as? [Any] {
            array.forEach { walk($0, into: &paths) }
        } else if let object = value as? [String: Any] {
            collectPaths(of: object, into: &paths)
            object.values.forEach { walk($0, into: &paths) }
        }
    }

    private static func collectPaths(of object: [String: Any], into paths: inout Set<String>) {
        guard object["var"] as? Bool != true else { return }
        for key in pathKeys {
            if let path = object[key] as? String {
                paths.insert(path)
            }
        }
    }
}
