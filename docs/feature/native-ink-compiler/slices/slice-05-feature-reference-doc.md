# Slice 05 — Supported / unsupported feature reference document

**Feature**: native-ink-compiler | **Release**: 4 (No surprises) | **Priority**: P6
**Persona**: Maarten (also serves Raya as author) | **Job**: job-native-compilation
**Depends on**: derives from runtime matrix; finalised after S1-S4 + S6

## Learning hypothesis
DISPROVES "an author can determine, before authoring, whether any given Ink
construct will compile or be rejected" if the reference is incomplete, ambiguous,
or drifts from what the compiler actually does.

## Outcome
A readable reference document the author consults to stay inside the supported
feature set — listing every Ink construct as MUST-COMPILE or MUST-REJECT, with a
short example and the reason, derived from the runtime's Feature Coverage Matrix.

## Production-real data
- The actual runtime Feature Coverage Matrix (`brief.md` rows 1-39) is the source.
- Each row gets a one-line Ink example (e.g. supported: `* [Open the door]`;
  rejected: `{shuffle|a|b}`).

## Dogfood moment
Before writing a new scene, Maarten (or Raya) checks the reference, sees that
`LIST` is rejected, and chooses a variable-based design instead — avoiding a
failed compile entirely.

## IN scope
- A single document listing all supported constructs (MUST-COMPILE) and all
  unsupported constructs (MUST-REJECT), each with an example and a reason.
- Explicit statement that the supported set == the runtime's playable set.
- Cross-reference: the reject entries match the error messages S6 emits.

## OUT of scope
- The compiler behaviour itself (S0-S4, S6) — this slice is the documentation artifact.
- Tutorials or how-to authoring guides (this is reference, per DIVIO/Diataxis).

## Acceptance (behavioural; Gherkin)
```gherkin
Scenario: The reference lists every supported construct with an example
  Given the supported/unsupported feature reference document
  When an author looks up a supported construct (e.g. tunnels)
  Then the document shows it as supported with a one-line example and reason

Scenario: The reference lists every unsupported construct with an example
  Given the reference document
  When an author looks up an unsupported construct (e.g. LIST)
  Then the document shows it as rejected with a one-line example and reason

Scenario: The reference matches actual compiler behaviour
  Given the reference document and the compiler
  When any construct's documented status (compile/reject) is checked against the compiler
  Then the documented status matches what the compiler does for that construct
```

## Carpaccio taste tests
- **Thin?** Yes — one document, derived from an existing matrix. **End-to-end?**
  N/A (artifact, not flow) — but it is a complete, standalone user-consumable deliverable.
- **Demonstrable?** Yes — the author reads it and predicts compile outcomes.
- **≤1 day?** Yes. **Independent value?** Yes — the user explicitly requested
  "a clear description of supported/unsupported features."
- **Note:** draft early as a living artifact; finalise last so it reflects shipped reality.
