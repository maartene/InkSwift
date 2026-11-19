// The walker's output helpers: the only code that appends to
// `StoryState.outputStream` (SwiftLint R7 bans `outputStream.append(` elsewhere).
// Tags are items at their position in the stream (ADR-020 §1): glue stops at a
// tag, and the nop trim and newline de-duplication look at text items only.
extension TreeWalker {

    /// Append a newline unless glue is in force or the output does not accept one.
    func appendNewline(state: inout StoryState) {
        if state.suppressNextNewline == false && outputAcceptsNewline(state) {
            state.outputStream.append(.newline)
        }
    }

    /// Append text to the output stream. Once non-whitespace text arrives, any
    /// glue (<>) has done its job of joining the preceding text, so the next \n
    /// is a real line ending again. Whitespace alone keeps the glue in force, as
    /// in the reference (`PushToOutputStreamIndividual` clears glue only on
    /// `isNonWhitespace` text).
    ///
    /// The item takes its wire spelling: a text of exactly `"\n"` is a line
    /// break that still clears the glue, as it did while the stream was a
    /// `[String]`.
    func appendToOutput(_ string: String, state: inout StoryState) {
        state.outputStream.append(OutputItem(wireText: string))
        if string.contains(where: { $0 != " " && $0 != "\t" }) {
            state.suppressNextNewline = false
        }
    }

    /// A content tag, closed (`/#`): it belongs to the line it sits in, so a tag
    /// after a newline starts the next line (Story.cs ~689-718).
    func appendTag(_ tag: String, state: inout StoryState) {
        state.outputStream.append(.tag(tag))
    }

    /// Glue: remove any trailing newlines already in the output stream AND
    /// suppress every newline until non-whitespace text is appended (see
    /// `appendToOutput`) — a block after the glue brings its own `\n` and its
    /// branch's, and both must go. This joins the preceding
    /// text with whatever follows the glue marker — even when the `\n` comes
    /// after the `<>` node in the JSON (e.g. `"text " <> \n -> next_section`).
    /// A tag stops the trim, as a control command stops C#
    /// `TrimNewlinesFromOutputStream`: `Before` / `# t` / `<> after` stays two lines.
    func applyGlue(state: inout StoryState) {
        while state.outputStream.last == .newline {
            state.outputStream.removeLast()
        }
        state.suppressNextNewline = true
    }

    /// Trim trailing whitespace from the output stream.
    /// In inklecate, `nop` is emitted as the "else" path for inline conditionals
    /// so that `{condition: then} rest` does not produce a double space when the
    /// condition is false: the space that the text before the `{...}` contributed
    /// is consumed here, leaving a single space before the continuation text.
    /// Tags after the text are looked past: the trim sees text items only.
    func trimTrailingSpace(state: inout StoryState) {
        guard let index = state.outputStream.lastIndex(where: { $0.isTag == false }),
              case .text(let last) = state.outputStream[index], last.last == " " else { return }
        let trimmed = String(last.dropLast())
        if trimmed.isEmpty {
            state.outputStream.remove(at: index)
        } else {
            state.outputStream[index] = .text(trimmed)
        }
    }

    /// De-duplicate newlines, and never lead with one: a newline is written only
    /// when the output has text and does not already end in a newline, looking
    /// back past inline whitespace and tags (ADR-020 §1: text items only, so a
    /// line holding just a tag does not end there; the tag stays with the text
    /// that follows). Mirrors the reference
    /// `StoryState.PushToOutputStreamIndividual` (its `outputStreamEndsInNewline`
    /// and `outputStreamContainsContent`). inklecate relies on it: each block's
    /// rejoin point and each branch start with a `"\n"` of their own.
    private func outputAcceptsNewline(_ state: StoryState) -> Bool {
        guard state.outputStream.contains(where: { $0.isTag == false }) else { return false }
        for item in state.outputStream.reversed() {
            if item == .newline { return false }
            if item.isNonWhitespaceText { return true }
        }
        return true
    }
}
