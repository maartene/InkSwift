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

    /// inklecate writes a function call as `{"f()": name}` and the native compiler
    /// builds the node directly (ADR-006): both trees must carry the same typed
    /// function-call targets, never a plain divert.
    @Test func `natively compiled function calls carry the decoded inklecate function-call targets`() throws {
        let fixture = "slice-c3-functions"
        let decoded = try InkDecoder().decode(Data(try CompilerOracle.oracleJSON(fixture).utf8))
        let native = try InkCompiler.compile(source: try CompilerOracle.source(fixture)).root

        let expected = Set(Self.functionCallTargets(in: decoded))
        #expect(expected == [.absolute(ContainerPath(components: [.name("double")])),
                             .absolute(ContainerPath(components: [.name("setSideEffect")]))])
        #expect(Set(Self.functionCallTargets(in: native)) == expected)
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

    /// Every function-call target in the tree, children and named content alike.
    private static func functionCallTargets(in container: ContainerNode) -> [PathReference] {
        var targets: [PathReference] = []
        for child in container.children {
            if case .functionCall(let target) = child { targets.append(target) }
            if case .container(let nested) = child { targets += functionCallTargets(in: nested) }
        }
        for nested in container.namedContent.values {
            targets += functionCallTargets(in: nested)
        }
        return targets
    }
}
