# Shared Artifacts Registry — tier3-conditionals-and-tunnels

## Registry

```yaml
shared_artifacts:

  ink_json_fixture:
    source_of_truth: "inklecate compiler output — .ink.json files in Tests/SwiftInkRuntimeTests/Resources/"
    consumers:
      - "SwiftInkRuntimeTests unit tests (fixture loading)"
      - "Integration tests (Story initialisation)"
      - "Oracle comparison tests (InkStory initialisation)"
    owner: "inklecate (external compiler)"
    integration_risk: "HIGH — hand-crafted JSON misses numeric path prefixes and produces false-green tests (see Tier 2 lessons learned)"
    validation: "inklecate must compile the source; resulting JSON must parse without errors in both Story and InkStory"

  story_current_text:
    source_of_truth: "SwiftInkRuntime.Story.currentText (computed property)"
    consumers:
      - "Acceptance test assertions in ConditionalTextTests"
      - "Acceptance test assertions in FunctionTests"
      - "Acceptance test assertions in TunnelTests"
      - "Oracle comparison (XCTAssertEqual against InkStory)"
    owner: "SwiftInkRuntime.Story (Facade layer)"
    integration_risk: "MEDIUM — text output includes trailing newlines from Ink; assertions must trim consistently"
    validation: "Every continue() call result captured; compared character-for-character with oracle"

  story_state_codable:
    source_of_truth: "SwiftInkRuntime.StoryState (Codable struct in Engine/StoryState.swift)"
    consumers:
      - "Save/restore acceptance tests across all slices"
      - "Any new StoryState fields added in Tier 3 (function callstack frames, conditional eval context)"
    owner: "SwiftInkRuntime (Engine layer)"
    integration_risk: "HIGH — any new field must use decodeIfPresent with safe default to avoid breaking existing save files"
    validation: "saveState() → restoreState() round-trip must produce identical story.continue() output"

  return_stack:
    source_of_truth: "StoryState.returnStack: [String] (ADR-004)"
    consumers:
      - "TunnelTests (push on ->t-> entry, pop on ->-> return)"
      - "FunctionTests (push on f() entry, pop on ~ret)"
      - "Save/restore tests for tunnels and functions"
    owner: "SwiftInkRuntime (Engine layer — InkEngine + TreeWalker)"
    integration_risk: "HIGH — returnStack depth must be correct across nested tunnels; LIFO discipline required"
    validation: "returnStack.count before and after tunnel/function call must match; post-call count == pre-call count"

  oracle_ink_story:
    source_of_truth: "InkSwift.InkStory (frozen module — Sources/InkSwift/InkStory.swift)"
    consumers:
      - "Integration tests in SwiftInkRuntimeTests/Integration/"
    owner: "InkSwift module (frozen — no changes permitted)"
    integration_risk: "LOW — frozen module; only risk is accidental import in production code"
    validation: "InkSwift module must never be imported from SwiftInkRuntime production sources"

  inklecate_binary:
    source_of_truth: "/Users/maartene/Downloads/inklecate_mac/inklecate"
    consumers:
      - "All test fixture compilation steps"
      - "Developer workflow for creating new fixture stories"
    owner: "inkle Studios (external)"
    integration_risk: "MEDIUM — path is machine-specific; must be documented and not hardcoded in test code"
    validation: "inklecate --version must succeed before fixture compilation; path documented in CLAUDE.md memory"
```

## Integration Risk Summary

| Artifact | Risk Level | Key Constraint |
|---|---|---|
| `ink_json_fixture` | HIGH | Only inklecate output; no hand-crafted JSON |
| `story_state_codable` | HIGH | All new fields: `decodeIfPresent` with safe defaults |
| `return_stack` | HIGH | LIFO discipline; depth must balance across all call sites |
| `story_current_text` | MEDIUM | Trailing newline handling must be consistent in assertions |
| `inklecate_binary` | MEDIUM | Path documented; not hardcoded in source |
| `oracle_ink_story` | LOW | Frozen; never imported in production sources |
