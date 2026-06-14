// Typed AST for the native Ink compiler (DDD-5). The InkParser produces a flat
// stream of `InkStatement`s, each carrying its source position so downstream
// codegen can report located errors. Divert targets are captured as raw,
// UNRESOLVED path strings: absolute (`intro`), qualified (`knot.stitch`), and
// relative (`.^.stitch`) forms are resolved by the runtime at play time.

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

/// A segment of a content line: either literal text or an inline-printed
/// expression `{ <expr> }` whose evaluated value is rendered in place.
public enum ContentSegment: Equatable {
    /// Literal text rendered verbatim.
    case literal(String)
    /// An inline-printed expression, e.g. `{name}` or `{2 + 3 * 4}`.
    case expression(InkExpression)
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
    /// A plain text line (no interpolation).
    case text(String)
    /// A content line mixing literal text and inline-printed expressions.
    case content([ContentSegment])
    /// A global `VAR name = expr` declaration. Lowered into the `global decl`
    /// container and run at story start to initialise global state.
    case globalVariable(name: String, value: InkExpression)
    /// A `CONST NAME = value` declaration. Compile-time only — inlined into
    /// expressions at codegen (D6 / DDD-9); never a runtime variable.
    case constant(name: String, value: InkExpression)
    /// A `~ temp name = expr` local declaration.
    case temporaryVariable(name: String, value: InkExpression)
    /// A `~ name = expr` reassignment of an existing variable.
    case assignment(name: String, value: InkExpression)
}

/// A typed arithmetic expression node (DDD-5). Produced by the Pratt
/// sub-parser and lowered to postfix runtime nodes by the codegen.
public indirect enum InkExpression: Equatable {
    /// An integer literal operand, e.g. `4`.
    case intLiteral(Int)
    /// A floating-point literal operand, e.g. `1.5`.
    case floatLiteral(Double)
    /// A string literal operand, e.g. `"Ada"`.
    case stringLiteral(String)
    /// A variable reference operand (resolved at codegen to `.variableReference`
    /// unless the name is a CONST, in which case its literal is inlined — D6).
    case variableReference(String)
    /// A binary operation `left OP right`, e.g. `3 * 4`. The operator is held
    /// as its runtime native-function symbol (`+ - * / %`).
    case binary(op: String, left: InkExpression, right: InkExpression)
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
