# Migrate from the JS-bridge (`InkStory`) to the native runtime

> **How-to (Diataxis).** This guide maps every public call on the legacy JavaScriptCore
> JS-bridge type `InkStory` to its native `SwiftInkRuntime` equivalent (`Story` /
> `InkCompiler`), so you can rewrite your code call-by-call. It flags the shape
> differences and the one capability that has **no native equivalent**.

The JS-bridge is fully supported in 2.x. It will be **deprecated in v3.0.0**, when the
native runtime becomes the `InkSwift` product, and **removed in v4.0.0**. Before migrating, check the
[supported-parity / known-gaps statement](../reference/js-bridge-vs-native-parity.md) to
confirm the native runtime supports your story's features.

## API mapping — `InkStory` → `Story` / `InkCompiler`

| JS-bridge (`InkStory`) | Native (`Story` / `InkCompiler`) | Notes |
|---|---|---|
| `InkStory()` + `loadStory(json:)` | `Story(blueprint: try StoryBlueprint(json:))` | construction + load merge into one initializer |
| `loadStory(ink:)` (in-process compile) | `Story(blueprint: try InkCompiler.compile(source:))` | native compiler, no JS engine |
| `continueStory()` | `continue()` | added `throws` |
| `canContinue` | `canContinue` | same name |
| `currentText` | `currentText` | same name |
| `currentErrors` | `currentErrors` | story errors only (e.g. a `->->` or `~ return` with no matching frame); they stop the story. API misuse throws instead — see the [parity reference](../reference/js-bridge-vs-native-parity.md#api-gaps) |
| `options: [Option]` | `currentChoices: [Choice]` | property + element type rename |
| `chooseChoiceIndex(_:)` | `chooseChoice(at:) throws` | added `throws` |
| `moveToKnitStitch(_:stitch:)` | `moveToKnot(_:stitch:) throws` | added `throws` |
| `currentTags: [String: String]` | `currentTags: [String]` | **shape differs** — dictionary → array |
| `globalTags: [String: String]` | `globalTags: [String]` | **shape differs** — dictionary → array |
| `getVariable(_:) -> JXValue` | `getVariable(_:) -> Any?` | return type `JXValue` → `Any?` |
| `setVariable(_:to:)` String/Int/Double overloads | `setVariable(_:to: some Any)` | one generic call replaces the overloads |
| `stateToJSON() -> String` | `saveState() throws -> Data` | **shape differs** — `String` → `Data`, added `throws` |
| `loadState(_:)` | `restoreState(_:) throws` | takes `Data`, added `throws` |
| `retainTags` | (no direct equivalent) | JS-bridge tag-retention behaviour; not needed with the native array tag model |
| `registerObservedVariable(_:)` | ⚠️ **no native equivalent** | Combine observation gap — see below |
| `deregisterObservedVariable(_:)` | ⚠️ **no native equivalent** | Combine observation gap — see below |
| `oberservedVariables` | ⚠️ **no native equivalent** | Combine observation gap — see below |
| — | native extras: `visitCount(forKnot:)`, `continueMaximally()` | no JS-bridge counterpart |

## Shape differences to watch

- **Tags: `[String: String]` → `[String]`.** Both `currentTags` and `globalTags` change
  from a dictionary to an array on the native runtime. Code that indexes tags by key must
  adapt to array iteration.
- **State: `String` → `Data`.** `stateToJSON()` returned a JSON `String`; the native
  `saveState()` returns `Data` and `throws`. Persist `Data` (or base64-encode it) instead
  of a string, and reload via `restoreState(_:)`.
- **Variables: `JXValue` → `Any?`.** `getVariable` no longer returns a JavaScriptCore
  `JXValue`; it returns `Any?`. Cast to the concrete Swift type you expect.
- **Added `throws`.** Choice selection, knot movement, continue, and state save/restore
  all throw on the native runtime — wrap them in `do` / `try` / `catch`.

## The Combine reactive-observation gap (no native equivalent)

The JS-bridge conforms to `ObservableObject`, exposes `@Published` properties, and lets
you observe individual Ink variables via `registerObservedVariable(_:)` /
`deregisterObservedVariable(_:)`, surfacing changes through the `oberservedVariables`
dictionary and Combine.

**The native `Story` has no Combine / reactive-observation equivalent.** There is nothing
to register, deregister, or publish. If you rely on Combine variable observation, either:

- **poll** `getVariable(_:)` at the points in your flow where a value could have changed, or
- **stay on the JS-bridge** until (or unless) native observation lands — this gap is
  tracked in the [parity statement's living backlog](../reference/js-bridge-vs-native-parity.md).

## When the JS-bridge is retired

| Version | What changes for `InkStory` users |
|---|---|
| 2.1.x | Nothing: `InkStory` is supported. (2.1.0 emitted a deprecation warning; 2.1.1 removes it.) |
| 3.0.0 | `InkStory` moves to its own product and is **deprecated**: compiling against it emits a warning, not an error. The `InkSwift` product becomes the native runtime. |
| 4.0.0 | `InkStory` is **removed**. |

If you have opted into warnings-as-errors and need to stay on the bridge in 3.x for a gap
above, scope the suppression narrowly to the `InkStory` call sites rather than disabling
the setting globally.

## See also

- [Supported parity & known gaps](../reference/js-bridge-vs-native-parity.md)
- [Ink feature reference (construct-gap SSOT)](../product/ink-feature-reference.md)
