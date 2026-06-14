# InkSwift — Project Guidelines

## Swift Testing style mandate

All tests must use the backtick function-name style introduced in Swift Testing. The string-label form is **forbidden**.

**Correct:**
```swift
@Test func `init with non-empty root does not crash and canContinue is true`() { … }
```

**Forbidden:**
```swift
@Test("init with non-empty root does not crash and canContinue is true")
func initWithNonEmptyRootCanContinue() { … }
```

For parametrized tests, move the display name to the function and keep only `arguments:` in the attribute:

```swift
@Test(arguments: ["done", "end"])
func `step sets isEnded to true for done or end control command`(command: String) { … }
```

## Development Paradigm

object-oriented

This project follows an object-oriented / imperative paradigm (value-type structs and enums with stateful, mutating methods — e.g. `InkDecoder`, the planned `Compiler/StringParser` cursor). DELIVER-wave TDD work is dispatched to `@nw-software-crafter` with example-based oracle tests. (Recorded 2026-06-14 during the native-ink-compiler DELIVER wave, paradigm step 1.5.)

## Branching Strategy — Trunk-Based Development

This project uses **trunk-based development**. `main` is the trunk; commit directly to it. During the DELIVER wave, **commit every step to `main`** as it goes green (the RED → GREEN → COMMIT cycle lands on the trunk, not a feature branch). Keep any feature branches short-lived (< 1 day) and merge back fast.

Every commit must pass the same gate CI enforces, so the trunk stays releasable:

- **Pre-commit gate** — `.githooks/pre-commit` blocks the commit on (1) SwiftLint architecture-boundary rules (`swiftlint lint --strict --no-cache --config .swiftlint.yml`) and (2) `swift test`. It mirrors `.forgejo/workflows/tests.yml`, so a commit that passes locally passes CI.
- **Activation** — the hook is versioned under `.githooks/` and activated per-clone via `git config core.hooksPath .githooks`. Run `.githooks/install.sh` after cloning.
- **Bypass** — emergencies only: `git commit --no-verify` (or `INKSWIFT_SKIP_HOOK=1 git commit …`). Do not bypass to land red code on the trunk.

## Mutation Testing Strategy

Mutation testing is **disabled** for this project. This is a durable constraint, not a deferral: no reliable, proven Swift mutation-testing solution exists, and Muter was flaky at best after significant effort.

Test quality is instead validated by the **execution-equivalence oracle suite** (supported stories are checked line-for-line and choice-for-choice against the inklecate oracle via the InkSwift JS-bridge), **code review**, and the **CI boundary gates** (the R1/R3/R5 SwiftLint `custom_rules` in `.swiftlint.yml`).
