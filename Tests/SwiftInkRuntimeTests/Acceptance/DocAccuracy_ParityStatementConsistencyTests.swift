// @us-04
//
// US-04 — Honest supported-parity / known-gaps statement.
//
// Doc-accuracy guard: the parity statement at
// docs/reference/js-bridge-vs-native-parity.md must recommend the native runtime,
// reference (not duplicate) the construct-gap SSOT, name the three API gaps, name
// the v3.0.0 runway, and make no "full parity" over-claim.
//
// PLATFORM-NEUTRAL by design: NO `import InkSwift`. This suite therefore runs on
// Linux CI as well as macOS. It reads the repository's markdown as plain text,
// locating the repo root by walking up from #filePath until Package.swift is found.

import Testing
import Foundation

/// Shared repo-root + file-reading helper for the platform-neutral doc-accuracy
/// guard suites (reused by DocAccuracy_MigrationGuideCoverageTests). Internal
/// visibility: both suites live in the same test target.
enum DocAccuracySupport {

    /// Walks up from the given source file until it finds the directory holding
    /// `Package.swift`, which is the repository root.
    static func repositoryRoot(from filePath: String = #filePath) -> URL {
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("Package.swift").path
        ) {
            let parent = directory.deletingLastPathComponent()
            precondition(
                parent.path != directory.path,
                "Package.swift not found walking up from \(filePath)"
            )
            directory = parent
        }
        return directory
    }

    /// Reads a repo-relative file as UTF-8 text.
    static func contents(of relativePath: String) throws -> String {
        let url = repositoryRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Extracts the set of tokens that MUST appear in prose for every `public`
    /// `func` / `var` / `init` member declared directly on `typeName`. For the
    /// initializer the required token is the constructor-call form `TypeName(`.
    static func publicMembers(ofType typeName: String, inSwiftSource source: String) -> Set<String> {
        guard let classRange = source.range(of: "class \(typeName)") else { return [] }
        let afterClass = source[classRange.upperBound...]
        let body: Substring
        if let optionRange = afterClass.range(of: "\npublic struct ") {
            body = afterClass[..<optionRange.lowerBound]
        } else {
            body = afterClass
        }

        var members = Set<String>()
        for keyword in ["func", "var"] {
            for name in matches(pattern: "public\\s+\(keyword)\\s+([A-Za-z_][A-Za-z0-9_]*)", in: String(body)) {
                members.insert(name)
            }
        }
        if String(body).range(of: "public init") != nil {
            members.insert("\(typeName)(")
        }
        return members
    }

    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let captured = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[captured])
        }
    }
}

@Suite("Doc Accuracy — Parity statement consistency (US-04)")
struct DocAccuracy_ParityStatementConsistencyTests {

    private static let parityStatementPath = "docs/reference/js-bridge-vs-native-parity.md"

    @Test func `the parity statement exists and recommends SwiftInkRuntime for new projects`() throws {
        let parity = try DocAccuracySupport.contents(of: Self.parityStatementPath)
        #expect(parity.contains("SwiftInkRuntime"), "parity statement must name the recommended native runtime")
        #expect(parity.lowercased().contains("recommend"), "parity statement must recommend the native runtime")
    }

    @Test func `the parity statement references the construct-gap SSOT instead of duplicating it`() throws {
        let parity = try DocAccuracySupport.contents(of: Self.parityStatementPath)
        #expect(
            parity.contains("ink-feature-reference.md"),
            "construct gaps must reference docs/product/ink-feature-reference.md (the SSOT), not be duplicated"
        )
    }

    @Test func `the parity statement names the three API gaps`() throws {
        let parity = try DocAccuracySupport.contents(of: Self.parityStatementPath)
        #expect(parity.contains("Combine"), "API gap: Combine reactive observation must be listed")
        #expect(parity.lowercased().contains("tag shape"), "API gap: tag shape must be listed")
        #expect(parity.lowercased().contains("error handling"), "API gap: error handling must be listed")
    }

    @Test func `the parity statement names the v3.0.0 removal runway`() throws {
        let parity = try DocAccuracySupport.contents(of: Self.parityStatementPath)
        #expect(parity.contains("v3.0.0"), "parity statement must name the v3.0.0 removal runway")
    }

    @Test func `the parity statement makes no full-parity over-claim`() throws {
        let parity = try DocAccuracySupport.contents(of: Self.parityStatementPath)
        #expect(
            parity.lowercased().contains("full parity") == false,
            "parity statement must not over-claim 'full parity'"
        )
    }
}
