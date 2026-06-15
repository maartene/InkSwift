// DIAGNOSTIC HARNESS (opt-in; not run in the normal suite).
// Plays TheIntercept native vs the inklecate oracle along the real script and
// reports the FIRST diverging output line (the next behavioral blocker) plus any
// surviving unresolved dotted read-count references. The behavioral complement to
// TheInterceptDivergenceDiagnostic (which is structural). Use it to re-diagnose the
// remaining gap after each emission-alignment phase.
//
// Run on demand:  DIAG_INTERCEPT2=1 swift test --filter TheInterceptPlaybackProbe
// Evidence for: docs/feature/native-compiler-emission-alignment/ (ADR-012 phases)
// Disabled by default so it does not slow or spam the standard suite.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("DIAG TheIntercept playback")
struct TheInterceptPlaybackProbe {

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIAG_INTERCEPT2"] != nil))
    func `play native vs oracle and report first divergence`() throws {
        let source = try CompilerOracle.source("TheIntercept")
        let oracleJSON = try CompilerOracle.oracleJSON("TheIntercept")
        let script = [0, 2, 1, 0, 0, 1, 2, 0, 1, 0]

        let oracle = try CompilerOracle.play(Story(json: oracleJSON), choiceScript: script, maxLines: 200)

        var native: [String] = []
        var nativeErr: String?
        do {
            native = try CompilerOracle.play(
                Story(blueprint: try InkCompiler.compile(source: source)),
                choiceScript: script, maxLines: 200
            )
        } catch { nativeErr = "\(error)" }

        print("\n===== THEINTERCEPT PLAYBACK PROBE =====")
        if let nativeErr { print("NATIVE PLAY THREW: \(nativeErr)") }
        print("native lines=\(native.count)  oracle lines=\(oracle.count)")

        let n = min(native.count, oracle.count)
        var firstDiff = -1
        for i in 0..<n where native[i] != oracle[i] { firstDiff = i; break }
        if firstDiff == -1 && native.count == oracle.count {
            print("=> NO DIVERGENCE: native == oracle for all \(oracle.count) lines. (e2e would PASS)")
        } else {
            let at = firstDiff == -1 ? n : firstDiff
            print("=> matched \(at) lines, then DIVERGE at index \(at):")
            for i in max(0, at - 2)..<at { print("     [\(i)] = \(oracle[i])") }
            print("   NATIVE[\(at)] = \(at < native.count ? native[at] : "<none — native ran out>")")
            print("   ORACLE[\(at)] = \(at < oracle.count ? oracle[at] : "<none — oracle ran out>")")
            print("   next 3 oracle lines:")
            for i in at..<min(oracle.count, at + 3) { print("     O[\(i)] = \(oracle[i])") }
            print("   next 3 native lines:")
            for i in at..<min(native.count, at + 3) { print("     N[\(i)] = \(native[i])") }
        }

        let dotted = survivingDotted(in: try InkCompiler.compile(source: source).root)
        print("\n-- surviving unresolved dotted variableReferences (#4b) : \(dotted.count) --")
        for name in dotted.sorted() { print("   \(name)") }

        #expect(Bool(true))
    }
}

private func survivingDotted(in root: ContainerNode) -> Set<String> {
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
