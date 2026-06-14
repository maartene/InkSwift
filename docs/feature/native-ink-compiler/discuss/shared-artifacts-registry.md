# Shared Artifacts Registry: native-ink-compiler

**Feature**: native-ink-compiler
**Created**: 2026-06-14
**Maintainer**: nw-product-owner

Shared artifacts flowing across the compilation journey. Each has a single source
of truth and documented consumers. Untracked artifacts are the primary cause of
horizontal integration failure — here the dominant risk is **scope drift** between
what the compiler accepts and what the runtime can play.

```yaml
shared_artifacts:

  supported_feature_set:
    source_of_truth: "docs/product/architecture/brief.md — Ink Feature Coverage Matrix, rows 1-35 (status WORKS / IMPLEMENTED)"
    consumers:
      - "compiler accepted-construct set"
      - "supported/unsupported feature reference document (Slice S5 deliverable)"
      - "every execution-equivalence acceptance test fixture"
    owner: "SwiftInkRuntime (the runtime defines what is playable; the compiler mirrors it)"
    integration_risk: "HIGH — if the compiler accepts a construct the runtime cannot play, the author ships a silently broken story. This is the single most important consistency invariant."
    validation: "For each accepted construct, an oracle execution-equivalence test proves the runtime plays the compiled output identically to inklecate."

  unsupported_feature_set:
    source_of_truth: "docs/product/architecture/brief.md — Ink Feature Coverage Matrix, rows 25-28 (variable-text sequences/cycles/once/shuffle, runtime status UNKNOWN/no handler) and rows 36-39 (threads, LIST, RANDOM/SEED_RANDOM, external functions, status MISSING)"
    consumers:
      - "compiler reject-with-error set"
      - "supported/unsupported feature reference document"
      - "compile error messages (the named construct)"
    owner: "SwiftInkRuntime"
    integration_risk: "HIGH — an unsupported construct that compiles instead of erroring is exactly the silent-failure outcome the user prohibited."
    validation: "For each unsupported construct, a test asserts compilation stops with an error naming the construct and reporting its source location."

  inklecate_oracle_output:
    source_of_truth: "inklecate binary at /Users/Maarten.Engels/.local/bin/inklecate"
    consumers:
      - "every execution-equivalence acceptance test (Level 1 oracle)"
      - "secondary JSON structural comparison (Level 2 oracle, lower priority)"
    owner: "external ground-truth reference (inkle C# compiler)"
    integration_risk: "MEDIUM — oracle is authoritative; risk is cosmetic JSON differences (container naming, key order) being mistaken for semantic divergence. Mitigated by preferring execution-equivalence over structural comparison."
    validation: "Compile the same .ink with both the native compiler and inklecate; play both through the runtime along fixed choice paths; assert text/choice output identical."

  compiled_story_shape:
    source_of_truth: "the input contract of the SwiftInkRuntime Story (owned by the runtime)"
    consumers:
      - "native compiler output (primary deliverable: a directly-runnable story)"
      - "runtime input"
    owner: "SwiftInkRuntime"
    integration_risk: "HIGH — the primary output must be consumable by the runtime with no JSON round-trip. If the shape diverges from what the runtime expects, the whole value proposition (in-process compile-to-run) breaks."
    validation: "Walking skeleton proves a compiled story plays in the runtime end to end; every subsequent slice extends the same hand-off."

  ink_json_format:
    source_of_truth: "Ink C# runtime serialiser — JsonSerialisation.cs (format owned by inkle); documented in docs/ink_JSON_runtime_format.md and the research doc's JSON Output Format section"
    consumers:
      - "secondary JSON output (valued for oracle structural comparison and on-disk caching/interop)"
      - "Level 2 structural-comparison oracle"
    owner: "external (inkle); pinned to the runtime's targeted version"
    integration_risk: "LOW — secondary, lower-priority output. Format has been stable for years and is pinned alongside the runtime."
    validation: "Normalise (sort keys, canonicalise container names) then compare structurally against inklecate JSON for the same source."

  compile_time_obligations:
    source_of_truth: "docs/product/architecture/brief.md — matrix row 17 (CONST inlining: 'inklecate inlines CONSTs as integer literals, so no engine support is required') and row 10 (invisible-default / choice-flag encoding)"
    consumers:
      - "compiler code-generation behaviour"
    owner: "SwiftInkRuntime (defines what it assumes was already done at compile time)"
    integration_risk: "HIGH — the runtime does NOT perform CONST inlining or choice-flag/invisible-default encoding; it assumes the compiler (replacing inklecate) already did. Omitting this makes supported stories mis-play with no error."
    validation: "Slices covering CONST and choices include oracle execution-equivalence tests that would fail if inlining/encoding were skipped."
```

## Consistency Check (Phase 5 validation)

| Check | Result |
|---|---|
| Every shared artifact has a single documented source of truth | PASS |
| The supported and unsupported feature sets derive from the same runtime matrix (no third list) | PASS — both cite `brief.md` Feature Coverage Matrix |
| The feature reference document (Slice S5) consumes, not re-defines, the matrix | PASS — registry marks it a consumer, not an owner |
| Error messages name constructs from the unsupported set (single source) | PASS |
| Compiled-story shape is owned by the runtime, not re-invented by the compiler | PASS |
| Oracle is a single binary path, referenced by all equivalence tests | PASS |

## Vocabulary (ubiquitous language for this feature)

| Term | Meaning |
|---|---|
| compile | turn .ink source into a runnable story, in-process, pure Swift |
| supported feature | an Ink construct the runtime can play (matrix rows 1-35) |
| unsupported feature | an Ink construct the runtime cannot play; the compiler rejects it (rows 25-28, 36-39) |
| reject (with error) | stop compilation, produce no story, name the construct + location |
| oracle / execution-equivalence | inklecate-compiled output played through the runtime, used as correctness ground truth |
| runnable story | the in-memory story object the runtime consumes directly (no JSON round-trip) |
| compile-time obligation | work the runtime assumes was done before play: CONST inlining, choice-flag/invisible-default encoding |
| walking skeleton | the thinnest end-to-end slice: one line of plain text, compiled and played, matching the oracle |
