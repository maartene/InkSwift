import Testing
@testable import SwiftInkRuntime

@Suite("InkParser — statement rules to AST")
struct InkParserTests {

    @Test func `parses a knot header and captures its name and position`() throws {
        let statements = try InkParser.parse("=== intro ===")
        #expect(statements.count == 1)
        #expect(statements[0].position.line == 1)
        guard case let .knot(name) = statements[0].kind else {
            Issue.record("expected a knot, got \(statements[0].kind)")
            return
        }
        #expect(name == "intro")
    }

    @Test func `parses a stitch header and captures its name`() throws {
        let statements = try InkParser.parse("= arrival")
        guard case let .stitch(name) = statements[0].kind else {
            Issue.record("expected a stitch, got \(statements[0].kind)")
            return
        }
        #expect(name == "arrival")
    }

    @Test func `parses an absolute divert and captures the unresolved target`() throws {
        let statements = try InkParser.parse("-> intro")
        guard case let .divert(target) = statements[0].kind else {
            Issue.record("expected a divert, got \(statements[0].kind)")
            return
        }
        #expect(target == "intro")
    }

    @Test func `parses a qualified divert as an unresolved path string`() throws {
        let statements = try InkParser.parse("-> investigation.arrival")
        guard case let .divert(target) = statements[0].kind else {
            Issue.record("expected a divert, got \(statements[0].kind)")
            return
        }
        #expect(target == "investigation.arrival")
    }

    @Test func `parses a relative divert as an unresolved path string`() throws {
        let statements = try InkParser.parse("-> .^.arrival")
        guard case let .divert(target) = statements[0].kind else {
            Issue.record("expected a divert, got \(statements[0].kind)")
            return
        }
        #expect(target == ".^.arrival")
    }

    @Test func `parses an end divert as a distinct terminal kind`() throws {
        let statements = try InkParser.parse("-> END")
        guard case .end = statements[0].kind else {
            Issue.record("expected end, got \(statements[0].kind)")
            return
        }
    }

    @Test func `parses a plain text line and a trailing glue marker`() throws {
        let statements = try InkParser.parse("You step inside. <>")
        #expect(statements.count == 2)
        guard case let .text(content) = statements[0].kind else {
            Issue.record("expected text, got \(statements[0].kind)")
            return
        }
        #expect(content == "You step inside.")
        guard case .glue = statements[1].kind else {
            Issue.record("expected glue, got \(statements[1].kind)")
            return
        }
    }

    @Test func `parses the linear-flow fixture into a structurally correct AST without scaffold`() throws {
        let source = """
        -> intro

        === intro ===
        The rain fell hard on the city.
        -> investigation.arrival

        === investigation ===
        = arrival
        You step inside. <>
        The room is cold and silent.
        -> conclusion

        === conclusion ===
        It was over before it began.
        -> END
        """
        let statements = try InkParser.parse(source)

        let knotNames: [String] = statements.compactMap {
            if case let .knot(name) = $0.kind { return name }
            return nil
        }
        #expect(knotNames == ["intro", "investigation", "conclusion"])

        let stitchNames: [String] = statements.compactMap {
            if case let .stitch(name) = $0.kind { return name }
            return nil
        }
        #expect(stitchNames == ["arrival"])

        let divertTargets: [String] = statements.compactMap {
            if case let .divert(target) = $0.kind { return target }
            return nil
        }
        #expect(divertTargets == ["intro", "investigation.arrival", "conclusion"])

        let hasGlue = statements.contains { if case .glue = $0.kind { return true }; return false }
        #expect(hasGlue)

        let hasEnd = statements.contains { if case .end = $0.kind { return true }; return false }
        #expect(hasEnd)

        // Every statement carries a real (1-based) source line.
        #expect(statements.allSatisfy { $0.position.line >= 1 })
    }
}
