// Targeted example unit tests for DELIVER step 04-01 — conditional (inline /
// block / switch) and tag PARSER+CODEGEN lowering. These drive the new lowering
// onto the runtime's EXISTING isConditional-divert pathway and tag node; the S4
// ceiling acceptance test stays RED until 04-02 (functions/tunnels/ref-params).
//
// Driving port: InkCompiler.compile(source:) → StoryBlueprint → Story, played
// through the production runtime. The condition variable is set at VAR scope (the
// truthy/falsy branch selection is the unit under test) and the source is played
// directly — these are NEW focused sources whose expected output is the
// execution-equivalent of the committed slice-c1/c2 inklecate oracle structure
// (verified against slice-c1/c2.ink.json). Weave-in-knot choice setup is NOT used
// because that is unsupported S3 territory, out of this step's scope.

import Testing
import Foundation
@testable import SwiftInkRuntime

@Suite("Conditional + tag lowering — compile and play")
struct InkConditionalCompileTests {

    private func play(_ source: String) throws -> [String] {
        let story = Story(blueprint: try InkCompiler.compile(source: source))
        return try CompilerOracle.play(story)
    }

    // MARK: - Inline conditionals  {c: a|b}

    @Test func `inline conditional renders the truthy branch when the condition holds`() throws {
        let source = """
        VAR metCass = true
        -> check
        === check ===
        {metCass: You know her.|She's a stranger.}
        -> END
        """
        #expect(try play(source) == ["You know her."])
    }

    @Test func `inline conditional renders the falsy branch when the condition fails`() throws {
        let source = """
        VAR metCass = false
        -> check
        === check ===
        {metCass: You know her.|She's a stranger.}
        -> END
        """
        #expect(try play(source) == ["She's a stranger."])
    }

    @Test func `inline conditional with surrounding text and a trailing tag renders inline`() throws {
        // Mirrors the ceiling shape `{visited: Welcome back.|First time here.} #greeting`:
        // the conditional renders inline, the tag does not leak into the prose.
        let source = """
        VAR visited = false
        -> intro
        === intro ===
        {visited: Welcome back.|First time here.} #greeting
        -> END
        """
        #expect(try play(source) == ["First time here."])
    }

    // MARK: - Block conditionals  {c: ... - else: ...}

    @Test func `block conditional renders the true arm when the guard holds`() throws {
        let source = """
        VAR score = 15
        -> score_check
        === score_check ===
        { score > 10:
            You passed.
        - else:
            You failed.
        }
        -> END
        """
        #expect(try play(source) == ["You passed."])
    }

    @Test func `block conditional renders the else arm when the guard fails`() throws {
        let source = """
        VAR score = 5
        -> score_check
        === score_check ===
        { score > 10:
            You passed.
        - else:
            You failed.
        }
        -> END
        """
        #expect(try play(source) == ["You failed."])
    }

    @Test func `block conditional with no else renders nothing when the guard fails`() throws {
        let source = """
        VAR score = 1
        -> score_check
        === score_check ===
        { score > 10:
            You passed.
        }
        After.
        -> END
        """
        #expect(try play(source) == ["After."])
    }

    @Test func `subject-less guarded block renders the arm whose guard holds`() throws {
        // The ceiling shape `{ - force > 5: ... - else: ... }` — a bare `{` opener
        // whose arms each carry their own boolean guard.
        let source = """
        VAR force = 6
        -> strength
        === strength ===
        {
            - force > 5: You are strong.
            - else: You are weak.
        }
        -> END
        """
        #expect(try play(source) == ["You are strong."])
    }

    @Test func `subject-less guarded block falls to else when the guard fails`() throws {
        let source = """
        VAR force = 2
        -> strength
        === strength ===
        {
            - force > 5: You are strong.
            - else: You are weak.
        }
        -> END
        """
        #expect(try play(source) == ["You are weak."])
    }

    // MARK: - Switch conditionals  {v: - 1: ... - 2: ... - else: ...}

    @Test func `switch conditional renders the first matching case`() throws {
        let source = """
        VAR outcome = 1
        -> outcome_check
        === outcome_check ===
        { outcome:
        - 1: Arrested.
        - 2: Escaped.
        - else: Unknown.
        }
        -> END
        """
        #expect(try play(source) == ["Arrested."])
    }

    @Test func `switch conditional renders a later matching case`() throws {
        let source = """
        VAR outcome = 2
        -> outcome_check
        === outcome_check ===
        { outcome:
        - 1: Arrested.
        - 2: Escaped.
        - else: Unknown.
        }
        -> END
        """
        #expect(try play(source) == ["Escaped."])
    }

    @Test func `switch conditional renders the else case when no label matches`() throws {
        let source = """
        VAR outcome = 99
        -> outcome_check
        === outcome_check ===
        { outcome:
        - 1: Arrested.
        - 2: Escaped.
        - else: Unknown.
        }
        -> END
        """
        #expect(try play(source) == ["Unknown."])
    }

    // MARK: - Tags  #tag

    @Test func `a content line with a trailing tag compiles and surfaces the tagged text`() throws {
        let source = """
        Hello there. #greeting
        -> END
        """
        // The tag must not be echoed as literal output text — the rendered line
        // is the prose only; the runtime surfaces "#greeting" as a tag, not output.
        #expect(try play(source) == ["Hello there."])
    }

    @Test func `a standalone tag line compiles without throwing and does not corrupt prose`() throws {
        let source = """
        # globaltag
        First line.
        -> END
        """
        #expect(try play(source) == ["First line."])
    }
}
