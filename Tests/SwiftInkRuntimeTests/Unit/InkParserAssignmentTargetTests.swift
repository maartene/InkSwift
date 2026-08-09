// Unit-level pins for how a `~` logic line is classified as an ASSIGNMENT vs an
// expression statement, and for what happens when the assignment target is not a
// legal identifier.
//
// Defect this pins (fixed 2026-08-09): `logicKind` decided "is this an
// assignment?" with `trimmedBody.contains("=")`, and `splitAssignment` then split
// at the FIRST `=`. Both are wrong when the line contains a comparison:
//
//   ~ x *= 3       → target "x *"  — silently declared, real `x` untouched
//   ~ x >= 5       → target "x >"  — ditto
//   ~ temp t >= 1  → target "t >"  — ditto
//   ~ f(x >= y)    → misread as an assignment; threw unexpectedToken(")")
//                    even though inklecate compiles and runs it
//
// All six silent cases are rejected by inklecate 1.2.1, so throwing is the
// oracle-aligned outcome; `~ f(x >= y)` must instead run.

import Testing
@testable import SwiftInkRuntime

@Suite("InkParser — assignment target validation")
struct InkParserAssignmentTargetTests {

    private func parse(_ line: String) throws -> [InkStatement] {
        try InkParser.parse(line + "\n")
    }

    // A1 — the unsupported compound operators are rejected with a located syntax
    // error naming the operator, instead of silently assigning to a bogus target.
    @Test(arguments: ["*", "/", "%"])
    func `an unsupported compound assignment operator is a located syntax error`(oper: String) throws {
        let error = #expect(throws: CompileError.self) {
            _ = try parse("~ x \(oper)= 3")
        }
        #expect(error?.kind == .syntaxError)
        #expect(error?.line == 1)
        #expect(error?.message.contains("\(oper)=") == true)
    }

    // A2 — `+=` / `-=` remain supported (PR #11): they are real Ink syntax and
    // must still desugar rather than hit the new rejection path.
    @Test(arguments: ["+", "-"])
    func `a supported compound assignment operator still parses`(oper: String) throws {
        let statements = try parse("~ x \(oper)= 3")
        guard case .assignment(let name, _) = statements.first?.kind else {
            Issue.record("expected an assignment, got \(String(describing: statements.first?.kind))")
            return
        }
        #expect(name == "x")
    }

    // A3 — a bare comparison is NOT an assignment. `>=`/`!=`/`==`/`<=` all carry
    // an `=` that must not be mistaken for the assignment operator.
    @Test(arguments: [">=", "<=", "!=", "=="])
    func `a bare comparison is an expression statement, not an assignment`(oper: String) throws {
        guard case .functionCallStatement = try parse("~ x \(oper) 5").first?.kind else {
            Issue.record("expected an expression statement for '~ x \(oper) 5'")
            return
        }
    }

    // A4 — a function call whose ARGUMENT contains a comparison is legal Ink
    // (verified: inklecate compiles and runs `~ f(x >= y)`). It must classify as
    // an expression statement, not as an assignment to "f(x >".
    @Test func `a function call with a comparison argument is an expression statement`() throws {
        guard case .functionCallStatement = try parse("~ f(x >= y)").first?.kind else {
            Issue.record("expected an expression statement")
            return
        }
    }

    // A5 — a genuine assignment whose RIGHT-hand side contains a comparison still
    // splits at the assignment `=`, not at the comparison's.
    @Test func `an assignment with a comparison on the right-hand side still parses`() throws {
        guard case .assignment(let name, let value) = try parse("~ x = y >= 1").first?.kind else {
            Issue.record("expected an assignment")
            return
        }
        #expect(name == "x")
        #expect(value == .binary(op: ">=", left: .variableReference("y"), right: .intLiteral(1)))
    }

    // A6 — a `temp` declaration with no assignment `=` is a located syntax error
    // (inklecate: "Expected '='"), not a temp named "t >".
    @Test func `a temp declaration without an assignment operator is a syntax error`() throws {
        let error = #expect(throws: CompileError.self) {
            _ = try parse("~ temp t >= 1")
        }
        #expect(error?.kind == .syntaxError)
    }

    // A7 — an assignment target that is not a legal identifier is rejected rather
    // than silently declared.
    @Test func `a non-identifier assignment target is a located syntax error`() throws {
        let error = #expect(throws: CompileError.self) {
            _ = try parse("~ f(a) = 5")
        }
        #expect(error?.kind == .syntaxError)
    }

    // A8 — an `=` inside a string literal is not an assignment operator.
    @Test func `an equals inside a string literal is not an assignment`() throws {
        guard case .functionCallStatement = try parse("~ f(\"a=b\")").first?.kind else {
            Issue.record("expected an expression statement")
            return
        }
    }
}
