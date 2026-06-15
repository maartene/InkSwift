// DIAGNOSTIC HARNESS (opt-in; not run in the normal suite).
// Compares the native compiler's emitted ContainerNode tree for TheIntercept
// against the inklecate oracle tree (TheIntercept.ink.json decoded by the
// runtime decoder), to enumerate ALL structural divergences at compile time
// instead of discovering them one playthrough line at a time.
//
// Run on demand:  DIAG_INTERCEPT=1 swift test --filter TheInterceptDivergenceDiagnostic
// Evidence for: docs/analysis/theintercept-native-divergence-2026-06-15.md
// Disabled by default so it does not slow or spam the standard suite.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("DIAG TheIntercept divergence")
struct TheInterceptDivergenceDiagnostic {

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIAG_INTERCEPT"] != nil))
    func `dump native-vs-oracle structural divergences for TheIntercept`() throws {
        let source = try CompilerOracle.source("TheIntercept")
        let oracleJSON = try CompilerOracle.oracleJSON("TheIntercept")

        let oracleRoot = try InkDecoder().decode(Data(oracleJSON.utf8))

        var nativeRoot: ContainerNode?
        var compileError: String?
        do {
            nativeRoot = try InkCompiler.compile(source: source).root
        } catch {
            compileError = "\(error)"
        }

        print("\n===== THEINTERCEPT DIVERGENCE DIAGNOSTIC =====")

        if let compileError {
            print("NATIVE COMPILE THREW: \(compileError)")
            print("=> Blocker class A: parse/lower cannot complete; no native tree to diff.")
            return
        }
        guard let nativeRoot else { return }
        print("NATIVE COMPILE: succeeded (produced a tree).")

        print("\n-- GLOBAL CENSUS (naming-invariant) --   [!! = differs]")
        let n = census(nativeRoot)
        let o = census(oracleRoot)
        for key in censusKeys {
            let nv = n[key] ?? 0
            let ov = o[key] ?? 0
            print("\(nv == ov ? "  " : "!!") \(key.padding(toLength: 26, withPad: " ", startingAt: 0)) native=\(nv)  oracle=\(ov)")
        }

        print("\n-- CONTROL-COMMAND HISTOGRAM (by name) --")
        let nc = controlHistogram(nativeRoot)
        let oc = controlHistogram(oracleRoot)
        for key in Set(nc.keys).union(oc.keys).sorted() {
            let nv = nc[key] ?? 0, ov = oc[key] ?? 0
            print("\(nv == ov ? "  " : "!!") cmd '\(key)'  native=\(nv)  oracle=\(ov)")
        }

        print("\n-- NAMED-CONTENT DIVERGENCES (stable names strict; auto c-/g- by count) --")
        var findings = 0
        walkNamed(path: "<root>", native: nativeRoot, oracle: oracleRoot, findings: &findings)
        print("\n-- total named-content findings: \(findings) --")

        #expect(Bool(true))
    }
}

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

private func walkNamed(path: String, native: ContainerNode, oracle: ContainerNode, findings: inout Int) {
    let nKeys = Set(native.namedContent.keys)
    let oKeys = Set(oracle.namedContent.keys)
    let nStable = nKeys.filter { !isAuto($0) }
    let oStable = oKeys.filter { !isAuto($0) }
    let missing = oStable.subtracting(nStable).sorted()
    let extra = nStable.subtracting(oStable).sorted()
    let nAuto = nKeys.filter(isAuto).count
    let oAuto = oKeys.filter(isAuto).count

    if !missing.isEmpty { print("!! \(path): named in ORACLE, missing in NATIVE: \(missing)"); findings += 1 }
    if !extra.isEmpty { print("!! \(path): named in NATIVE, missing in ORACLE: \(extra)"); findings += 1 }
    if nAuto != oAuto { print("~  \(path): auto-named child count native=\(nAuto) oracle=\(oAuto)"); findings += 1 }
    if native.flags != oracle.flags {
        print("!! \(path): flags native=0x\(String(native.flags, radix: 16)) oracle=0x\(String(oracle.flags, radix: 16))")
        findings += 1
    }
    for key in oStable.intersection(nStable).sorted() {
        walkNamed(path: path + "." + key, native: native.namedContent[key]!, oracle: oracle.namedContent[key]!, findings: &findings)
    }
}
