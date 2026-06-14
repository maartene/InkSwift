// The compile-error taxonomy (ADR-009 / DDD-7: single-error-then-stop, located,
// construct-named). `InkCompiler.compile` yields a runnable `StoryBlueprint` or
// throws exactly one `CompileError`.

import Foundation

/// The kind of compile failure (ADR-009, DDD-7).
public enum CompileErrorKind: Equatable {
    /// An Ink construct outside the runtime's supported set (matrix rows 25-28,
    /// 36-39). The offending construct is named in `CompileError.construct`.
    case unsupportedConstruct
    /// A syntactic error in the `.ink` source.
    case syntaxError
    /// A divert / function / variable reference that does not resolve.
    case unresolvedReference
    /// Sentinel for compiler entry points whose construct support has not yet
    /// landed (later slices S3-S6). Distinct from `.unsupportedConstruct`, which
    /// names a construct outside the runtime's supported set; `.scaffold` marks a
    /// path that is in scope but not yet implemented.
    case scaffold
}

/// A single, located, construct-named compile error (ADR-009, DDD-7).
///
/// `InkCompiler.compile` yields a runnable `StoryBlueprint` OR throws exactly one
/// of these. Multi-diagnostic recovery is explicitly out of scope (Fork 4 / D2).
public struct CompileError: Error, Equatable {
    public let kind: CompileErrorKind
    /// The named construct when `kind == .unsupportedConstruct`
    /// (e.g. "LIST", "variable-text sequence", "thread", "external function");
    /// `nil` otherwise.
    public let construct: String?
    /// Human-readable message naming the construct / problem.
    public let message: String
    /// 1-based source line of the offending construct (`0` when unknown).
    public let line: Int
    /// 1-based source column of the offending construct (`0` when unknown).
    public let column: Int

    public init(
        kind: CompileErrorKind,
        construct: String? = nil,
        message: String,
        line: Int = 0,
        column: Int = 0
    ) {
        self.kind = kind
        self.construct = construct
        self.message = message
        self.line = line
        self.column = column
    }
}
