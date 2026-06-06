# Journey Visual — Developer Using SwiftInkRuntime (Tier 3)

**Persona**: Ava (Swift game developer integrating `SwiftInkRuntime` into a narrative game)
**Goal**: Play an Ink story that uses conditional text, functions, and tunnels — and have it produce the same output as the JS-bridge reference.
**Emotional arc**: Productive confidence → brief uncertainty at API boundaries → relief at test-green confirmation

---

## ASCII Flow

```
[Author writes Ink]  →  [Compile with inklecate]  →  [Drive Story API]  →  [Assert output matches oracle]
       |                         |                          |                          |
 Conditional text          .ink.json ready            story.continue()          Tests pass (green)
 Functions                                             story.currentText          Story matches JS bridge
 Tunnels                                               story.currentChoices
 Ref params
```

### Emotional Annotations

```
[Author writes Ink]         Confident — Ink syntax is familiar
       ↓
[Compile with inklecate]    Neutral — mechanical step, always works
       ↓
[Drive Story API]           Slightly uncertain — "Will the engine handle this?"
       ↓
[Assert output matches]     Relief → confidence — "Green. Same output as inkjs."
```

---

## Step-by-Step Journey

### Step 1 — Write Ink source with Tier 3 features

Ava writes an `.ink` file using:
- Inline conditional text: `{visited_café > 0: You remember the smell.|You're here for the first time.}`
- Block conditionals: `{ score > 10: You passed.\n- else: You failed. }`
- Switch-style conditionals: `{ outcome:\n- 1: Arrested.\n- 2: Escaped.\n- else: Unknown. }`
- Ink functions: `=== function greet(name) ===` called as `{greet("Cass")}`
- Tunnels: `-> question_room ->`
- Reference params: `=== function add(ref total, n) ===`

**Emotional state**: Confident — Ink syntax is well-known; the author knows what the story *should* do.

---

### Step 2 — Compile with inklecate

```
/Users/maartene/Downloads/inklecate_mac/inklecate -o story.ink.json story.ink
```

Ava gets a `.ink.json` file. This is the actual compiler output — the test fixture.

**Shared artifact**: `story.ink.json` → single source of truth for all test assertions.

**Emotional state**: Neutral, mechanical.

---

### Step 3 — Drive the Story API

Ava writes a Swift test or host-app snippet:

```
let story = try Story(json: data)

// Conditional text scenario
let text = story.continue()
// → expect: "You're here for the first time."

// Function call scenario
let greeting = story.continue()
// → expect: "Hello, Cass."

// Tunnel scenario — story enters sub-knot, executes, returns
story.continue()  // enters tunnel
story.continue()  // exits tunnel, continues main flow
```

**Entry feeling**: Slightly uncertain — "Has the engine wired up the conditional evaluator?"
**Exit feeling**: Relief — `currentText` matches expected output.

---

### Step 4 — Assert Output Matches Oracle

```
// Oracle pattern (existing infrastructure from Tier 1)
let oracle = try InkStory(json: data)      // JS bridge
let native = try Story(json: data)          // SwiftInkRuntime

while oracle.canContinue {
    XCTAssertEqual(native.continue(), oracle.continue())
}
XCTAssertEqual(native.currentChoices.map(\.text),
               oracle.currentChoices.map(\.text))
```

**Exit feeling**: Confident. Green tests confirm The Intercept ceiling is within reach.

---

## Error Paths

### E1 — Conditional falls through to wrong branch
- Symptom: `currentText` contains wrong branch text (else when condition was true)
- Recovery: inspect `evalStack` at conditional entry point; verify `ev`/`/ev` block produces correct boolean

### E2 — Function returns void instead of value
- Symptom: `currentText` contains `"void"` literal or empty string where function result expected
- Recovery: verify `~ret` handling pops the callstack correctly and `"void"` node is suppressed from output

### E3 — Tunnel does not return
- Symptom: story hangs in the tunnel knot; `canContinue` stays true but progress stops
- Recovery: verify `->t->` divert pushes return address onto `returnStack` and `->->` pops it correctly

### E4 — Reference parameter not updated in caller scope
- Symptom: caller's variable unchanged after function mutates `ref` parameter
- Recovery: verify `{"^var": "name", "ci": N}` variable pointer resolves to the correct callstack frame

### E5 — Save/restore drops conditional or function state
- Symptom: restored story produces different conditional branch than in-memory run
- Recovery: verify new `StoryState` fields use `decodeIfPresent` with correct defaults

---

## Shared Artifacts

| Artifact | Source of Truth | Consumers |
|---|---|---|
| `story.ink.json` | inklecate compiler output | Test fixtures in `SwiftInkRuntimeTests` |
| `Story.currentText` | `SwiftInkRuntime.Story` facade | All acceptance tests |
| `Story.currentChoices` | `SwiftInkRuntime.Story` facade | Choice-related acceptance tests |
| `InkStory` (oracle) | `InkSwift` module (frozen) | Integration tests comparing output |
| `StoryState` (Codable) | `SwiftInkRuntime.StoryState` | Save/restore acceptance tests |
