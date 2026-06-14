# Journey (visual): Compile an Ink Story in Pure Swift

**Feature**: native-ink-compiler
**Persona**: Maarten — Swift app developer embedding Ink stories
**Job**: job-native-compilation
**Created**: 2026-06-14

> DISCUSS scope: this describes what the developer does and observes — intent and
> behaviour only. No method signatures, type names, or access modifiers (those are
> DESIGN concerns). The "compile entry point" is a conceptual driving port, not a
> Swift API.

## Emotional Arc — Problem Relief + Confidence Building

```
Start: dependent / wary        Middle: focused / testing         End: confident / self-sufficient
"My runtime is Swift but        "Does the native output really     "One Swift toolchain, compile
 my build still needs the        match inklecate? What happens       to run. Unsupported features
 inklecate binary."              if I use something unsupported?"     fail loud, not silent."
```

## Happy Path Flow

```
[Trigger: I have a .ink story    -> [Compile in-process]   -> [Get a runnable story]  -> [Play it]            -> [Goal: ship]
 and want to run it without          (the compile entry         (story object the          (runtime emits the      "Whole pipeline is
 the external inklecate binary]       point, in pure Swift)      runtime plays directly)    same text inklecate      pure Swift, end to end"
                                                                                            would have produced)
  Feels: dependent / wary            Feels: hopeful              Feels: watching closely    Feels: reassured        Feels: confident
  Sees: a .ink file                  Sees: compile starts,      Sees: a ready-to-play      Sees: story text /       Sees: no inklecate
                                      no external process        story, no JSON round-trip   choices, identical       in the build
                                                                                            to the oracle
```

## Sad / Error Path — Unsupported Feature (fail loud, never silent)

```
[Trigger: my .ink uses a       -> [Compile in-process]   -> [Compile STOPS]         -> [I read the error]     -> [I fix or scope down]
 feature the runtime can't          (the compile entry         with a clear, located       "Threads are not          "Now I know exactly
 play — e.g. a LIST, a thread,       point)                     error naming the            supported at line 42"      what's in bounds"
 a {a|b|c} sequence]                                            unsupported construct
  Feels: about to ship            Feels: normal               Feels: caught early        Feels: informed,          Feels: in control
                                                                (relief, not dread)        not blocked blind
  Sees: a .ink file              Sees: compile runs          Sees: a named construct,    Sees: construct name      Sees: the supported-
                                                              a source location, and       + location + (ideally)    feature reference doc
                                                              a "not supported" reason     a pointer to the doc
```

## The Documentation Deliverable (a first-class artifact, not a side note)

```
[Trigger: I'm about to author   -> [Open the supported/    -> [I author within bounds] -> [Goal: no surprises]
 a new story and want to stay        unsupported feature        knowing every construct      "I never discover an
 inside the runtime's bounds]        reference]                  I use is playable            unsupported feature
                                                                                              by accident"
  Feels: uncertain                Feels: oriented            Feels: deliberate           Feels: confident
  Sees: the feature matrix        Sees: a clear MUST-        Sees: my story uses only    Sees: a story that
  (supported vs rejected)          COMPILE / MUST-REJECT      supported features           compiles first try
                                   table with examples
```

## Walking Skeleton (Feature-0, thinnest end-to-end slice)

```
+-- Walking Skeleton: single line of plain text ----------------------------------+
| Source (.ink):   Hello, world.                                                   |
|                                                                                  |
|   [read .ink] -> [parse] -> [codegen] -> [runnable story] -> [runtime plays it]  |
|                                                                                  |
| Observed:        the runtime emits exactly:  Hello, world.                       |
| Oracle check:    inklecate compiles the same source; runtime plays both;         |
|                  the emitted text is identical line-for-line.                     |
|                                                                                  |
| Learning hypothesis: DISPROVES "the read->parse->codegen->runtime-consumable     |
| ->execute pipeline can be wired end to end in pure Swift" if this line cannot    |
| be compiled and played to match the oracle.                                      |
+----------------------------------------------------------------------------------+
```

This single line exercises every stage of the pipeline on the smallest possible
input. It does not prove any individual language feature beyond plain text — that
is deliberate. It proves the *spine*.

## Shared Artifacts (tracked across the journey — see registry)

| Artifact | Single source of truth | Appears in |
|---|---|---|
| Supported feature set | The runtime's Feature Coverage Matrix (`brief.md` rows 1-35 supported) | compiler scope, reject-list, the feature reference doc, error messages |
| Unsupported feature set | Same matrix (rows 25-28, 36-39 unsupported) | reject behaviour, the feature reference doc, error messages |
| inklecate oracle output | `inklecate` binary at `/Users/Maarten.Engels/.local/bin/inklecate` | every execution-equivalence acceptance test |
| Compiled story shape | The shape the SwiftInkRuntime Story already consumes (owned by the runtime) | compile output, runtime input |
| Ink JSON format | Owned by the Ink C# runtime serialiser (`JsonSerialisation.cs`) | secondary JSON output, oracle structural comparison |

## Integration Checkpoints

1. **Compile -> runtime hand-off**: the compiled story must be directly consumable
   by the existing runtime with no JSON round-trip. The compiled-story shape is the
   integration contract; the runtime owns it.
2. **Compiler scope == runtime scope**: the set of features the compiler accepts
   must be exactly the set the runtime can play. Any drift is an integration bug —
   the compiler would accept something the runtime mis-plays, or reject something
   the runtime supports.
3. **Compile-time work the runtime assumes inklecate already did**: CONST inlining
   (matrix row 17) and choice-flag / invisible-default encoding (row 10). The runtime
   does NOT do these; the compiler must, or supported stories will mis-play.
4. **Oracle parity**: for supported stories, native output played through the runtime
   must equal inklecate-compiled output played through the runtime, line-for-line.
