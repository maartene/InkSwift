# Shared Artifacts Registry — native-move-to-knot

Feature ID: native-move-to-knot
Date: 2026-06-08

---

## Registry

```yaml
shared_artifacts:
  knot_name:
    source_of_truth: "caller-supplied String parameter to Story.moveToKnot(_:stitch:)"
    consumers:
      - "InkEngine.moveToKnot: path resolution (root.namedContent lookup)"
      - "StoryError.knotNotFound message (includes attempted path)"
      - "Test fixtures: Ink source knot names must match call-site strings exactly"
    owner: "SwiftInkRuntime — Story facade"
    integration_risk: "HIGH — Ink knot names are case-sensitive; a mismatch produces knotNotFound at runtime"
    validation: "Test both exact-match (succeeds) and case-variant (fails) lookups"

  compound_path:
    source_of_truth: "Constructed inside InkEngine from knot + '.' + stitch"
    consumers:
      - "Container tree lookup: root.namedContent[knot].namedContent[stitch]"
      - "StoryError.knotNotFound message"
    owner: "SwiftInkRuntime — InkEngine"
    integration_risk: "MEDIUM — path construction must use '.' separator to match Ink's dotted-path convention"
    validation: "Verify constructed path matches inklecate's own named-content hierarchy"

  state_reset_fields:
    source_of_truth: "InkEngine.resetForJump() (new internal method)"
    consumers:
      - "containerStack — replaced with single frame for target"
      - "returnStack — cleared to []"
      - "evalStack — cleared to []"
      - "currentChoices — cleared to []"
      - "outputStream — cleared to []"
      - "callFrameVariables — cleared to []"
      - "suppressNextNewline — reset to false"
      - "isEnded — reset to false"
      - "inTagMode — reset to false"
      - "tagAccumulator — reset to ''"
      - "inStringMode — reset to false"
      - "stringAccumulator — reset to ''"
    owner: "SwiftInkRuntime — InkEngine"
    integration_risk: "HIGH — any field left un-reset can cause incorrect output on first continue() or corrupt save/restore"
    validation: "Assert all fields in the list above have been reset before installing new pointer; test with a story that has active tunnel frames before the jump"

  story_error_knotnotfound:
    source_of_truth: "StoryError enum — new case knotNotFound(String) in Story.swift"
    consumers:
      - "InkEngine.moveToKnot: thrown when path cannot be resolved"
      - "Story.moveToKnot facade: rethrows"
      - "Developer catch sites in host app"
      - "Test assertions: XCTAssertThrowsError matching .knotNotFound"
    owner: "SwiftInkRuntime — Story facade / StoryError"
    integration_risk: "MEDIUM — error case must be added to StoryError before InkEngine can throw it; order of implementation matters"
    validation: "Verify knotNotFound is in StoryError enum; verify thrown path matches the attempted path string"

  visit_counts:
    source_of_truth: "StoryState.visitCounts — preserved across jump"
    consumers:
      - "CNT? nodes: read counts of previously visited knots remain valid after jump"
      - "Once-only choice suppression: chosenChoiceTargets preserved"
    owner: "SwiftInkRuntime — StoryState"
    integration_risk: "LOW — visit counts are NOT cleared on jump (C# reference runtime preserves them); clearing them would be a bug"
    validation: "Test that a knot visited before the jump still has a non-zero visit count after the jump"

  variable_state:
    source_of_truth: "StoryState.variablesState — preserved across jump"
    consumers:
      - "Variable references in target knot read the same variables set before the jump"
    owner: "SwiftInkRuntime — StoryState"
    integration_risk: "LOW — variables are NOT cleared on jump (matching C# reference runtime behaviour)"
    validation: "Test that a global variable set before the jump retains its value in the target knot"
```

---

## Integration Validation Checklist

- [ ] Every `${variable}` referenced in the journey YAML has an entry above
- [ ] `state_reset_fields` lists all fields from `StoryState` struct — cross-checked against StoryState.swift
- [ ] `visit_counts` and `variable_state` are explicitly documented as NOT reset (important distinction from other fields)
- [ ] `story_error_knotnotfound` is defined before `InkEngine` references it (implementation ordering note)
- [ ] Test fixtures use inklecate-compiled JSON (per project feedback: no hand-crafted JSON)
