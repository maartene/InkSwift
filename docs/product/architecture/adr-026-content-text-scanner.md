# ADR-026: One Escape-Aware Content-Text Scanner in the Native Compiler

**Status**: Accepted (maintainer, 2026-11-19 — option D1, #34 fixed first on its own)
**Date**: 2026-11-19
**Deciders**: Maarten Engels (project owner), Morgan (solution architect)
**Feature**: reference-fidelity-backlog (issues #35, #34)

---

## Context

The native compiler scans content text in seven independent places:

- `parseContentSegments`
- `scanBraceSegment`
- `topLevelIndex`
- `topLevelBarSplit`
- `GlueMarker`
- the mid-line divert scan
- `carriesInterpolationOrTag`

None of them knows backslash escapes, and the string-literal scanner keeps the backslash pair
(`InkParserExpressions.swift:322-329`). Only `UnsupportedConstructDetector` skips escaped
characters (`:137-139, 155-167`). So `\{`, `\}` and `\#` are read as logic and tags in prose,
and a tag or string literal keeps the backslash (#35).

Separately, `parseContentSegments` trims the literal before `#` on **both** sides
(`InkParser.swift:1401`). That drops the space after an inline conditional on a tagged line
(#34).

**Reference.** One rule, `ContentTextAllowingEcapeChar` (upstream spelling, typo included) over `ContentTextNoEscape`, with a
stop set per context (`InkParser_Content.cs:117-199`):

- content: `{}|\n\r\#`
- choice: content plus `[]`
- string: content plus `"`

Tags and string expressions reuse it. `TrimEndWhitespace` (`:10-32`) trims only the last
parsed object of a line. On a tagged line that object is the tag text, so the content literal
before `#` is emitted **untrimmed** (`"^ after. "`, `"^Text   "` in inklecate's JSON). The
runtime cleans line-end whitespace.

## Decision

1. **#34 first, alone.** Do not trim the literal before a `#` at all; emit it as inklecate
   does. This is a one-line patch release ahead of the refactor. (Step 01-01 first trimmed
   only the trailing whitespace; its manual mutation check showed that trim was unobservable
   and had no counterpart in inklecate, so a follow-up commit under the same step removed it.)
2. **`Compiler/Parser/ContentTextScanner.swift` (new)**, a pure scanner.
   - Input: text and a context (content, choice, string, tag).
   - Output: a sequence of *literal runs*, already unescaped (`\x` becomes `x`), and
     *structural markers* (brace open/close, `|`, `#`, glue, divert arrow, `[`/`]`, quote),
     each with its source offset for located errors.
3. **Every content scanner consumes it**: `parseContentSegments`, the tag text, the
   string-literal tokenizer, the brace/top-level splitters, `GlueMarker` and the divert scan.
   `UnsupportedConstructDetector` uses the scanner's single escape primitive instead of its
   private helpers. "Escaped" then has one definition.
4. **Target trim policy follows `TrimEndWhitespace`**: trailing whitespace at end of line, and
   before a divert, where a single trailing space is kept. Nothing is trimmed mid-line, and
   the text before a `#` is not trimmed. Step 1 only removes the trim before `#`; see §5 for
   when anything more changes.
5. **Two modes, so only one step changes behaviour.**
   - **Step 10** introduces the scanner in an **escape-agnostic mode**. A `\` is ordinary
     text, runs are returned raw (backslashes kept), and the trim stays exactly as it is
     after #34. Every consumer is switched over in this mode. The step is behaviour-neutral:
     the oracle, conformance and TheIntercept e2e are unchanged, and no AT changes.
   - **Step 11** switches the mode to **escape-aware**: `\x` becomes a literal `x`, and an
     escaped character never acts as a stop. This is the single behaviour change that fixes
     #35. Trim behaviour stays as after #34: no trim before `#`, and any further
     alignment of the trim policy with `TrimEndWhitespace` is gated on a separate probe.

   Two items stay DELIVER probes:
   - the `{\…}` "escape-to-sequence" reading in `modeAndContent` (`InkParser.swift:1490`);
   - the backlog entry "escaped characters in alternatives".

## Alternatives Considered

- **D2: fix #34, then add an `unescape` post-pass and escape-aware index helpers to each
  scanner.** **Rejected** as the end state: escape logic would stay in about seven places,
  and one missed scanner (`->` detection, `GlueMarker`) re-opens #35. Kept as the fallback if
  D1 stalls.
- **Port inklecate's full `StringParser` combinator** (ADR-007 territory). **Rejected**: far
  beyond the scope; the content-text rule is the only part needed.

## Consequences

**Positive**
- Escapes behave the same in prose, choice text, tags and strings.
- One definition of "escaped" is shared with the reject detector.

**Negative**
- Every content line passes through new code. The execution-equivalence oracle and the
  TheIntercept e2e gate it.

**Release**: #34 and #35 are each a **patch**. The refactor step ships with #35.
