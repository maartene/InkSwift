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
    ) throws -> [NodeKind] {
        evalGroup(try lowerExpression(expression, context: context) + [.controlCommand("out")])
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
    /// built-in's `.nativeFunction` or the story function's `.functionCall`, either
    /// of which leaves the result there (see `lowerFunctionCall`).
    static func lowerExpression(
        _ expression: InkExpression,
        context: LoweringContext
    ) throws -> [NodeKind] {
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
            return try lowerVariableReference(name, context: context)
        case .binary(let oper, let left, let right):
            return try lowerExpression(left, context: context)
                + lowerExpression(right, context: context)
                + [.nativeFunction(try nativeOperator(oper))]
        case .unary(let oper, let operand):
            return try lowerExpression(operand, context: context) + [.nativeFunction(try nativeOperator(oper))]
        case .functionCall(let name, let arguments):
            return try lowerFunctionCall(name: name, arguments: arguments, context: context)
        }
    }

    /// The catalog native for an operator symbol. The expression parser only
    /// produces symbols of supported natives (`InkParserExpressions.bindingPower`,
    /// the `!`/`_` prefixes and the `+=`/`-=` assignments), so a miss is a
    /// compiler defect; it is still reported as a compile error, never a crash.
    private static func nativeOperator(_ symbol: String) throws -> NativeFunction {
        guard let native = NativeFunctionCatalog.supportedNative(forToken: symbol) else {
            throw CompileError(
                kind: .unsupportedConstruct, construct: symbol,
                message: "operator '\(symbol)' is not a supported native function"
            )
        }
        return native
    }

    /// Lower a name: a CONST inlines its value; a name resolving to a known weave
    /// label or knot/stitch is a read-count subject (ADR-011 EXTEND #2) and emits
    /// `.readCount(path)` addressing the resolved container; a true miss (a real
    /// qualified variable) falls through to `.variableReference`.
    private static func lowerVariableReference(_ name: String, context: LoweringContext) throws -> [NodeKind] {
        if let inlined = context.constants[name] {
            return try lowerExpression(inlined, context: context)
        }
        if let path = context.readCountPath(for: name) {
            return [.readCount(.absolute(ContainerPath(components: path.map(PathComponent.init(parsing:)))))]
        }
        return [.variableReference(name: name)]
    }

    /// The catalog's built-ins by the name an author calls them with.
    private static let builtInsBySourceName: [String: NativeFunctionEntry] = Dictionary(
        NativeFunctionCatalog.entries.map { ($0.sourceName, $0) }, uniquingKeysWith: { first, _ in first })

    /// Lower a function call `f(args)`, resolving the name as C# `FunctionCall.cs`
    /// does: a built-in native first (arity-checked, then its arguments and the
    /// `.nativeFunction` node), else a story function, else an error —
    /// inklecate's "Function call target not found". A catalog-unsupported
    /// built-in (TURNS, RANDOM, LIST_…) and SEED_RANDOM, whose native does not
    /// push a value yet, keep the plain call lowering until step 04-03.
    private static func lowerFunctionCall(
        name: String,
        arguments: [InkExpression],
        context: LoweringContext
    ) throws -> [NodeKind] {
        switch builtInsBySourceName[name]?.status {
        case .supported(let native) where native != .seedRandom:
            try checkArity(of: name, expected: NativeFunctionCatalog.entry(for: native).arity, given: arguments.count)
            return try lowerArguments(arguments, parameters: [], context: context) + [.nativeFunction(native)]
        case .supported, .unsupported:
            return try lowerStoryCall(name: name, arguments: arguments, context: context)
        case nil:
            guard context.functions[name] != nil else {
                throw CompileError(kind: .unresolvedReference, message: "Function call target not found: '-> \(name)'")
            }
            return try lowerStoryCall(name: name, arguments: arguments, context: context)
        }
    }

    /// C#'s arity error for a built-in (`FunctionCall.cs`): "FLOOR should take 1
    /// parameter", "MIN should take 2 parameters".
    private static func checkArity(of name: String, expected: Int, given: Int) throws {
        guard given != expected else { return }
        let noun = expected > 1 ? "parameters" : "parameter"
        throw CompileError(kind: .syntaxError, message: "\(name) should take \(expected) \(noun)")
    }

    /// Lower a call to a story function: push each argument onto the eval stack,
    /// then emit the `.functionCall` node (inklecate's `{"f()": name}`) on which
    /// the runtime pushes a return address and jumps into the function.
    private static func lowerStoryCall(
        name: String,
        arguments: [InkExpression],
        context: LoweringContext
    ) throws -> [NodeKind] {
        let parameters = context.functions[name] ?? []
        return try lowerArguments(arguments, parameters: parameters, context: context)
            + [.functionCall(target: PathReference(parsing: name))]
    }

    /// Push call arguments onto the eval stack. An argument bound to a `ref`
    /// parameter becomes a `variablePointer` so the callee mutates the caller's
    /// variable.
    private static func lowerArguments(
        _ arguments: [InkExpression],
        parameters: [FunctionParameter],
        context: LoweringContext
    ) throws -> [NodeKind] {
        var nodes: [NodeKind] = []
        for (offset, argument) in arguments.enumerated() {
            let isReference = offset < parameters.count && parameters[offset].isReference
            if isReference, case .variableReference(let variableName) = argument {
                nodes.append(.variablePointer(name: variableName, contextIndex: globalContextIndex))
                continue
            }
            nodes.append(contentsOf: try lowerExpression(argument, context: context))
        }
        return nodes
    }
}
