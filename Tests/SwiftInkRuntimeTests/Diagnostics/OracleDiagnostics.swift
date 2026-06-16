// REUSABLE ANY-STORY ORACLE DIAGNOSTICS (test-only; not run in the normal suite).
//
// Story-agnostic core extracted from the two TheIntercept-specific probes:
//   - TheInterceptDivergenceDiagnostic (STRUCTURAL native-vs-oracle tree diff)
//   - TheInterceptPlaybackProbe        (PLAYBACK first-divergence)
//
// Any bundled `.ink` / `.ink.json` fixture can now be diagnosed with ZERO new
// code via the env-driven OracleDivergenceProbe, or programmatically via the
// `firstDivergence` / `structuralCensus` / `expectNativeMatchesOraclePrefix`
// entry points below. The TheIntercept probes + the progress ratchet are thin
// callers (the committed WORKED EXAMPLE).
//
// Compares `InkCompiler.compile(source).root` (native) against
// `InkDecoder().decode(oracleJSON)` (inklecate oracle) using the CompilerOracle
// fixture loaders + deterministic playthrough.

import Testing
import Foundation
@testable import SwiftInkRuntime

enum OracleDiagnostics {

    // MARK: - Playback: first divergence

    /// Native/oracle playback comparison along a fixed choice `script`.
    struct DivergenceReport {
        let story: String
        let script: [Int]
        let nativeLineCount: Int
        let oracleLineCount: Int
        /// Number of leading lines that matched before the first divergence.
        let matchedPrefix: Int
        /// Index of the first diverging line, or -1 when native == oracle entirely.
        let firstDivergenceIndex: Int
        /// The native/oracle lines at the divergence index (nil when that side ran out).
        let nativeLineAtDivergence: String?
        let oracleLineAtDivergence: String?
        /// Surviving unresolved dotted `.variableReference` names in the native tree.
        let survivingDottedReferences: Set<String>
        /// Set when the native compile/playback threw.
        let nativeError: String?
        /// Context windows for the human-readable dump.
        let nativeLines: [String]
        let oracleLines: [String]

        var hasDivergence: Bool {
            nativeError != nil || firstDivergenceIndex != -1 || nativeLineCount != oracleLineCount
        }

        func printReport() {
            print("\n===== ORACLE PLAYBACK PROBE: \(story) =====")
            print("script=\(script)")
            if let nativeError { print("NATIVE PLAY THREW: \(nativeError)") }
            print("native lines=\(nativeLineCount)  oracle lines=\(oracleLineCount)")

            if !hasDivergence {
                print("=> NO DIVERGENCE: native == oracle for all \(oracleLineCount) lines. (e2e would PASS)")
            } else {
                let at = firstDivergenceIndex == -1 ? matchedPrefix : firstDivergenceIndex
                print("=> matched \(at) lines, then DIVERGE at index \(at):")
                for i in max(0, at - 2)..<at { print("     [\(i)] = \(oracleLines[i])") }
                print("   NATIVE[\(at)] = \(nativeLineAtDivergence ?? "<none — native ran out>")")
                print("   ORACLE[\(at)] = \(oracleLineAtDivergence ?? "<none — oracle ran out>")")
                print("   next 3 oracle lines:")
                for i in at..<min(oracleLineCount, at + 3) { print("     O[\(i)] = \(oracleLines[i])") }
                print("   next 3 native lines:")
                for i in at..<min(nativeLineCount, at + 3) { print("     N[\(i)] = \(nativeLines[i])") }
            }

            print("\n-- surviving unresolved dotted variableReferences : \(survivingDottedReferences.count) --")
            for name in survivingDottedReferences.sorted() { print("   \(name)") }
        }
    }

    /// Play `story`.ink (native) and `story`.ink.json (oracle) along `script` and
    /// report the first diverging output line plus surviving dotted read-count refs.
    static func firstDivergence(
        story: String,
        script: [Int],
        maxLines: Int = 200
    ) throws -> DivergenceReport {
        let source = try CompilerOracle.source(story)
        let oracleJSON = try CompilerOracle.oracleJSON(story)

        let oracle = try CompilerOracle.play(
            Story(json: oracleJSON), choiceScript: script, maxLines: maxLines
        )

        var native: [String] = []
        var nativeError: String?
        var survivingDotted: Set<String> = []
        do {
            let blueprint = try InkCompiler.compile(source: source)
            native = try CompilerOracle.play(
                Story(blueprint: blueprint), choiceScript: script, maxLines: maxLines
            )
            survivingDotted = survivingDottedReferences(in: blueprint.root)
        } catch {
            nativeError = "\(error)"
        }

        let bound = min(native.count, oracle.count)
        var firstDiff = -1
        for i in 0..<bound where native[i] != oracle[i] { firstDiff = i; break }
        let matched = firstDiff == -1 ? bound : firstDiff
        let at = firstDiff == -1 ? bound : firstDiff

        return DivergenceReport(
            story: story,
            script: script,
            nativeLineCount: native.count,
            oracleLineCount: oracle.count,
            matchedPrefix: matched,
            firstDivergenceIndex: firstDiff,
            nativeLineAtDivergence: at < native.count ? native[at] : nil,
            oracleLineAtDivergence: at < oracle.count ? oracle[at] : nil,
            survivingDottedReferences: survivingDotted,
            nativeError: nativeError,
            nativeLines: native,
            oracleLines: oracle
        )
    }

    // MARK: - Structural census

    /// Naming-invariant structural comparison of the native vs oracle trees.
    struct CensusReport {
        let story: String
        let nativeCensus: [String: Int]
        let oracleCensus: [String: Int]
        let nativeControl: [String: Int]
        let oracleControl: [String: Int]
        let namedContentFindings: [String]
        /// Set when the native compile threw (no tree to diff).
        let nativeError: String?

        func printReport() {
            print("\n===== ORACLE STRUCTURAL CENSUS: \(story) =====")
            if let nativeError {
                print("NATIVE COMPILE THREW: \(nativeError)")
                print("=> Blocker class A: parse/lower cannot complete; no native tree to diff.")
                return
            }
            print("NATIVE COMPILE: succeeded (produced a tree).")

            print("\n-- GLOBAL CENSUS (naming-invariant) --   [!! = differs]")
            for key in censusKeys {
                let nativeValue = nativeCensus[key] ?? 0
                let oracleValue = oracleCensus[key] ?? 0
                let marker = nativeValue == oracleValue ? "  " : "!!"
                let label = key.padding(toLength: 26, withPad: " ", startingAt: 0)
                print("\(marker) \(label) native=\(nativeValue)  oracle=\(oracleValue)")
            }

            print("\n-- CONTROL-COMMAND HISTOGRAM (by name) --")
            for key in Set(nativeControl.keys).union(oracleControl.keys).sorted() {
                let nativeValue = nativeControl[key] ?? 0
                let oracleValue = oracleControl[key] ?? 0
                let marker = nativeValue == oracleValue ? "  " : "!!"
                print("\(marker) cmd '\(key)'  native=\(nativeValue)  oracle=\(oracleValue)")
            }

            print("\n-- NAMED-CONTENT DIVERGENCES (stable names strict; auto c-/g- by count) --")
            for finding in namedContentFindings { print(finding) }
            print("\n-- total named-content findings: \(namedContentFindings.count) --")
        }
    }

    /// Compile `story`.ink natively and structurally diff it against the oracle tree.
    static func structuralCensus(story: String) throws -> CensusReport {
        let source = try CompilerOracle.source(story)
        let oracleJSON = try CompilerOracle.oracleJSON(story)
        let oracleRoot = try InkDecoder().decode(Data(oracleJSON.utf8))

        var nativeRoot: ContainerNode?
        var nativeError: String?
        do {
            nativeRoot = try InkCompiler.compile(source: source).root
        } catch {
            nativeError = "\(error)"
        }

        guard let nativeRoot else {
            return CensusReport(
                story: story,
                nativeCensus: [:], oracleCensus: census(oracleRoot),
                nativeControl: [:], oracleControl: controlHistogram(oracleRoot),
                namedContentFindings: [],
                nativeError: nativeError
            )
        }

        var findings: [String] = []
        walkNamed(path: "<root>", native: nativeRoot, oracle: oracleRoot, findings: &findings)

        return CensusReport(
            story: story,
            nativeCensus: census(nativeRoot),
            oracleCensus: census(oracleRoot),
            nativeControl: controlHistogram(nativeRoot),
            oracleControl: controlHistogram(oracleRoot),
            namedContentFindings: findings,
            nativeError: nil
        )
    }

    // MARK: - Ratchet assertion helper

    /// Assert native matches the oracle for at least the first `floor` lines.
    /// Failures point at the CALLER via `sourceLocation`.
    static func expectNativeMatchesOraclePrefix(
        story: String,
        script: [Int],
        floor: Int,
        maxLines: Int = 200,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let report = try firstDivergence(story: story, script: script, maxLines: maxLines)
        #expect(
            report.nativeLineCount >= floor,
            "native played only \(report.nativeLineCount) lines; expected at least \(floor)",
            sourceLocation: sourceLocation
        )
        #expect(
            Array(report.nativeLines.prefix(floor)) == Array(report.oracleLines.prefix(floor)),
            "native diverged from the oracle within the first \(floor) lines",
            sourceLocation: sourceLocation
        )
    }
}

// MARK: - Tree-walking primitives (shared)

private let censusKeys = [
    "containers", "flaggedContainers", "text", "newline", "divert",
    "choicePoint", "readCount", "variableReference", "dottedVariableReference",
    "nativeFunction", "variableAssignment"
]

private func census(_ root: ContainerNode) -> [String: Int] {
    var m: [String: Int] = [:]
    func bump(_ k: String) { m[k, default: 0] += 1 }
    func visit(_ c: ContainerNode) {
        bump("containers")
        if c.flags != 0 { bump("flaggedContainers") }
        for child in c.children {
            switch child {
            case .container(let nested): visit(nested)
            case .text: bump("text")
            case .newline: bump("newline")
            case .divert: bump("divert")
            case .choicePoint: bump("choicePoint")
            case .readCount: bump("readCount")
            case .variableReference(let name):
                bump("variableReference")
                if name.contains(".") { bump("dottedVariableReference") }
            case .nativeFunction: bump("nativeFunction")
            case .variableAssignment: bump("variableAssignment")
            default: break
            }
        }
        for nested in c.namedContent.values { visit(nested) }
    }
    visit(root)
    return m
}

private func controlHistogram(_ root: ContainerNode) -> [String: Int] {
    var m: [String: Int] = [:]
    func visit(_ c: ContainerNode) {
        for child in c.children {
            switch child {
            case .container(let nested): visit(nested)
            case .controlCommand(let name): m[name, default: 0] += 1
            default: break
            }
        }
        for nested in c.namedContent.values { visit(nested) }
    }
    visit(root)
    return m
}

private func isAuto(_ name: String) -> Bool {
    name.range(of: "^[cg]-[0-9]+$", options: .regularExpression) != nil
}

private func walkNamed(path: String, native: ContainerNode, oracle: ContainerNode, findings: inout [String]) {
    let nKeys = Set(native.namedContent.keys)
    let oKeys = Set(oracle.namedContent.keys)
    let nStable = nKeys.filter { !isAuto($0) }
    let oStable = oKeys.filter { !isAuto($0) }
    let missing = oStable.subtracting(nStable).sorted()
    let extra = nStable.subtracting(oStable).sorted()
    let nAuto = nKeys.filter(isAuto).count
    let oAuto = oKeys.filter(isAuto).count

    if !missing.isEmpty { findings.append("!! \(path): named in ORACLE, missing in NATIVE: \(missing)") }
    if !extra.isEmpty { findings.append("!! \(path): named in NATIVE, missing in ORACLE: \(extra)") }
    if nAuto != oAuto { findings.append("~  \(path): auto-named child count native=\(nAuto) oracle=\(oAuto)") }
    if native.flags != oracle.flags {
        findings.append("!! \(path): flags native=0x\(String(native.flags, radix: 16)) oracle=0x\(String(oracle.flags, radix: 16))")
    }
    for key in oStable.intersection(nStable).sorted() {
        walkNamed(path: path + "." + key, native: native.namedContent[key]!, oracle: oracle.namedContent[key]!, findings: &findings)
    }
}

private func survivingDottedReferences(in root: ContainerNode) -> Set<String> {
    var out: Set<String> = []
    func visit(_ c: ContainerNode) {
        for child in c.children {
            switch child {
            case .container(let nested): visit(nested)
            case .variableReference(let name): if name.contains(".") { out.insert(name) }
            default: break
            }
        }
        for nested in c.namedContent.values { visit(nested) }
    }
    visit(root)
    return out
}
