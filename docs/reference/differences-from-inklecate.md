# How InkSwift differs from inklecate

> **Reference (Diataxis).** What changes when you compile and play a story with
> InkSwift instead of inkle's own tools (inklecate, Inky, and the C# or inkjs
> runtime). Read it to understand why a story behaves differently, and whether you can
> work around it by compiling with inklecate.

InkSwift has two independent halves, and a story can go through either or both:

| | Native compiler | Native runtime |
|---|---|---|
| What it does | Turns `.ink` source into a story | Plays a compiled story |
| API | `InkCompiler.compile(source:)` | `Story(blueprint:)`, `Story(json:)` |
| inkle's equivalent | inklecate (and Inky's export) | the C# runtime / inkjs |
| When it runs | Compile time, in your app or build | Runtime, while the player reads |

That gives two ways to load a story:

```swift
// 1. Native compile: .ink source → InkSwift's compiler → InkSwift's runtime
let story = Story(blueprint: try InkCompiler.compile(source: inkSource))

// 2. inklecate compile: .ink → inklecate (or Inky: File → Export to JSON) → InkSwift's runtime
let story = try Story(json: inkJSON)
```

Both paths end in the **same runtime**. So:

- A **compile-time difference** affects only path 1. Compiling with inklecate and loading
  the `.ink.json` (path 2) avoids it.
- A **runtime difference** affects both paths. Compiling with inklecate does not help.

## The workaround: compile with inklecate

If the native compiler rejects your story, or the story plays differently from Inky,
compile it with inklecate and load the JSON:

```
inklecate -o story.ink.json story.ink
```

```swift
let json = try String(contentsOf: Bundle.main.url(forResource: "story", withExtension: "ink.json")!, encoding: .utf8)
let story = try Story(json: json)
```

If the story now plays correctly, the difference was in the compiler and this is your
workaround. If it still plays differently, the difference is in the runtime. Check
[Runtime differences](#runtime-differences), and consider the JS-bridge (`InkStory`) for
that story (see [JS-bridge vs native parity](js-bridge-vs-native-parity.md)).

## At a glance

Each row but the last was checked against inklecate 1.2.1: once compiled natively, and
once by playing inklecate's `.ink.json` on the native runtime. The last row comes from
the feature reference.

| Construct | Native compiler | Native runtime, inklecate JSON | What to do |
|---|---|---|---|
| `INCLUDE other.ink` | Rejected | ✅ Works | Compile with inklecate |
| String with inline logic: `~ return "value {n}"` | Rejected | ✅ Works | Compile with inklecate |
| Tag with inline logic: `Line. # pic{n}.jpg` | Rejected | ✅ Works¹ | Compile with inklecate |
| Tag inside inline logic: `{met: Hi # greeting}`, `{A # t\|B}` | Rejected | ✅ Works¹ | Compile with inklecate |
| A conditional inside a function body | Compiles, **plays wrong** | ✅ Works | Compile with inklecate |
| Multi-line sequences: `{stopping:` … `}`, `{cycle:` … `}` | Rejected | ❌ **Plays wrong** (repeats an item) | Use the inline forms (`{a\|b}`, `{&a\|b}`, `{!a\|b}`), or the JS-bridge |
| Shuffle: `{~a\|b}` | Rejected | ❌ Plays nothing, no error | JS-bridge |
| `LIST`, `RANDOM` / `SEED_RANDOM`, threads (`<-`), `EXTERNAL` | Rejected | ❌ Not supported | JS-bridge |

¹ A line's tags currently stay in `currentTags` for later lines until the next choice,
for every tag ([#30](https://github.com/maartene/InkSwift/issues/30), a runtime
difference).

The authoritative construct list, including everything that *is* supported, is the
[Ink feature reference](../product/ink-feature-reference.md).

## Compile-time differences

These affect only `InkCompiler.compile(source:)`.

### Constructs the native compiler rejects

The native compiler never knowingly builds a wrong story. When it meets a construct it
cannot compile, it throws a `CompileError` with `kind == .unsupportedConstruct`, the
construct's name, and the line and column where it starts:

```swift
do {
    let story = Story(blueprint: try InkCompiler.compile(source: inkSource))
} catch let error as CompileError where error.kind == .unsupportedConstruct {
    print("\(error.construct ?? "?") at \(error.line):\(error.column): \(error.message)")
    // e.g. "tag with inline logic at 2:7: A tag with inline logic is not supported by the native compiler yet."
}
```

| Construct | Example | Plays from inklecate JSON? |
|---|---|---|
| `INCLUDE` | `INCLUDE chapter_two.ink` | Yes |
| String with inline logic | `~ temp label = "value {n}"`, `{f("a{n}")}` | Yes |
| Tag with inline logic | `Line. # pic{n}.jpg`, `# {a\|b}` | Yes¹ |
| Tag inside inline logic | `{met: Hi # greeting}`, `{A # t\|B}` | Yes¹ |
| Multi-line sequence | `{stopping:` / `- Halt!` / `- I said halt!` / `}` | No, see [Runtime differences](#runtime-differences) |
| Shuffle | `{~heads\|tails}` | No |
| `LIST`, `RANDOM`, threads, `EXTERNAL` | `LIST colours = red, green` | No |

What is *not* rejected:

- Quotes in prose are text: `She said "hi {n}".` compiles and interpolates `{n}`.
- An escaped brace or hash is not logic: `Line # a\{b\}` compiles. (The escapes
  currently keep their backslash in the native compile, where inklecate drops it.)
- A tag on its own line inside a block conditional's branch compiles normally.

### Stories the native compiler builds differently

A few shapes compile without an error but play differently from inklecate. The known
ones are in [Native compiler known gaps](native-compiler-known-gaps.md), each with a
reproduction:

- a conditional inside a function body (output after the call is lost, or the function
  prints nothing);
- a block conditional before a choice in the same branch (the text after the block is
  dropped).

ink's own test suite finds a few more, such as a tunnel call in the middle of a line, or
a divert after choice text being kept as text. Each is a disabled test in
`Tests/SwiftInkRuntimeTests/Conformance/` named after the gap. In every one of these
cases, inklecate's JSON plays correctly on the native runtime.

### Errors and warnings

- The native compiler **stops at the first error**. inklecate reports all of them.
- Its **messages differ** from inklecate's.
- It reports **no warnings** (inklecate warns about, for example, an apparent loose end).
- It **accepts some stories inklecate rejects**. Examples: a name used twice for
  different things, an unresolved variable, a string constant containing `#`.

If you rely on inklecate's checks, run inklecate over your stories in CI even when you
ship with the native compiler.

## Runtime differences

These affect both paths. Compiling with inklecate does not avoid them.

### Not supported

| Feature | What happens |
|---|---|
| `LIST` | Not supported |
| Threads (`<-`) | Not supported |
| `RANDOM`, `SEED_RANDOM`, shuffle `{~a\|b}` | Not supported; a shuffle plays nothing, with no error |
| `EXTERNAL` functions | No host binding API |
| Multi-line sequences | Play the wrong item: `{stopping:` gives *First, First, Second* where inklecate gives *First, Second, Second* |

The inline sequence forms (`{a|b}`, `{&a|b}`, `{!a|b}`) are supported by both halves.

### Behaviour that differs

Known places where the same compiled story plays differently on InkSwift's runtime:

- A line's **tags stay in `currentTags`** for later lines until the next choice
  ([#30](https://github.com/maartene/InkSwift/issues/30)).
- **Running out of content** (a missing `->->`, `~ return` or `-> END`) ends the story
  silently; inkle's runtime reports an error
  ([#28](https://github.com/maartene/InkSwift/issues/28)).
- **`-> END` does not discard pending choices**, so a choice generated before the story
  ends can still be offered (see [Native compiler known gaps](native-compiler-known-gaps.md)).
- **Default (fallback) choices**, `TURNS()` and `TURNS_SINCE`, a tunnel onwards with a
  divert (`->-> target`), and `FLOOR` / `INT` / `CEILING` differ in some cases.

For the complete, current list, run this from a checkout of InkSwift. Reasons naming
the runtime show up for both paths:

```
grep -rho 'conformance: [^"]*' Tests/SwiftInkRuntimeTests/Conformance | sort | uniq -c | sort -rn
```

### API differences

The native `Story` API is not a copy of inkle's C# API:

- **Tags** are `[String]`.
- **Not available:** evaluating a function from the host (`EvaluateFunction`), binding
  external functions, variable observers, multiple parallel flows, and reading the tags
  of a knot without playing it (`TagsForContentAtPath`).
- **Errors** in the story itself are reported in `Story.currentErrors` and stop the
  story. Misuse of the API (an invalid choice index, an unknown knot) throws from the
  call instead.

## See also

- [Ink feature reference](../product/ink-feature-reference.md): every construct, and
  whether it compiles or is rejected
- [Native compiler known gaps](native-compiler-known-gaps.md): reproductions for the
  known compile-time and runtime defects
- [JS-bridge vs native parity](js-bridge-vs-native-parity.md): what the legacy
  JS-bridge (`InkStory`) still covers that the native runtime does not
