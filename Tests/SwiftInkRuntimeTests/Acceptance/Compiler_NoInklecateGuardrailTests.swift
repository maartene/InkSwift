// @us-04 @kpi-4 @guardrail
//
// KPI #4 — the no-inklecate guardrail. Supported stories compile with ZERO
// inklecate invocations: production `Compiler/` code must reference neither the
// external `inklecate` binary nor Foundation `Process` (it would be the only way
// to shell out). inklecate stays test-only/offline for fixture generation (DDD-10).
//
// This is a GUARDRAIL, not a feature behaviour: it passes against the scaffold
// (the scaffold spawns nothing) and must KEEP passing as the real compiler lands.
// A regression — any Process/inklecate symbol in production Compiler/ code —
// fails CI (KPI #4 blocking gate).

import Testing
import Foundation

@Suite("Compiler — No-inklecate Guardrail (KPI #4)")
struct Compiler_NoInklecateGuardrailTests {

    /// Production compiler source directory, resolved from this test file's path
    /// (working-directory-independent).
    private static var compilerSourceDir: URL {
        URL(fileURLWithPath: #filePath)            // …/Tests/SwiftInkRuntimeTests/Acceptance/<this>.swift
            .deletingLastPathComponent()           // …/Acceptance
            .deletingLastPathComponent()           // …/SwiftInkRuntimeTests
            .deletingLastPathComponent()           // …/Tests
            .deletingLastPathComponent()           // …/<package root>
            .appendingPathComponent("Sources/SwiftInkRuntime/Compiler", isDirectory: true)
    }

    /// The non-comment portion of a source line (everything before `//`).
    private static func codePart(of line: String) -> String {
        if let r = line.range(of: "//") { return String(line[..<r.lowerBound]) }
        return line
    }

    @Test func `production Compiler source references no inklecate binary and spawns no Process`() throws {
        let dir = Self.compilerSourceDir
        let fm = FileManager.default

        let enumerator = try #require(fm.enumerator(at: dir, includingPropertiesForKeys: nil),
                                      "Compiler source directory not found at \(dir.path)")

        var swiftFiles = 0
        var violations: [String] = []

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            swiftFiles += 1
            let contents = try String(contentsOf: url, encoding: .utf8)
            for (i, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = Self.codePart(of: String(line))
                if code.range(of: "inklecate", options: .caseInsensitive) != nil {
                    violations.append("\(url.lastPathComponent):\(i + 1) references inklecate in code")
                }
                if code.range(of: #"\bProcess\b"#, options: .regularExpression) != nil {
                    violations.append("\(url.lastPathComponent):\(i + 1) references Process (subprocess) in code")
                }
            }
        }

        #expect(swiftFiles > 0, "expected at least one Swift file under Compiler/")
        #expect(violations.isEmpty, "no-inklecate guardrail violated:\n\(violations.joined(separator: "\n"))")
    }
}
