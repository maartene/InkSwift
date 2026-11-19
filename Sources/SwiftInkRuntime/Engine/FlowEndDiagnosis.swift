/// The end-of-content check of C# Story.ContinueInternal (Story.cs ~502-516),
/// ADR-020 §5: why a flow that ran out of content, without a safe exit and
/// without choices, cannot go on.
///
/// The C# "unknown reason" branch needs threads, which InkSwift lacks, so it
/// is omitted. Messages are bare, without inkjs's location prefix (ADR-017).
enum FlowEndDiagnosis {
    /// The error to report after a `continue()` that stopped for `stopReason`,
    /// or nil when there is none. Only a ran-out stop with no choices pending is
    /// diagnosed: a safe exit (`done`, `end`, a forced end) and a stop at a
    /// choice point are not errors.
    static func message(
        stopReason: InkEngine.FlowStop?,
        returnStackTop: CallKind?,
        choicesEmpty: Bool
    ) -> String? {
        guard stopReason == .ranOut, choicesEmpty else { return nil }
        switch returnStackTop {
        case .tunnel:
            return "unexpectedly reached end of content. Do you need a '->->' to return from a tunnel?"
        case .function:
            return "unexpectedly reached end of content. Do you need a '~ return'?"
        case nil:
            return "ran out of content. Do you need a '-> DONE' or '-> END'?"
        }
    }
}
