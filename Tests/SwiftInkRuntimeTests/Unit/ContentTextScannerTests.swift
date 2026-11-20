import Testing
@testable import SwiftInkRuntime

/// ContentTextScanner (ADR-026): one content-text rule with a stop set per
/// context, mirroring inklecate's `ContentTextAllowingEcapeChar` /
/// `ContentTextNoEscape` (`InkParser_Content.cs`).
struct ContentTextScannerTests {

    typealias Scanner = ContentTextScanner
    typealias Marker = ContentTextScanner.Marker

    /// One token as (marker, text, offset); `nil` marker is a literal run.
    struct Expected: Equatable, CustomStringConvertible {
        let marker: Marker?
        let text: String
        let offset: Int

        static func run(_ text: String, _ offset: Int) -> Expected {
            Expected(marker: nil, text: text, offset: offset)
        }

        static func marker(_ marker: Marker, _ text: String, _ offset: Int) -> Expected {
            Expected(marker: marker, text: text, offset: offset)
        }

        var description: String { "\(marker.map { "\($0)" } ?? "run")(\(text.debugDescription)@\(offset))" }
    }

    private func scanned(_ text: String, _ context: Scanner.Context, mode: Scanner.Mode = .escapeAgnostic) -> [Expected] {
        Scanner.scan(text, context: context, mode: mode).map {
            Expected(marker: $0.marker, text: $0.text, offset: $0.offset)
        }
    }

    // MARK: - Stop set per context

    /// Every context stops at the content set `{ } | #` and a newline.
    @Test(arguments: [Scanner.Context.content, .choice, .string, .tag])
    func `every context stops at braces, bar, hash and newline`(context: Scanner.Context) {
        #expect(scanned("a{b}c|d#e\nf", context) == [
            .run("a", 0), .marker(.braceOpen, "{", 1), .run("b", 2), .marker(.braceClose, "}", 3),
            .run("c", 4), .marker(.bar, "|", 5), .run("d", 6), .marker(.hash, "#", 7),
            .run("e", 8), .marker(.newline, "\n", 9), .run("f", 10),
        ])
    }

    /// Square brackets stop only in choice text; elsewhere they are literal text.
    @Test(arguments: [
        (Scanner.Context.choice, true),
        (Scanner.Context.content, false),
        (Scanner.Context.string, false),
        (Scanner.Context.tag, false),
    ])
    func `square brackets are markers only in choice text`(context: Scanner.Context, stops: Bool) {
        let expected: [Expected] = stops
            ? [.run("a", 0), .marker(.bracketOpen, "[", 1), .run("b", 2), .marker(.bracketClose, "]", 3), .run("c", 4)]
            : [.run("a[b]c", 0)]
        #expect(scanned("a[b]c", context) == expected)
    }

    /// A double quote stops only in a string expression.
    @Test(arguments: [
        (Scanner.Context.string, true),
        (Scanner.Context.content, false),
        (Scanner.Context.choice, false),
        (Scanner.Context.tag, false),
    ])
    func `a double quote is a marker only in string text`(context: Scanner.Context, stops: Bool) {
        let expected: [Expected] = stops
            ? [.run("say ", 0), .marker(.quote, "\"", 4), .run("hi", 5)]
            : [.run("say \"hi", 0)]
        #expect(scanned("say \"hi", context) == expected)
    }

    // MARK: - Glue and divert markers

    @Test(arguments: [Scanner.Context.content, .choice, .string, .tag])
    func `glue and the divert arrow come out as markers with their offsets`(context: Scanner.Context) {
        #expect(scanned("<>a -> b<>", context) == [
            .marker(.glue, "<>", 0), .run("a ", 2), .marker(.divert, "->", 4), .run(" b", 6), .marker(.glue, "<>", 8),
        ])
    }

    /// A lone `<`, `-` or `>` is text: only the two-character pairs are markers.
    @Test(arguments: ["a < b", "a - b", "a > b", "<-x", "--", "<<"])
    func `a lone angle bracket or dash is literal text`(text: String) {
        #expect(scanned(text, .content) == [.run(text, 0)])
    }

    @Test func `a dash before glue does not pair with it`() {
        #expect(scanned("-<>", .content) == [.run("-", 0), .marker(.glue, "<>", 1)])
    }

    // MARK: - Offsets

    @Test func `offsets count characters of the source text`() {
        let tokens = Scanner.scan("é{x}", context: .content)
        #expect(tokens.map(\.offset) == [0, 1, 2, 3])
        #expect(tokens.map(\.length) == [1, 1, 1, 1])
    }

    @Test func `an empty text yields no tokens`() {
        #expect(scanned("", .content).isEmpty)
    }

    // MARK: - Escapes

    /// Escape-agnostic mode reproduces the compiler before #35: a backslash is
    /// ordinary text, so it neither protects the next character nor disappears.
    @Test(arguments: [Scanner.Context.content, .choice, .tag])
    func `in escape-agnostic mode a backslash is ordinary text`(context: Scanner.Context) {
        #expect(scanned("a\\{b", context) == [.run("a\\", 0), .marker(.braceOpen, "{", 2), .run("b", 3)])
    }

    /// A string literal has always skipped escape pairs when looking for its
    /// closing quote (the expression tokenizer did so before this scanner), so
    /// in escape-agnostic mode the string context keeps the pair, raw.
    @Test func `in escape-agnostic mode a string keeps escape pairs raw and an escaped quote is not a stop`() {
        #expect(scanned("a\\\"b\"c", .string) == [.run("a\\\"b", 0), .marker(.quote, "\"", 4), .run("c", 5)])
    }

    @Test(arguments: [Scanner.Context.content, .choice, .string, .tag])
    func `in escape-aware mode an escaped character is literal text without its backslash`(context: Scanner.Context) {
        #expect(scanned("a\\{b\\#c", context, mode: .escapeAware) == [.run("a{b#c", 0)])
        #expect(Scanner.scan("a\\{b", context: context, mode: .escapeAware).first?.length == 4)
    }

    @Test func `a trailing lone backslash is literal text in either mode`() {
        #expect(scanned("a\\", .content, mode: .escapeAware) == [.run("a\\", 0)])
        #expect(scanned("a\\", .content) == [.run("a\\", 0)])
    }

    @Test func `escape-aware markers keep their source offsets after an escape`() {
        #expect(scanned("\\{x}", .content, mode: .escapeAware) == [.run("{x", 0), .marker(.braceClose, "}", 3)])
    }

    // MARK: - Queries

    @Test func `text re-joins the scanned pieces`() {
        #expect(Scanner.text(of: "a\\{b} <> c -> d # e", context: .content, mode: .escapeAgnostic) == "a\\{b} <> c -> d # e")
        #expect(Scanner.text(of: "a\\{b", context: .content, mode: .escapeAware) == "a{b")
    }

    @Test func `first finds the first marker of a kind`() {
        let arrow = Scanner.first(.divert, in: "go -> there -> again", context: .content)
        #expect(arrow?.offset == 3)
        #expect(Scanner.first(.divert, in: "no arrow", context: .content) == nil)
    }

    @Test func `split cuts the text at every marker of a kind, keeping empty pieces`() {
        #expect(Scanner.split("a # b ## c", at: .hash, context: .choice) == ["a ", " b ", "", " c"])
        #expect(Scanner.split("plain", at: .hash, context: .choice) == ["plain"])
    }

    /// The detector's escape primitive is escape-aware whatever the compiler's mode.
    @Test(arguments: [
        ("a{b", true),
        ("a\\{b", false),
        ("a\\\\{b", true),
        ("a\\", false),
    ])
    func `the escape-aware scan sees only unescaped markers`(text: String, hasBrace: Bool) {
        #expect(Scanner.contains(.braceOpen, in: text, context: .content, mode: .escapeAware) == hasBrace)
    }
}
