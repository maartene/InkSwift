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
