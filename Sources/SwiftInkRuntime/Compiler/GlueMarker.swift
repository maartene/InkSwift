//
//  GlueMarker.swift
//  InkSwift
//
//  Single source of truth for the glue marker `<>` and its edge detection.
//

/// The glue marker `<>` and the rule for peeling it off the leading or trailing
/// edge of a content body.
///
/// Several content contexts each need to recognise a `<>` at the start or end of
/// a body string and emit a glue control in its place: plain content lines
/// (`InkParser.appendContent`), gather/choice outcomes
/// (`WeaveEmitter.inlineBodyStatements`), and inline-conditional branches
/// (`ConditionalEmitter.inlineBranchContainer`). Before this type each carried
/// its own `"<>"` literal and `hasPrefix`/`dropFirst`/`hasSuffix`/`dropLast`
/// triplet — the inline-conditional copy was simply never written, so `<>` there
/// leaked as literal text. Centralising the marker and the peel here means a new
/// content context reaches for one shared splitter instead of hand-rolling a
/// fourth copy that can drift or be forgotten.
///
/// `edge(of:)` only *locates* the marker and returns the remaining body
/// VERBATIM. Each call site keeps its own policy for what to do with the
/// remainder — whether to trim it, re-dispatch it through a parser, and which
/// node kind to emit — because those genuinely differ by context.
enum GlueMarker {
    /// The glue marker literal.
    static let marker = "<>"

    /// Where (if anywhere) a glue marker sits on the edge of a body.
    enum Edge: Equatable {
        /// The body begins with `<>`; `remainder` is everything after it, verbatim.
        case leading(remainder: String)
        /// The body ends with `<>`; `prose` is everything before it, verbatim.
        case trailing(prose: String)
        /// No glue marker on either edge.
        case none
    }

    /// Classify a body by its edge glue. Leading is checked first, so a bare
    /// `<>` is reported as `.leading(remainder: "")` and a body glued on both
    /// ends (`<>x<>`) is reported as `.leading` with the trailing marker left in
    /// the remainder for the caller to re-dispatch.
    static func edge(of body: String) -> Edge {
        if body.hasPrefix(marker) {
            return .leading(remainder: String(body.dropFirst(marker.count)))
        }
        if body.hasSuffix(marker) {
            return .trailing(prose: String(body.dropLast(marker.count)))
        }
        return .none
    }
}
