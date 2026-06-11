# Mutation Testing Report — story-testability

**Status**: SKIPPED
**Date**: 2026-06-11
**Reason**: No reliable mutation testing tooling available for Swift

Automated mutation testing tools for Swift (e.g. muter/MuterX) are not present in this environment and are not yet reliable for SPM projects. This skip is documented per the nw-mutation-test skip condition: "No tool for language — No mutation framework available for detected language."

**Test Quality Evidence (substitutes for automated mutation score):**
- 28/28 acceptance tests in Milestone7_StoryTestabilityTests.swift cover all 4 US methods
- Unit tests verify bridging edge cases: Bool-before-Int ordering, .variablePointer → nil, absent key → nil
- Adversarial review (Phase 4) confirmed zero Testing Theater patterns
- All tests entered RED state for business-logic reasons (not import/syntax errors) before GREEN

**Manual Mutation Spot-Check:**
| Mutation | Caught by test? |
|---|---|
| Remove Bool guard → Bool coerces to Int | "setVariable for Bool is readable back via getVariable" → FAIL |
| `?? 0` → `?? 1` in visitCount | "visitCount returns 0 for unvisited knot" → FAIL |
| `while canContinue` → `if canContinue` in continueMaximally | "continueMaximally collects all lines" → FAIL |
| Remove `guard state.variablesState[name] != nil` in setVariable | "setVariable for unknown variable" test confirms nil after set → FAIL |
| Remove setVisitCount guard → create unknown keys | "setVisitCount for unknown knot does not throw" + visitCount returns 0 → FAIL |
