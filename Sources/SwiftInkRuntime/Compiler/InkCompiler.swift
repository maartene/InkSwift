// SCAFFOLD: true — RED scaffold created by DISTILL (native-ink-compiler).
//
// The driving port for the native Ink compiler (DDD-10). The real pipeline
// (CommentEliminator -> StringParser/combinators -> InkParser -> AST ->
// WeaveResolver -> RuntimeObjectEmitter -> ContainerNode) lands in DELIVER
// (slices S0-S6). Every entry point here throws `CompileErrorKind.scaffold`
// so the acceptance suite fails RED (missing functionality), never BROKEN.

import Foundation

/// Native, in-process Ink compiler.
///
/// Reads `.ink` source and produces a `StoryBlueprint` the existing `Story`
/// runtime plays directly — no JSON round-trip (D3), no external inklecate
/// binary (KPI #4). The accepted set equals the runtime's supported set
/// (D1, matrix rows 1-35); unsupported constructs are rejected with a located,
/// construct-named `CompileError` (D2 / ADR-009), never compiled to silent
/// wrong output.
public enum InkCompiler {

    private static let notImplemented = CompileError(
        kind: .scaffold,
        message: "InkCompiler is not yet implemented — RED scaffold (DISTILL)."
    )

    /// Primary driving port: compile `.ink` source text into a runnable story.
    /// - Throws: `CompileError` (located, construct-named) on unsupported
    ///   construct, syntax error, or unresolved reference.
    public static func compile(source: String) throws -> StoryBlueprint {
        let sanitized = CommentEliminator.strip(source)
        let lines = StringParser.parseLines(sanitized)
        let root = RuntimeObjectEmitter.emitRoot(lines: lines)
        return StoryBlueprint(root: root)
    }

    /// Driving port (file overload): read and compile a `.ink` file in-process.
    public static func compile(fileURL: URL) throws -> StoryBlueprint {
        throw notImplemented
    }

    /// Secondary sink (D4): emit the Ink-JSON representation for Level-2
    /// structural-oracle comparison, caching, and interop. Lower priority.
    public static func emitJSON(source: String) throws -> String {
        throw notImplemented
    }
}

/// Convenience driving-port surface on the runtime facade (DISTILL decision
/// DWD-1; DESIGN deferred Q#4). Lets a caller go straight from `.ink` source to
/// a playable `Story`. Declared in the `Compiler/` layer (not `Facade/`) so the
/// facade does not depend on the compiler (boundary rule R5) — this extension is
/// the single sanctioned compile entry point on `Story`.
public extension Story {
    /// Compile `.ink` source and wrap the result in a playable `Story`.
    convenience init(inkSource: String) throws {
        self.init(blueprint: try InkCompiler.compile(source: inkSource))
    }
}
