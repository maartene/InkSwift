// Example-based unit coverage for S4 function / tunnel / ref-param codegen
// (DELIVER 04-02). Each test compiles a slice `.ink` source NATIVELY through the
// InkCompiler.compile driving port, plays it, and asserts execution-equivalence
// against the committed inklecate oracle `.ink.json` for that slice — the
// project's mutation-testing-disabled correctness gate (CLAUDE.md).

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Compiler — functions, tunnels, ref params (slice oracles)")
struct Compiler_FunctionTunnelRefTests {

    private func compileAndPlay(_ name: String, script: [Int] = []) throws -> (native: [String], oracle: [String]) {
        let oracleJSON = try CompilerOracle.oracleJSON(name)
        let oracle = try CompilerOracle.play(Story(json: oracleJSON), choiceScript: script, maxLines: 100)
        let source = try CompilerOracle.source(name)
        let native = try CompilerOracle.play(
            Story(blueprint: try InkCompiler.compile(source: source)), choiceScript: script, maxLines: 100
        )
        return (native, oracle)
    }

    @Test func `inline and stored function calls play identical to the oracle`() throws {
        let result = try compileAndPlay("slice-c3-functions", script: [0])
        #expect(result.native == result.oracle)
    }

    @Test func `a single tunnel runs the sub-knot then returns to the call site`() throws {
        let result = try compileAndPlay("slice-t1-tunnels")
        #expect(result.native == result.oracle)
    }

    @Test func `nested tunnels return through each call site in order`() throws {
        let result = try compileAndPlay("slice-t2-nested-tunnels")
        #expect(result.native == result.oracle)
    }

    @Test func `a ref parameter mutation propagates to the caller variable`() throws {
        let result = try compileAndPlay("slice-t3-ref-params")
        #expect(result.native == result.oracle)
    }
}
