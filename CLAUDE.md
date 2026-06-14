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

## Acceptance tests, DISTILL, and the pre-commit gate

Outside-In TDD has DISTILL author acceptance tests (ATs) up front, before the DELIVER steps that make them pass. Because the pre-commit gate runs the **full** `swift test`, an AT that is *enabled but unimplemented* is red — it fails the suite, fails the hook, and blocks **every** commit until the whole feature lands. That defeats per-step trunk commits.

Resolve this with the Swift Testing `.disabled` trait:

1. **DISTILL authors every new AT disabled**, with a reason naming the DELIVER step/criteria that will satisfy it. A disabled test is reported as *skipped* — the suite stays green and commits are allowed.
   ```swift
   @Test(.disabled("pending DELIVER step 06-02: weave choice nesting"))
   func `nested weave choices match the JavaScript oracle`() { … }
   ```
   For parametrized ATs the trait sits alongside `arguments:` (name stays on the function per the style mandate):
   ```swift
   @Test(.disabled("pending DELIVER step 06-01"), arguments: ["a", "b"])
   func `output matches the oracle for each branch`(input: String) { … }
   ```
   The `.disabled("…")` string is a **trait argument, not a test display name** — it does NOT violate the backtick-name mandate above. Never put the human-readable scenario in a `@Test("…")` label.

2. **DELIVER re-enables on green.** The step that makes an AT pass removes that AT's `.disabled` trait as part of GREEN, so the now-passing test guards the COMMIT. A step never commits with its own target AT still disabled.

3. **Compile caveat.** `.disabled` skips *execution*, not *compilation* — an AT must still compile. If an AT references not-yet-existing public API, land that API's signature (a stub) first so the test compiles, then keep it `.disabled` until the behaviour is implemented.

4. **Finalize invariant: zero `.disabled` ATs may remain** when a feature's DELIVER wave completes. A leftover disabled AT means a scenario silently never ran — treat it as incomplete delivery. Quick check: `grep -rn "\.disabled(" Tests/SwiftInkRuntimeTests/Acceptance` should return nothing at finalize.

Alternative — `withKnownIssue { … }`: wrap an AT body instead of disabling it when you want the test to keep *executing* while red and to auto-fail the moment the feature starts passing (forcing removal of the wrapper, an automatic tripwire). Prefer `.disabled` when the AT cannot meaningfully run yet; prefer `withKnownIssue` when the API exists but behaviour is only partially done.

## Mutation Testing Strategy

Mutation testing is **disabled** for this project. This is a durable constraint, not a deferral: no reliable, proven Swift mutation-testing solution exists, and Muter was flaky at best after significant effort.

Test quality is instead validated by the **execution-equivalence oracle suite** (supported stories are checked line-for-line and choice-for-choice against the inklecate oracle via the InkSwift JS-bridge), **code review**, and the **CI boundary gates** (the R1/R3/R5 SwiftLint `custom_rules` in `.swiftlint.yml`).
