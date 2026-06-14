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

## Mutation Testing Strategy

Mutation testing is **disabled** for this project. This is a durable constraint, not a deferral: no reliable, proven Swift mutation-testing solution exists, and Muter was flaky at best after significant effort.

Test quality is instead validated by the **execution-equivalence oracle suite** (supported stories are checked line-for-line and choice-for-choice against the inklecate oracle via the InkSwift JS-bridge), **code review**, and the **CI boundary gates** (the R1/R3/R5 SwiftLint `custom_rules` in `.swiftlint.yml`).
