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

/// A segment of a content line: literal text, an inline-printed expression
/// `{ <expr> }`, an inline conditional `{ cond: a|b }`, or a tag `#tag`.
public enum ContentSegment: Equatable {
    /// Literal text rendered verbatim.
    case literal(String)
    /// An inline-printed expression, e.g. `{name}` or `{2 + 3 * 4}`.
    case expression(InkExpression)
    /// An inline conditional `{ cond: <true-text>|<false-text> }`. The branch
    /// texts are raw content rendered when the condition is truthy/falsy. A
    /// missing `|` (i.e. `{ cond: text }`) yields an empty false branch.
    case conditional(condition: InkExpression, ifTrue: String, ifFalse: String)
    /// A tag `#tag` attached to the line. The runtime surfaces it as a tag, not
    /// as output text.
    case tag(String)
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
    /// A weave choice line: `* [label] body` (bracketed, choice-only) or
    /// `* body` (plain, label echoes). `level` is the weave nesting depth
    /// (number of leading `*`/`+` markers). `isSticky` distinguishes `+`
    /// (sticky) from `*` (once-only). `choiceOnlyLabel` is the bracketed
    /// `[…]` span when present (the choice text shown but not echoed into the
    /// body); `body` is the outcome text that runs after the choice is taken.
    case choice(level: Int, isSticky: Bool, choiceOnlyLabel: String?, body: String)
    /// A weave gather line: `- outcome` (or `- - outcome` at deeper levels).
    /// `level` is the gather depth (number of leading `-` markers). `label`
    /// is the optional `(name)` gather label. `outcome` is the gather's text.
    case gather(level: Int, label: String?, outcome: String)
    /// A multi-line block / switch conditional:
    ///   block:  `{ cond: ... - else: ... }`
    ///   switch: `{ value: - 1: ... - 2: ... - else: ... }`
    /// `subject` is the leading expression — for a block it is the boolean
    /// condition itself; for a switch it is the value compared against each
    /// case label with `==`. `branches` are the ordered arms; an arm whose
    /// `match` is `nil` is the `else` (default) arm. `isSwitch` records whether
    /// the subject is compared against each branch's `match` (switch) or whether
    /// the subject IS the guard and branches carry their own guards (block).
    case conditionalBlock(subject: InkExpression, isSwitch: Bool, branches: [ConditionalBranch])
}

/// One arm of a block/switch conditional. `match` is the case guard: for a
/// switch it is the value the subject is compared against (`- 1: ...`); for a
/// block-with-guards it is the arm's own boolean condition; `nil` marks the
/// `else` arm. `body` is the arm's content, parsed as ordinary statements.
public struct ConditionalBranch: Equatable {
    public let match: InkExpression?
    public let body: [InkStatement]

    public init(match: InkExpression?, body: [InkStatement]) {
        self.match = match
        self.body = body
    }
}

/// A typed arithmetic expression node (DDD-5). Produced by the Pratt
/// sub-parser and lowered to postfix runtime nodes by the codegen.
public indirect enum InkExpression: Equatable {
    /// An integer literal operand, e.g. `4`.
    case intLiteral(Int)
    /// A boolean literal operand, `true` / `false`. Used for the implicit
    /// true-guard of a `{ cond: ... }` block with no explicit arms.
    case boolLiteral(Bool)
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
