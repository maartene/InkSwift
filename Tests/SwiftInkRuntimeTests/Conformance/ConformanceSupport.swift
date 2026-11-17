// Harness for the upstream ink conformance suite (`Upstream*Tests.swift`, generated
// by scripts/conformance/import_upstream_tests.py from inkle/ink's tests/Tests.cs).
//
// `Conformance` stands in for upstream's test helpers, so a translated C# body
// reads almost line for line:
//
//   CompileString(str, testingErrors:)  →  c.compile(n, testingErrors:)
//   HadError("…") / HadWarning("…")      →  c.hadError("…") / c.hadWarning("…")
//   _errorMessages / _warningMessages    →  c.errorMessages / c.warningMessages
//   Assert.AreEqual(a, b)                →  c.equal(a, b)
//
// As upstream's `OnError`, any compile or runtime error or warning fails the test
// unless that compile passed `testingErrors: true`.
//
// Two modes, mirroring upstream's `Normal` and `JsonRoundTrip` fixtures:
// - `.native`: the story source is compiled by InkSwift's compiler. It reports
//   only the first error and no warnings.
// - `.runtime`: the story is inklecate's committed `.ink.json`, so the compile
//   diagnostics are inklecate's (`.diagnostics.txt`) and only the runtime is ours.
//
// Every body runs on its own thread under a time limit: a hang fails its test
// instead of stalling the whole suite (and the pre-commit gate).
//
// Backlog: a known gap is `.disabled(if: Conformance.skipsBacklog, "conformance: …")`.
// Set INKSWIFT_CONFORMANCE_BACKLOG=1 to run those too and see which now pass.

import Testing
import Foundation
@testable import SwiftInkRuntime

enum ConformanceMode: String, Sendable {
    case native
    case runtime
}

/// Messages collected from compiles and stories. Out-of-range reads return an
/// empty string, so a missing message fails an assertion instead of trapping.
struct ConformanceMessages {
    let all: [String]

    var count: Int { all.count }

    subscript(safe index: Int) -> String {
        all.indices.contains(index) ? all[index] : ""
    }
}

extension Array where Element == String {
    subscript(safe index: Int) -> String {
        indices.contains(index) ? self[index] : ""
    }
}

extension Story {
    /// Upstream's `ChoosePathString("knot.stitch")`.
    func choosePath(_ path: String) throws {
        let parts = path.split(separator: ".", maxSplits: 1).map(String.init)
        try moveToKnot(parts[0], stitch: parts.count > 1 ? parts[1] : nil)
    }
}

final class Conformance: @unchecked Sendable {

    /// False when INKSWIFT_CONFORMANCE_BACKLOG=1: the backlog runs as well.
    static let skipsBacklog = ProcessInfo.processInfo.environment["INKSWIFT_CONFORMANCE_BACKLOG"] != "1"

    private struct Failure {
        let message: String
        let location: SourceLocation
    }

    private struct CompileFailure: Error {
        let message: String
    }

    let test: String
    let mode: ConformanceMode

    private let lock = NSLock()
    private var failures: [Failure] = []
    private var compileErrors: [String] = []
    private var compileWarnings: [String] = []
    private var compileAuthorMessages: [String] = []
    private var stories: [(story: Story, testingErrors: Bool)] = []
    /// The last `hadError`/`hadWarning` query, so a failed `isTrue` around it
    /// can say what was reported instead.
    private var lastQuery: String?

    private init(test: String, mode: ConformanceMode) {
        self.test = test
        self.mode = mode
    }

    // MARK: Running a test

    /// Run one upstream test body in `mode`, recording its failures as issues.
    static func run(
        _ test: String,
        _ mode: ConformanceMode,
        timeLimit: TimeInterval = 5,
        _ body: @escaping @Sendable (Conformance) throws -> Void
    ) {
        let conformance = Conformance(test: test, mode: mode)
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            do {
                try body(conformance)
                conformance.checkStoriesHadNoUnexpectedErrors()
            } catch let failure as CompileFailure {
                conformance.fail(failure.message)
            } catch {
                conformance.fail("threw \(error)")
            }
            finished.signal()
        }
        thread.stackSize = 16 << 20
        thread.start()
        if finished.wait(timeout: .now() + timeLimit) == .timedOut {
            conformance.fail("timed out after \(Int(timeLimit))s (hang)")
        }
        for failure in conformance.recordedFailures() {
            Issue.record(Comment(rawValue: "\(test) [\(mode.rawValue)]: \(failure.message)"),
                         sourceLocation: failure.location)
        }
    }

    // MARK: Compiling (upstream's CompileString / CompileStringWithoutRuntime)

    /// The test's story number `index`, compiled for `mode`. With
    /// `testingErrors: false` a compile error fails the test, as upstream.
    @discardableResult
    func compile(_ index: Int, testingErrors: Bool = false, countAllVisits: Bool = false) throws -> Story {
        resetCompileMessages()
        let name = "upstream-\(test)-\(index)"
        let story: Story?
        switch mode {
        case .native:
            story = compileNatively(name)
        case .runtime:
            story = try loadInklecateJSON(name)
        }
        try checkCompile(name, testingErrors: testingErrors)
        guard let story else {
            return try Self.placeholderStory()
        }
        locked { stories.append((story, testingErrors)) }
        return story
    }

    /// Compile `source` (built by the test itself, e.g. from a character range)
    /// with InkSwift's compiler. Native mode only: there is no inklecate JSON.
    @discardableResult
    func compile(source: String, testingErrors: Bool = false) throws -> Story {
        precondition(mode == .native, "compile(source:) has no inklecate JSON for runtime mode")
        resetCompileMessages()
        var story: Story?
        do {
            story = Story(blueprint: try InkCompiler.compile(source: source))
        } catch let error as CompileError {
            locked { compileErrors.append(error.message) }
        } catch {
            locked { compileErrors.append(String(describing: error)) }
        }
        try checkCompile("generated source", testingErrors: testingErrors)
        guard let story else {
            return try Self.placeholderStory()
        }
        locked { stories.append((story, testingErrors)) }
        return story
    }

    /// Upstream's `CompileStringWithoutRuntime`: only the diagnostics matter.
    func compileWithoutRuntime(_ index: Int, testingErrors: Bool = false) throws {
        _ = try compile(index, testingErrors: testingErrors)
    }

    private func compileNatively(_ name: String) -> Story? {
        do {
            let source = try String(contentsOf: try fixture(name, "ink"), encoding: .utf8)
            return Story(blueprint: try InkCompiler.compile(source: source))
        } catch let error as CompileError {
            locked { compileErrors.append(error.message) }
        } catch {
            locked { compileErrors.append(String(describing: error)) }
        }
        return nil
    }

    private func loadInklecateJSON(_ name: String) throws -> Story? {
        if let diagnostics = Bundle.module.url(forResource: name, withExtension: "diagnostics.txt") {
            for line in try String(contentsOf: diagnostics, encoding: .utf8).split(separator: "\n") {
                record(diagnostic: String(line))
            }
        }
        guard let json = Bundle.module.url(forResource: name, withExtension: "ink.json") else {
            return nil
        }
        do {
            return try Story(json: try String(contentsOf: json, encoding: .utf8))
        } catch {
            throw CompileFailure(message: "runtime could not load inklecate's JSON: \(error)")
        }
    }

    private func record(diagnostic line: String) {
        let message = line.replacingOccurrences(
            of: #"^[A-Z ]+: '[^']*' "#, with: "", options: .regularExpression)
        locked {
            if line.hasPrefix("ERROR") {
                compileErrors.append(message)
            } else if line.hasPrefix("WARNING") {
                compileWarnings.append(message)
            } else {
                compileAuthorMessages.append(message)
            }
        }
    }

    private func checkCompile(_ name: String, testingErrors: Bool) throws {
        let (errors, warnings) = locked { (compileErrors, compileWarnings) }
        guard testingErrors == false, errors.isEmpty == false || warnings.isEmpty == false else {
            return
        }
        throw CompileFailure(message: "\(name) did not compile cleanly: \((errors + warnings).joined(separator: " | "))")
    }

    private func resetCompileMessages() {
        locked {
            compileErrors = []
            compileWarnings = []
            compileAuthorMessages = []
        }
    }

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw CompileFailure(message: "missing fixture \(name).\(ext)")
        }
        return url
    }

    /// Returned where upstream's `CompileString` returns null (a failed compile
    /// under `testingErrors`); such tests only inspect the error messages.
    private static func placeholderStory() throws -> Story {
        Story(blueprint: try InkCompiler.compile(source: "-> END"))
    }

    // MARK: Diagnostics (upstream's HadError / HadWarning / _errorMessages)

    var errorMessages: ConformanceMessages {
        ConformanceMessages(all: locked { compileErrors + stories.flatMap(\.story.currentErrors) })
    }

    var warningMessages: ConformanceMessages {
        ConformanceMessages(all: locked { compileWarnings })
    }

    var authorMessages: ConformanceMessages {
        ConformanceMessages(all: locked { compileAuthorMessages })
    }

    func hadError(_ match: String? = nil) -> Bool {
        let errors = errorMessages.all
        locked { lastQuery = "hadError(\((match ?? "any").debugDescription)); errors were \(errors)" }
        return Self.contains(errors, match)
    }

    func hadWarning(_ match: String? = nil) -> Bool {
        let warnings = warningMessages.all
        locked { lastQuery = "hadWarning(\((match ?? "any").debugDescription)); warnings were \(warnings)" }
        return Self.contains(warnings, match)
    }

    private static func contains(_ messages: [String], _ match: String?) -> Bool {
        guard let match else {
            return messages.isEmpty == false
        }
        return messages.contains { $0.contains(match) }
    }

    /// Upstream's `OnError` fails the test on any runtime error unless the
    /// story was compiled with `testingErrors: true`.
    private func checkStoriesHadNoUnexpectedErrors() {
        for (story, testingErrors) in locked({ stories }) where testingErrors == false {
            for error in story.currentErrors {
                fail("runtime error: \(error)")
            }
        }
    }

    // MARK: Choices

    /// `story.currentChoices[index]`, or nil (failing the test) when the story
    /// offers fewer choices.
    func choice(_ story: Story, _ index: Int, location: SourceLocation = #_sourceLocation) -> Choice? {
        let choices = story.currentChoices
        guard choices.indices.contains(index) else {
            fail("expected a choice at index \(index), story offers \(choices.count)", location: location)
            return nil
        }
        return choices[index]
    }

    // MARK: Assertions (upstream's Assert.*)

    func equal<T: Equatable>(_ expected: T, _ actual: T, location: SourceLocation = #_sourceLocation) {
        if expected != actual {
            fail("expected \(Self.show(expected)), got \(Self.show(actual))", location: location)
        }
    }

    /// Equality against an untyped value (a variable read), compared as text.
    func equal(_ expected: Any, _ actual: Any?, location: SourceLocation = #_sourceLocation) {
        let actualText = actual.map { "\($0)" } ?? "nil"
        if "\(expected)" != actualText {
            fail("expected \(expected), got \(actualText)", location: location)
        }
    }

    func notEqual<T: Equatable>(_ unexpected: T, _ actual: T, location: SourceLocation = #_sourceLocation) {
        if unexpected == actual {
            fail("expected anything but \(Self.show(unexpected))", location: location)
        }
    }

    /// A nil condition (a choice that is not there) counts as false.
    func isTrue(_ condition: Bool?, location: SourceLocation = #_sourceLocation) {
        if condition != true {
            fail("expected true" + queryContext(), location: location)
        }
    }

    func isFalse(_ condition: Bool?, location: SourceLocation = #_sourceLocation) {
        if condition != false {
            fail("expected false" + queryContext(), location: location)
        }
    }

    func isNil(_ value: Any?, location: SourceLocation = #_sourceLocation) {
        if value != nil {
            fail("expected nil", location: location)
        }
    }

    func isNotNil(_ value: Any?, location: SourceLocation = #_sourceLocation) {
        if value == nil {
            fail("expected a value", location: location)
        }
    }

    func fail(_ message: String, location: SourceLocation = #_sourceLocation) {
        locked { failures.append(Failure(message: message, location: location)) }
    }

    // MARK: Helpers

    private func queryContext() -> String {
        locked {
            defer { lastQuery = nil }
            return lastQuery.map { " from \($0)" } ?? ""
        }
    }

    private func recordedFailures() -> [Failure] {
        locked { failures }
    }

    private func locked<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }

    private static func show(_ value: Any) -> String {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            return mirror.children.first.map { show($0.value) } ?? "nil"
        }
        if let text = value as? String {
            return text.debugDescription
        }
        return String(describing: value)
    }
}

/// The non-ASCII identifier character ranges inklecate accepts
/// (`InkParser_CharacterRanges.cs`, `ListAllCharacterRanges`), each with its
/// excluded characters; upstream's character-range tests use every
/// character of a range as one identifier.
enum UpstreamCharacterRanges {
    struct Range {
        let name: String
        let first: UInt32
        let last: UInt32
        let excludes: [ClosedRange<UInt32>]

        /// Every character of the range, minus its excludes, as one string.
        var identifier: String {
            var text = ""
            for scalar in first...last where excludes.allSatisfy({ $0.contains(scalar) == false }) {
                if let character = Unicode.Scalar(scalar) {
                    text.unicodeScalars.append(character)
                }
            }
            return text
        }
    }

    static let all: [Range] = [
        Range(name: "LatinBasic", first: 0x0041, last: 0x007A, excludes: [0x005B...0x0060]),
        Range(name: "LatinExtendedA", first: 0x0100, last: 0x017F, excludes: []),
        Range(name: "LatinExtendedB", first: 0x0180, last: 0x024F, excludes: []),
        Range(name: "Arabic", first: 0x0600, last: 0x06FF, excludes: []),
        Range(name: "Armenian", first: 0x0530, last: 0x058F,
              excludes: [0x0530...0x0530, 0x0557...0x0560, 0x0588...0x058E]),
        Range(name: "Cyrillic", first: 0x0400, last: 0x04FF, excludes: [0x0482...0x0489]),
        Range(name: "Greek", first: 0x0370, last: 0x03FF,
              excludes: [0x0378...0x0385, 0x0374...0x0375, 0x0387...0x0387, 0x038B...0x038B,
                         0x038D...0x038D, 0x03A2...0x03A2]),
        Range(name: "Hebrew", first: 0x0590, last: 0x05FF, excludes: []),
        Range(name: "Korean", first: 0xAC00, last: 0xD7AF, excludes: []),
        Range(name: "Latin1Supplement", first: 0x0080, last: 0x00FF, excludes: []),
        Range(name: "CJKUnifiedIdeographs", first: 0x4E00, last: 0x9FFF, excludes: []),
        Range(name: "Hiragana", first: 0x3041, last: 0x3096, excludes: []),
        Range(name: "Katakana", first: 0x30A0, last: 0x30FC, excludes: []),
    ]
}
