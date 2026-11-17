// WHY-NEW-FILE: Sources/SwiftInkRuntime/Compiler/Codegen/LoweringContext.swift
//   CLOSEST-EXISTING: Sources/SwiftInkRuntime/Compiler/Codegen/RuntimeObjectEmitter.swift
//   EXTENSION-COST: the context was a nested type of RuntimeObjectEmitter, which
//     was past 1,400 lines; its scope-aware name resolution is a responsibility of
//     its own, independent of how statements are lowered.
//   PARALLEL-RATIONALE: every lowerer (RuntimeObjectEmitter, ExpressionLowering,
//     and the closures handed to ConditionalEmitter / WeaveEmitter /
//     VariableTextEmitter) threads the same immutable context; as a top-level
//     type it is shared rather than owned by one emitter.

import Foundation

/// Codegen-wide lowering inputs threaded through the lowerers: the CONST
/// inlining table and the function-signature table (so a `ref` argument can
/// be lowered to a `variablePointer` at the call site).
struct LoweringContext {
    let constants: [String: InkExpression]
    let functions: [String: [FunctionParameter]]
    /// The weave-label addressing table (ADR-011 EXTEND #3): source label ->
    /// absolute compiled path, populated by the discovery pre-pass before
    /// expression lowering so a read-count reference (later steps) resolves a
    /// label to its container path order-independently. Labelled-only. Threaded
    /// identically to the CONST and function tables; write-only at this slice
    /// (02-03 consumes it to emit `.readCount`).
    var weaveLabelPaths: [String: [String]] = [:]
    /// The knot/stitch read-count addressing table (ADR-011 EXTEND #2): a
    /// dotted source name (`knot.stitch`, or a bare `knot`) -> its absolute
    /// compiled namedContent path. Reuses the path emitKnot/emitStitch already
    /// key their containers by; consumed by the `.variableReference` lowering to
    /// emit `.readCount` for a dotted read-count subject naming a knot/stitch.
    var knotStitchPaths: [String: [String]] = [:]
    /// Names that are function-local in the current scope (parameters plus
    /// `~ temp` declarations inside a function body). An assignment to a local
    /// name lowers to `temp=` so the runtime consults the call frame — the
    /// write-through path that makes a `ref` parameter mutate the caller's
    /// variable. Empty at knot/root scope (all assignments are global there).
    var localNames: Set<String> = []
    /// The enclosing knot name of the body being lowered (empty at root). A bare
    /// divert target `-> T` inside a knot resolves first to a SIBLING stitch
    /// `knot.T` (ink scoping: current-knot stitch before root knot), but the
    /// runtime resolves divert targets ABSOLUTELY from root — so a bare stitch
    /// target dead-ends (no root-level `T`). The divert lowerer consults this to
    /// qualify a bare target to `knot.T` when `knot.T` is a known stitch.
    var knotScope: String = ""

    func bindingLocals(_ names: Set<String>) -> LoweringContext {
        LoweringContext(
            constants: constants, functions: functions,
            weaveLabelPaths: weaveLabelPaths, knotStitchPaths: knotStitchPaths,
            localNames: names, knotScope: knotScope
        )
    }

    /// Bind the enclosing knot scope so bare stitch-local diverts qualify.
    func inKnotScope(_ knotName: String) -> LoweringContext {
        LoweringContext(
            constants: constants, functions: functions,
            weaveLabelPaths: weaveLabelPaths, knotStitchPaths: knotStitchPaths,
            localNames: localNames, knotScope: knotName
        )
    }

    /// Resolve a bare divert target against the current knot scope. A bare `T`
    /// that names a sibling stitch (`knot.T` is a known stitch path) qualifies to
    /// `knot.T` so the runtime's absolute-from-root resolution finds it. A bare `T`
    /// that names a WEAVE LABEL anywhere in the current knot (`knot.T` is a known
    /// weave-label name) qualifies to that label's ABSOLUTE physical container
    /// path — a deeply-nested gather label (`-> pushes_cup` reaching a `- -`
    /// gather inside a sibling choice body) resolves regardless of nesting depth,
    /// mirroring inklecate's by-name weave-point resolution. Any other target
    /// (already-dotted, root knot, relative `.^`) is returned unchanged. Mirrors
    /// ink scoping (current-knot stitch / weave label before root knot).
    func qualifiedDivertTarget(_ target: String) -> String {
        guard knotScope.isEmpty == false,
              target.contains(".") == false,
              target.hasPrefix(".") == false else { return target }
        let qualified = "\(knotScope).\(target)"
        if knotStitchPaths[qualified] != nil { return qualified }
        if let labelPath = weaveLabelPaths[qualified] { return labelPath.joined(separator: ".") }
        return target
    }

    /// Resolve a (possibly dotted) name to the absolute compiled path of a
    /// known weave label or knot/stitch, reusing the pre-built tables — never
    /// re-deriving. Returns nil for a true miss (a real qualified variable).
    ///
    /// A BARE read-count subject (`{ not nope: … }`) resolves in LOCAL knot scope
    /// FIRST — symmetric with `qualifiedDivertTarget`'s by-name weave-point
    /// resolution. inklecate resolves a bare read-count reference against the
    /// enclosing knot's namespace; the `knot.label` key is registered by
    /// `discoverLabelPaths`/`mergeWeaveLabelPaths`. Without this, a bare label
    /// that is NOT unique story-wide (so `mergeUniqueBareLabels` leaves it
    /// dotted-only — e.g. `nope` appears in two knots) fell through to
    /// `.variableReference`, evaluating an undefined variable instead of the
    /// label's read-count. The knot-scoped lookup precedes the bare-global lookup
    /// so a local label shadows a same-named label in another knot.
    func readCountPath(for name: String) -> [String]? {
        if knotScope.isEmpty == false, name.contains(".") == false {
            if let localPath = weaveLabelPaths["\(knotScope).\(name)"] { return localPath }
        }
        if let labelPath = weaveLabelPaths[name] { return labelPath }
        return knotStitchPaths[name]
    }
}
