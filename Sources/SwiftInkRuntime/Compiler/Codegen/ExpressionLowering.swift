// WHY-NEW-FILE: Sources/SwiftInkRuntime/Compiler/Codegen/ExpressionLowering.swift
//   CLOSEST-EXISTING: Sources/SwiftInkRuntime/Compiler/Codegen/RuntimeObjectEmitter.swift
//   EXTENSION-COST: expression lowering lived in RuntimeObjectEmitter (past
//     1,400 lines) next to statement and body lowering, although it depends only
//     on the expression AST and the lowering context.
//   PARALLEL-RATIONALE: ExpressionLowering turns one `InkExpression` into postfix
//     eval-stack nodes. Every statement lowerer, and the guard / subject closures
//     handed to ConditionalEmitter and WeaveEmitter, call into it; it never
//     lowers statements or touches the named-container namespace.

import Foundation

/// Lowers expressions to the runtime's postfix eval-stack nodes.
enum ExpressionLowering {

    /// The runtime intercepts a divert whose target carries this prefix as a
    /// function call (push a return address before jumping). Matches the decoder's
    /// lowering of an inklecate `{"f()": path}` divert.
    static let functionCallTargetPrefix = "f():"

    /// Reference arguments use `ci == -1` to denote global scope (brief tier3); a
    /// non-negative index would point into a call frame's temp scope.
    private static let globalContextIndex = -1

    /// Lower an inline-printed expression `{ <expr> }` into the runtime nodes
    /// that evaluate it and emit the result, matching the committed oracle
    /// token order for `{2 + 3 * 4}`: `ev, 2, 3, 4, *, +, out, /ev`. The
    /// expression body is lowered to POSTFIX (RPN) so it drives the runtime's
    /// evaluation stack directly; `out` pops the result and prints it.
    static func lowerInlineExpression(
        _ expression: InkExpression,
        context: LoweringContext
    ) -> [NodeKind] {
        evalGroup(lowerExpression(expression, context: context) + [.controlCommand("out")])
    }

    /// Wrap eval-stack nodes in the runtime's `ev` … `/ev` evaluation block. The
    /// shared shape behind inline-print, return, assignment, and discarded-call
    /// lowering: each supplies the body that runs between the markers.
    static func evalGroup(_ body: [NodeKind]) -> [NodeKind] {
        [.controlCommand("ev")] + body + [.controlCommand("/ev")]
    }

    /// Lower an expression to POSTFIX runtime nodes, inlining any CONST
    /// reference to its literal value (D6 / DDD-9). `a OP b` becomes
    /// `<lower a> <lower b> .nativeFunction(OP)`; literals push onto the eval
    /// stack; non-CONST identifiers lower to `.variableReference`; string
    /// literals lower to a `str`/`^text`/`/str` group that pushes the string; a
    /// function call lowers its arguments onto the eval stack then emits the
    /// `f():`-tagged divert that calls the function and leaves its result there.
    static func lowerExpression(
        _ expression: InkExpression,
        context: LoweringContext
    ) -> [NodeKind] {
        switch expression {
        case .intLiteral(let value):
            return [.intValue(value)]
        case .boolLiteral(let value):
            return [.boolValue(value)]
        case .floatLiteral(let value):
            return [.floatValue(value)]
        case .stringLiteral(let value):
            return [.controlCommand("str"), .text(value), .controlCommand("/str")]
        case .variableReference(let name):
            return lowerVariableReference(name, context: context)
        case .binary(let oper, let left, let right):
            return lowerExpression(left, context: context)
                + lowerExpression(right, context: context)
                + [.nativeFunction(oper)]
        case .unary(let oper, let operand):
            return lowerExpression(operand, context: context) + [.nativeFunction(oper)]
        case .functionCall(let name, let arguments):
            return lowerFunctionCall(name: name, arguments: arguments, context: context)
        }
    }

    /// Lower a name: a CONST inlines its value; a name resolving to a known weave
    /// label or knot/stitch is a read-count subject (ADR-011 EXTEND #2) and emits
    /// `.readCount(path)` addressing the resolved container; a true miss (a real
    /// qualified variable) falls through to `.variableReference`.
    private static func lowerVariableReference(_ name: String, context: LoweringContext) -> [NodeKind] {
        if let inlined = context.constants[name] {
            return lowerExpression(inlined, context: context)
        }
        if let path = context.readCountPath(for: name) {
            return [.readCount(.absolute(ContainerPath(components: path.map(PathComponent.init(parsing:)))))]
        }
        return [.variableReference(name: name)]
    }

    /// Lower a function call `f(args)`: push each argument onto the eval stack —
    /// an argument bound to a `ref` parameter becomes a `variablePointer` so the
    /// callee mutates the caller's variable — then emit the `f():`-tagged divert
    /// the runtime intercepts to push a return address and jump into the function.
    private static func lowerFunctionCall(
        name: String,
        arguments: [InkExpression],
        context: LoweringContext
    ) -> [NodeKind] {
        let parameters = context.functions[name] ?? []
        var nodes: [NodeKind] = []
        for (offset, argument) in arguments.enumerated() {
            let isReference = offset < parameters.count && parameters[offset].isReference
            if isReference, case .variableReference(let variableName) = argument {
                nodes.append(.variablePointer(name: variableName, contextIndex: globalContextIndex))
                continue
            }
            nodes.append(contentsOf: lowerExpression(argument, context: context))
        }
        nodes.append(.divert(target: .path(PathReference(parsing: functionCallTargetPrefix + name)), isConditional: false))
        return nodes
    }
}
