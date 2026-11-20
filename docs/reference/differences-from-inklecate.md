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

Each row was checked against inklecate 1.2.1: once compiled natively, and once by
playing inklecate's `.ink.json` on the native runtime.

| Construct | Native compiler | Native runtime, inklecate JSON | What to do |
|---|---|---|---|
| `INCLUDE other.ink` | Rejected | ✅ Works | Compile with inklecate |
| String with inline logic: `~ return "value {n}"` | Rejected | ✅ Works | Compile with inklecate |
| Tag with inline logic: `Line. # pic{n}.jpg` | Rejected | ✅ Works | Compile with inklecate |
| Tag inside inline logic: `{met: Hi # greeting}`, `{A # t\|B}` | Rejected | ✅ Works | Compile with inklecate |
| A conditional inside a function body | Compiles, **plays wrong** | ✅ Works | Compile with inklecate |
| Multi-line sequences: `{stopping:` … `}`, `{cycle:` … `}` | Rejected | ✅ Works | Compile with inklecate, or use the inline forms (`{a\|b}`, `{&a\|b}`, `{!a\|b}`) |
| Shuffle: `{~a\|b}` | Rejected | ❌ Refused at load | JS-bridge |
| `LIST`, `RANDOM()`, threads (`<-`), `EXTERNAL` | Rejected | ❌ Refused at load | JS-bridge |
| `TURNS()`, `TURNS_SINCE()`, `CHOICE_COUNT()`, `READ_COUNT()` | Rejected | ❌ Refused at load | JS-bridge, or avoid the function |
| `SEED_RANDOM()` | ✅ Works (no observable effect) | ✅ Works (no observable effect) | — |
| `POW()`, string `?` / `!?` (also `has` / `hasnt`) | ✅ Works | ✅ Works | — (on lists they need `LIST`, which is refused) |

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
| Tag with inline logic | `Line. # pic{n}.jpg`, `# {a\|b}` | Yes |
| Tag inside inline logic | `{met: Hi # greeting}`, `{A # t\|B}` | Yes |
| Multi-line sequence | `{stopping:` / `- Halt!` / `- I said halt!` / `}` | Yes |
| Shuffle | `{~heads\|tails}` | No |
| `LIST`, `RANDOM()`, threads, `EXTERNAL` | `LIST colours = red, green` | No |
| `TURNS()`, `TURNS_SINCE()`, `CHOICE_COUNT()`, `READ_COUNT()` | `{TURNS_SINCE(-> shop)}` | No |

A construct the runtime also refuses is named exactly as the runtime names it when it
refuses inklecate's JSON (see [Not supported: refused at
load](#not-supported-refused-at-load)), so a host sees one vocabulary on both paths:
`"RANDOM()"`, `"LIST"`, `"threads (<-)"`, `"EXTERNAL functions"`, `"shuffle {~a|b}"`,
`"TURNS_SINCE()"` and so on. `INCLUDE` is named `"INCLUDE"`. These strings changed in
2.x: earlier releases used `"random"`, `"list"`, `"thread"`, `"external"`, `"include"` and
`"shuffle"`.

What is *not* rejected:

- Quotes in prose are text: `She said "hi {n}".` compiles and interpolates `{n}`.
- An escaped brace or hash is not logic: `Line # a\{b\}` compiles, and prints the tag
  `a{b}` as inklecate does.
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
  A loose end still behaves the same on both paths: like inklecate, the native compiler
  ends only the top-level flow with `-> DONE`, so a knot or stitch whose flow runs out
  (including one whose choices are all used up) runs out of content on both paths.
- It **accepts some stories inklecate rejects**. Examples: a name used twice for
  different things, an unresolved variable, a string constant containing `#`.
- A **function call** is checked as inklecate checks it. A call to a name that is
  neither a story function nor a built-in (`{nosuchfunction(1.5)}`, `~ gret()` when the
  function is `greet`) is a `CompileError` of kind `.unresolvedReference` with inklecate's
  message, `Function call target not found: '-> nosuchfunction'`, at the call's line. A
  built-in called with the wrong number of arguments is a `.syntaxError` with inklecate's
  message, such as `FLOOR should take 1 parameter`. `FLOOR()`, `CEILING()`, `INT()`,
  `FLOAT()`, `MIN()` and `MAX()` compile to the runtime's built-ins and print what
  inklecate prints.

If you rely on inklecate's checks, run inklecate over your stories in CI even when you
ship with the native compiler.

## Runtime differences

These affect both paths. Compiling with inklecate does not avoid them.

### Not supported: refused at load

`Story(json:)` checks the whole story when it loads, including knots no playthrough
reaches. If the story uses a feature the runtime does not support, it throws
`StoryError.unsupportedFeatures`, listing every such feature and where the story uses it,
so you find out during development, not from a player:

```swift
do {
    let story = try Story(json: json)
} catch StoryError.unsupportedFeatures(let features) {
    for feature in features {
        print("\(feature.name) in \(feature.locations)")
        // e.g. "RANDOM() in [\"never_visited\", \"shop.haggle\"]"; "" is the top level
    }
}
```

| Feature | Reported as |
|---|---|
| `LIST` (values, list functions, `LIST_RANDOM`) | `LIST` |
| Threads | `threads (<-)` |
| `RANDOM()` | `RANDOM()` |
| Shuffle | `shuffle {~a\|b}` |
| `EXTERNAL` function calls (there is no host binding API) | `EXTERNAL functions` |
| `TURNS()`, `TURNS_SINCE()`, `CHOICE_COUNT()` | the function's name |
| `READ_COUNT()`, of a divert-target variable or a literal `-> knot` (a bare `{knot}` read count works) | `READ_COUNT() of a divert-target variable` |
| Tags in the old inkVersion 20 format | asks you to recompile with a current inklecate |

`SEED_RANDOM()` is accepted, on this path and by the native compiler. With every random
feature refused, a seed changes nothing a player can see. Like inklecate's runtime, it
leaves a void value for the discarded call to remove, so the evaluation stack stays
balanced.

### Behaviour that differs

Known places where the same compiled story plays differently on InkSwift's runtime:

- **Running out of content** (a missing `->->`, `~ return` or `-> END`) reports the same
  error as inkle's runtime in `currentErrors`
  ([#28](https://github.com/maartene/InkSwift/issues/28)), on both compile paths. The
  message has no `RUNTIME ERROR: (<location>):` prefix, and like every InkSwift runtime
  error it is never saved; `restoreState` and `moveToKnot` clear it.
- **Float arithmetic is 64-bit.** ink floats are 32-bit; InkSwift computes and stores
  them as `Double` (ADR-024) and only *prints* the 32-bit value. Printed floats match
  inklecate (`2`, `0.33333334`, `0.3`, `1E+20`, `1E-05`, `Infinity`, `NaN`), but
  comparisons and accumulated results can differ: `{0.1 + 0.2 == 0.3}` is `false` on
  InkSwift and `true` on inklecate; a value beyond 32-bit range (about 3.4E+38) stays
  finite in later arithmetic where inklecate's has already become `Infinity`; and
  `getVariable` returns the `Double` (`0.30000000000000004` for `0.1 + 0.2`).
  Floats always print with a `.` as decimal separator; inklecate's own player uses the
  machine's locale ([inkle/ink#916](https://github.com/inkle/ink/issues/916)).
- **Integer arithmetic is 64-bit and does not wrap.** ink integers are 32-bit and wrap
  on overflow; InkSwift's are Swift `Int` (64-bit). With `VAR x = 2147483647`,
  inklecate prints `-2147483648` for `{x + 1}` and `-2` for `{x * 2}`; InkSwift prints
  `2147483648` and `4294967294`. This is deliberate: a story that relies on 32-bit
  wrap-around is relying on an overflow, and InkSwift keeps the mathematically correct
  result instead. Only `INT()` of a float uses the 32-bit range, clamping to it as
  inklecate does. A result beyond the 64-bit range (about ±9.2E+18) is not wrapped
  either: Swift's overflow check stops the app, so a story must keep its integers within
  that range.
- **Glue before a tag stops after the glued line.** For `Text <> # t` followed by
  `glued.` and `After the glue.`, inklecate and inkjs print `Text glued.After the glue.`:
  they keep gluing until the next choice point. InkSwift prints `Text glued.` (tag `t`)
  and then `After the glue.`. This is a deliberate difference: the reference behaviour
  is the open upstream bug
  [inkle/ink#923](https://github.com/inkle/ink/issues/923), "Gluing a tag causes glue
  state to persist indefinitely", which InkSwift does not copy
  ([#43](https://github.com/maartene/InkSwift/issues/43)).
- **No warning for a variable that doesn't exist.** Reading a temp whose declaration
  was skipped (`{flag: ~ temp y = 1}` with `flag` false, then `{y}`) reads as the
  integer 0 on both paths, as in inkle's runtime. inkle's runtime also warns
  "Variable not found: 'y'. Using default value of 0 (false)…". InkSwift has no
  runtime warnings yet, so it says nothing
  ([#39](https://github.com/maartene/InkSwift/issues/39)).
- **Integer division by zero is a runtime error.** `{1 / z}` or `{7 % z}` with
  `VAR z = 0` crashes inklecate's player with an unhandled .NET
  `DivideByZeroException` (the open upstream issue
  [inkle/ink#843](https://github.com/inkle/ink/issues/843), unanswered since 2023), so
  there is no story behaviour to copy. InkSwift reports `Attempted to divide by zero.`
  in `currentErrors` and ends the flow, like any other runtime error
  ([#41](https://github.com/maartene/InkSwift/issues/41)). Float division follows IEEE
  on both: `{1.0 / z}` with `VAR z = 0.0` prints `Infinity`, `{0.0 / z}` prints `NaN`.
- **A short evaluation stack is a runtime error.** JSON in which an instruction finds no
  value to pop (inklecate never writes such JSON) reports `Evaluation stack is empty` in
  `currentErrors` and ends the flow, where inkle's runtime fails with an internal
  exception. That holds for every instruction that pops: an operator, an assignment,
  `out`, `pop`, `->->`, `SEED_RANDOM`, and the condition of a conditional divert or
  choice. `Story(json:)` accepts JSON from any source, so a
  malformed story must not crash the app hosting it
  ([#41](https://github.com/maartene/InkSwift/issues/41)).
- **Default (fallback) choices** differ in some cases.
- **A tunnel onwards override (`->-> target`) is not supported.** inklecate compiles
  it to `ev {"^->": "target"} /ev ->->`: the target is pushed as a value for `->->` to
  pop and follow. On the runtime path (path 2) InkSwift pops the target and ignores it,
  so play resumes at the tunnel's call site instead of at `target`. The native compiler
  doesn't recognise the form: the tunnel never returns, and the story stops with
  `unexpectedly reached end of content. Do you need a '->->' to return from a tunnel?`
  in `currentErrors`. Write a bare `->->` and divert from the call site instead.

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
- **Saves are InkSwift's own format and forward-only.** `saveState()` / `restoreState(_:)`
  do not read or write inkle's save JSON. A save from an older InkSwift build restores
  on a newer one: visit counts an older build stored under two spellings of the same
  container (its index and its name) are merged into one count
  ([#33](https://github.com/maartene/InkSwift/issues/33)), and a count for a knot or
  stitch the story no longer has is kept as it is. A save from a newer build is **not
  supported on an older build**: restored there, some visit counts read as 0, so
  sequence items and once-only content replay and loops run extra passes (ADR-022 §4).
  A save holding a void value (`"type":"void"`, a variable that stored the result of a
  function that returns nothing) can't be read at all by builds before 2.2.2, which
  saved that result as the string `"void"`. Such an older save restores on 2.2.2 and
  later as the string itself, so the variable prints `void` where it printed nothing
  ([#44](https://github.com/maartene/InkSwift/issues/44)).

## See also

- [Ink feature reference](../product/ink-feature-reference.md): every construct, and
  whether it compiles or is rejected
- [Native compiler known gaps](native-compiler-known-gaps.md): reproductions for the
  known compile-time and runtime defects
- [JS-bridge vs native parity](js-bridge-vs-native-parity.md): what the legacy
  JS-bridge (`InkStory`) still covers that the native runtime does not
