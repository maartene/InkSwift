// Typed AST for the native Ink compiler (DDD-5). The InkParser produces a flat
// stream of `InkStatement`s, each carrying its source position so downstream
// codegen (01-02) can report located errors. Path RESOLUTION is deferred to
// 01-02: qualified (`knot.stitch`) and relative (`.^.stitch`) divert targets are
// captured here as raw, UNRESOLVED path strings.

import Foundation

/// A 1-based source position (line, column). Value object — wraps the two
/// position primitives so AST nodes never carry bare ints.
public struct SourcePosition: Equatable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

/// The kind of a parsed Ink statement. Each construct the S1 core flow needs is
/// a distinct case; diverts store their target as a raw unresolved path string.
public enum InkStatementKind: Equatable {
    /// A knot header: `=== name ===`.
    case knot(String)
    /// A stitch header: `= name`.
    case stitch(String)
    /// A divert to a (still unresolved) target path: `-> intro`,
    /// `-> investigation.arrival`, `-> .^.arrival`.
    case divert(String)
    /// The terminal divert `-> END`.
    case end
    /// A glue marker `<>` joining adjacent output.
    case glue
    /// A plain text line.
    case text(String)
}

/// One parsed statement plus where it came from.
public struct InkStatement: Equatable {
    public let kind: InkStatementKind
    public let position: SourcePosition

    public init(kind: InkStatementKind, position: SourcePosition) {
        self.kind = kind
        self.position = position
    }
}
