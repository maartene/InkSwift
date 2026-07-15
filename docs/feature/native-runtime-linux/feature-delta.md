<!-- markdownlint-disable MD024 -->
# Feature Delta — native-runtime-linux (DISCUSS)

> Single DISCUSS narrative. Tier-1 [REF] sections only (density = DISCUSS hard
> default: lean + ask-intelligent). Legacy split files (user-stories.md,
> story-map.md, acceptance-criteria.md, outcome-kpis.md) are intentionally NOT
> emitted — that content lives here.

**One-liner**: Make the pure-Swift `SwiftInkRuntime` (runtime + native compiler)
build, test, and run on **Linux**, producing output identical to macOS.

---

## Wave: DISCUSS / [REF] Persona

**New persona**: `nadia` — *Nadia, server-side Swift developer running Ink on Linux*
(`docs/product/personas/nadia.md`).

Distinct from `maarten` (Apple-platform app/toolchain owner). Nadia never ships to
an Apple platform: she runs Swift services and CI on Linux (containers, no Mac in
the loop) and wants to embed Ink server-side. She adopts SwiftInkRuntime precisely
because it has no JS engine and no external `inklecate` binary — the two things
hardest to ship in a Linux container. Single new persona → the ≥3-persona
multi-stakeholder ask-intelligent trigger does **not** fire.

---

## Wave: DISCUSS / [REF] JTBD

**New job**: `job-linux-portability` (added to `docs/product/jobs.yaml`, schema v3).

> When I run Swift services and CI on Linux and want to embed Ink stories
> server-side, I want the pure-Swift Ink runtime and compiler to build, test, and
> play identically on Linux as on macOS, so I can ship Ink-driven backends and run
> the whole test suite in my Linux CI without needing a Mac or a JavaScript engine.

**Four forces** (full detail in jobs.yaml):
- **Push**: pure-Swift runtime does not build/behave on Linux — `InkDecoder.classifyNumber`
  depends on CoreFoundation type identity that is unreliable under swift-corelibs-foundation;
  no Linux CI; no JS-bridge oracle on Linux.
- **Pull**: one codebase that builds, tests green, and plays/compiles identically on
  Linux and macOS; a committed-fixture oracle; Linux CI guarding parity.
- **Anxiety**: silent number/bool divergence (`2.5`→`2`, `true`→`1`) — a
  platform-specific correctness bug invisible on the Mac the fix is written on.
- **Habit**: "works on my Mac" as a proxy for "works everywhere"; live JS-bridge oracle.

**Opportunity score**: importance 9, satisfaction 2 → **16 (extreme, >15)**. The
runtime literally does not run for this persona today.

**Dimensions**:
- *Functional*: build/test/run + compile Ink on Linux; classify numbers portably; verify vs committed fixtures.
- *Emotional*: relief from platform-correctness anxiety; confidence a real 28-knot story is provably identical.
- *Social*: makes InkSwift a credible server-side / cross-platform Swift citizen; lets Linux-based teammates participate.

**Relation to existing jobs** (extends *reach*, not behaviour): `job-story-playback`
(RUN side, Maarten) and `job-native-compilation` (BUILD side, Maarten) become
correct on Linux for a new platform/audience.

---

## Wave: DISCUSS / [REF] Scope Assessment

**## Scope Assessment: PASS — 4 stories, 1 bounded context (SwiftInkRuntime), estimated 4 days**

Elephant-Carpaccio early gate (run before journey investment). Oversized signals checked:

| Signal | Threshold | This feature | Trip? |
|---|---|---|---|
| Story count | >10 | 4 | No |
| Bounded contexts / modules | >3 | 1 (`SwiftInkRuntime` + its TestSupport) | No |
| Walking-skeleton integration points | >5 | 2 (decoder classification, committed fixture) | No |
| Estimated effort | >2 weeks | ~4 days | No |
| Independent shippable outcomes | multiple | 1 coherent outcome (Linux parity), sliced thin | No |

Right-sized. No split required. The core fix is contained to the decoder's
number/bool classification + resource loading + a committed-fixture oracle + one
Linux CI job.

---

## Wave: DISCUSS / [REF] Out of Scope

- **The legacy `InkSwift` JS-bridge module** (JXKit + bundled `ink-full.js` + Combine).
  Inherently Apple-only; already conditionalized to `.macOS` in `Package.swift:67`.
  **Do not port it.** Linux CI simply does not build this target.
- **Changing the supported Ink feature set** — this feature is *parity only* (same
  behaviour, new platform), not new constructs.
- **Prescribing the portable-classification implementation** — DESIGN owns *how*
  (JSONDecoder vs manual token typing vs other). DISCUSS fixes only observable behaviour.
- **Deployment / container packaging / observability instrumentation** — DEVOPS
  wave (outcome KPIs below feed it).

---

## Wave: DISCUSS / [REF] Journey & Emotional Arc

Journey SSOT: `docs/product/journeys/linux-portability.yaml` (lightweight, Decision 3).

`clone → swift build → decode (numbers correct) → play/compile (fixture parity) → CI guards it`

Emotional arc (Problem Relief + Confidence Building):
**Skeptical** ("pure Swift, but will it build on Linux?") → **cautiously engaged**
(build compiles; first real fixture matches) → **confident/trusting** (full suite
green on Linux CI, parity guarded every push).

Minimal error paths (Decision 3): (1) missing/incompatible Swift toolchain on the
Linux host; (2) **CF-drift** — a float classified as int or `true` as `1`, so story
text diverges. Both have Gherkin in the journey SSOT.

---

## Wave: DISCUSS / [REF] Shared Artifacts

| Artifact | Source of truth | Consumers | Integration risk |
|---|---|---|---|
| `number-classification-behaviour` (int/float/bool node tags) | `InkDecoder` classification path | engine value rendering, variable print output, fixture diff | **HIGH** — divergence silently changes story text on Linux |
| `committed-fixture-oracle` (expected transcripts, captured on macOS ground truth) | `Tests/SwiftInkRuntimeTests/Fixtures` (committed golden files) | Linux runtime oracle, Linux compiler oracle, Linux CI | **HIGH** — the file the local suite diffs MUST be the same file CI runs |
| `swift-toolchain-version` | `Package.swift` swift-tools-version + Linux install | local build, Linux CI job | MEDIUM — version skew can change behaviour |
| `Bundle.module` resource (`test.ink.json`) | `Sources/SwiftInkRuntime` resources (`Package.swift:54-56`) | `InkDecoder.probe()`, runtime tests | MEDIUM — SPM resource resolution on Linux needs verification |

Integration checkpoint: the committed fixture is captured **once on macOS** (the
trusted ground truth) and is the single source both the Linux local suite and the
Linux CI job diff against — no per-platform regeneration.

---

## Wave: DISCUSS / [REF] Story Map & Walking Skeleton

**Backbone** (Nadia's activities, left→right):

| Build on Linux | Decode with correct types | Play & compile a real story | Guard parity in CI |
|---|---|---|---|
| `swift build` green | portable number/bool classify | runtime + compiler fixture parity | Linux `swift test` CI job |

**Walking skeleton (Slice 01 / US-01)**: make `InkDecoder` classify numbers/booleans
correctly on Linux and prove one real story decodes with node types identical to a
committed macOS fixture. This is the riskiest assumption — if it fails, nothing
else can. It touches every downstream activity (all playback/compile output depends
on correct value typing).

**Release slices** (each ≤1 day, end-to-end, outcome-named; briefs in `slices/`):

1. **Slice 01 — Portable number classification** (WS) → US-01. Outcome: numbers/bools identical on Linux.
2. **Slice 02 — Play a real story on Linux** → US-02. Outcome: runtime transcript parity + resources resolve.
3. **Slice 03 — Compile a real .ink on Linux** → US-03. Outcome: in-process compiler parity.
4. **Slice 04 — Linux CI guards parity** → US-04. Outcome: continuous Linux verification.

### Priority Rationale

Priority = walking-skeleton-first, then riskiest-assumption, then reach:
**S01 first** (validates the fatal CF-drift assumption; blocks all others).
**S02 second** (delivers the primary RUN-side value — Nadia can embed the runtime
in a Linux service the moment this lands, before the compiler path). **S03 third**
(extends the BUILD-side toolchain reach; lower urgency because compiling can be
done on macOS as a fallback while runtime cannot). **S04 last** (needs a green
Linux suite to exist before it can guard one). Value×Urgency/Effort keeps this
order — S01/S02 are highest value and unblock everything.

---

## Wave: DISCUSS / [REF] Driving Ports

The observable surfaces every Elevator Pitch "After" line references (all exist today):

- `swift build` and `swift test` executed **on Linux** — observable: build succeeds / suite green.
- `StoryBlueprint(json:)` + `Story` facade playback (`continue()`, `chooseChoice(at:)`,
  `continueMaximally()`) — observable: rendered story text + choices on Linux.
- `InkCompiler.compile(source:) -> StoryBlueprint` — observable: compiled story's played text/choices.
- `git push` → `.forgejo/workflows/tests.yml` Linux job — observable: green/red CI status.

---

## Wave: DISCUSS / [REF] System Constraints

Cross-cutting constraints inherited by DISTILL/DELIVER (recorded from CLAUDE.md):

- **Swift Testing backtick style is mandatory**; string-label `@Test("…")` forbidden.
  `.disabled("…")` reasons are traits, not display names.
- **Trunk-based dev**: every DELIVER step commits to `main` green. New ATs authored
  `.disabled(...)` until their DELIVER step re-enables; **zero `.disabled` ATs at finalize**.
- **Mutation testing disabled** project-wide. Test quality = **execution-equivalence
  oracle suite** (line-for-line / choice-for-choice), code review, CI boundary gates.
  Frame test-quality KPIs around the oracle suite, never mutation kill-rate.
- **Oracle strategy on Linux** = committed-fixture oracle (golden files captured on
  macOS), NOT the macOS-only live JS-bridge comparison.
- Paradigm: object-oriented / imperative (value-type structs + enums with mutating
  methods, e.g. `InkDecoder`).
- **Guardrail**: the existing macOS suite (incl. JS-bridge path) must remain green —
  no Apple-platform regression.

---

## Wave: DISCUSS / [REF] User Stories

All stories trace to `job_id: job-linux-portability`. None are `@infrastructure`
(each enables a real Nadia decision and references a real driving port).

### US-01 — A real story's numbers keep their type on Linux (Walking Skeleton)

**job_id**: job-linux-portability · **Slice**: 01 · **MoSCoW**: Must

#### Elevator Pitch
- **Before**: On Linux, `swift build` fails on CoreFoundation number handling; even
  if patched, a float could silently classify as an int and `true` as `1`.
- **After**: On Linux, `swift test` decodes a real story and a `2.5` float variable
  renders `2.5`, a `true` boolean renders `true`, and a `2` int renders `2` — the
  decoded node types match the committed macOS fixture exactly.
- **Decision enabled**: Nadia can *trust that story values behave identically on Linux*
  and safely build playback/compilation on top.

#### Problem
Nadia is a server-side Swift developer who wants to run Ink on Linux. She finds it
blocking that `InkDecoder.classifyNumber` uses CoreFoundation type identity
(`CFGetTypeID`/`CFBooleanGetTypeID`/`CFNumberGetType`), which is unreliable under
swift-corelibs-foundation — so a story's floats, ints, and booleans can silently
misclassify on Linux and she cannot even get the package to build correctly.

#### Who
- Nadia (server-side Swift dev) | Linux host, no Mac | wants trustworthy value typing before building further.

#### Solution
Classify JSON numbers and booleans through a path whose int/float/bool result is
identical on Linux and macOS, verified by decoding a real story against a committed
macOS-captured fixture. (DESIGN chooses the portable mechanism.)

#### Domain Examples
1. **Float preserved** — A story with `VAR health = 2.5`; on Linux the decoded value
   is a float and renders `Health: 2.5` (never `2`), matching the macOS fixture.
2. **Boolean preserved** — A story with `VAR alive = true`; on Linux `{alive: You live.}`
   evaluates the boolean and renders `You live.`; a raw `{alive}` renders `true` (never `1`).
3. **Int preserved (boundary)** — The Intercept's integer variables (of its 21) decode as
   ints and render without a decimal point, identical to the committed macOS fixture.

#### UAT Scenarios (BDD)
```gherkin
Scenario: Float and boolean values keep their type on Linux
  Given an Ink story declares "VAR health = 2.5" and "VAR alive = true"
  And the committed macOS fixture renders "Health 2.5, alive true"
  When the story is decoded and played on Linux via "swift test"
  Then the float variable renders "2.5" and never "2"
  And the boolean variable renders "true" and never "1"

Scenario: A real story's integer variables stay integers on Linux
  Given The Intercept's committed macOS decode fixture
  When The Intercept JSON is decoded on Linux
  Then every integer variable classifies as an integer node
  And zero numbers misclassify as float or bool versus the fixture

Scenario: The runtime target builds on Linux
  Given a Linux host with a supported Swift toolchain
  When Nadia runs "swift build"
  Then SwiftInkRuntime compiles with no CoreFoundation-related errors
```

#### Acceptance Criteria
- [ ] `swift build` succeeds for `SwiftInkRuntime` + `SwiftInkRuntimeTestSupport` on Linux.
- [ ] Decoding the committed fixture story on Linux yields int/float/bool node tags identical to the macOS fixture (zero misclassifications).
- [ ] A played float renders with its decimal (`2.5`), a bool renders `true`/`false`, on Linux — matching the fixture transcript.

#### Outcome KPIs (link)
KPI-1 (build+suite green on Linux), KPI-3 (zero misclassifications). See KPI section.

#### Technical Notes
- Root cause anchored at `Sources/SwiftInkRuntime/Decoder/InkDecoder.swift:123-138`
  (`classifyNumber`) and the `as? NSNumber` path in `decode(_:)` (lines 24-36).
- **Open for DESIGN**: portable classification approach (do NOT prescribe here).
- Dependency: none (this is the walking skeleton; unblocks US-02/03/04).

---

### US-02 — A real story plays identically on Linux (runtime)

**job_id**: job-linux-portability · **Slice**: 02 · **MoSCoW**: Must · **Depends on**: US-01

#### Elevator Pitch
- **Before**: There is no way to play an Ink story on Linux — the package doesn't
  build, and SPM resource loading (`Bundle.module`) is unverified there.
- **After**: On Linux, `swift test` plays The Intercept through the `Story` facade
  and the full transcript — every line of narrative and every choice — is identical
  to the committed macOS fixture.
- **Decision enabled**: Nadia can *embed the runtime in a Linux service* and ship
  Ink-driven backends without a Mac.

#### Problem
Nadia is a server-side Swift developer who wants to run Ink stories inside a Linux
service. She finds it impossible to play any story on Linux today, and even a
patched build depends on `Bundle.module` resources and Foundation error handling
resolving correctly under swift-corelibs-foundation.

#### Who
- Nadia | embedding the runtime in a Linux service/container | needs full-story playback parity.

#### Solution
Play a real committed story end-to-end on Linux via `StoryBlueprint(json:)` + `Story`,
resolve `Bundle.module` resources on Linux (`probe()` succeeds), and verify the whole
transcript against the committed-fixture oracle.

#### Domain Examples
1. **Full playthrough** — The Intercept (28 knots) plays on Linux; its complete
   text-and-choice transcript equals the committed macOS fixture line-for-line.
2. **Choice parity** — At a branch offering "Tell the truth" / "Lie", both choices
   appear in the same order with the same text on Linux as on macOS.
3. **Resource loading (boundary)** — `InkDecoder.probe()` loads `test.ink.json` via
   `Bundle.module` on Linux and the probe succeeds (no `decoderProbeFailure`).

#### UAT Scenarios (BDD)
```gherkin
Scenario: A real story plays identically on Linux
  Given The Intercept's committed macOS playthrough fixture
  When Nadia plays The Intercept on Linux via "swift test"
  Then the narrative text matches the fixture line-for-line
  And every choice matches the fixture choice-for-choice

Scenario: Bundled resources resolve on Linux
  Given the SwiftInkRuntime resource bundle contains test.ink.json
  When the decoder probe runs on Linux
  Then the resource loads via Bundle.module and the probe succeeds

Scenario: An unplayable story still fails cleanly on Linux
  Given a malformed Ink JSON input
  When it is loaded on Linux
  Then a StoryError is raised with a readable reason (no crash, no silent success)
```

#### Acceptance Criteria
- [ ] The Intercept transcript (all text + all choices) on Linux equals the committed macOS fixture.
- [ ] `Bundle.module` resources resolve on Linux; `probe()` succeeds.
- [ ] Malformed input surfaces a `StoryError` with a readable reason on Linux (no crash).

#### Outcome KPIs (link)
KPI-1 (suite green), KPI-2 (fixture-corpus transcript parity).

#### Technical Notes
- Touches `StoryBlueprint.swift:24` (`error.localizedDescription`) and `Bundle.module`
  resource path (`Package.swift:54-56`).
- Verification runs against **committed fixtures**, not the macOS JS-bridge (see constraints).
- Dependency: US-01.

---

### US-03 — A real .ink compiles in-process on Linux (compiler)

**job_id**: job-linux-portability · **Slice**: 03 · **MoSCoW**: Should · **Depends on**: US-02

#### Elevator Pitch
- **Before**: On Linux, compiling `.ink` requires the external inklecate binary in
  the container, or is simply unavailable because the package doesn't build.
- **After**: On Linux, `InkCompiler.compile(source:)` turns a real `.ink` source into
  a `StoryBlueprint`, and playing it via `swift test` produces text and choices
  identical to the committed macOS fixture — with no inklecate binary present.
- **Decision enabled**: Nadia can *compile and run Ink entirely in-process on Linux*,
  removing the last external dependency from her container build.

#### Problem
Nadia wants a pure-Swift Ink toolchain in her Linux container. She finds it a
blocker that compilation would otherwise require installing the external inklecate
(C#) binary, and that the native compiler path has never been proven on Linux.

#### Who
- Nadia | containerized Linux build with no external binaries | needs in-process compile+run parity.

#### Solution
Compile a real supported-set `.ink` source string via `InkCompiler.compile(source:)`
on Linux, play the result, and diff the transcript against the committed macOS fixture.

#### Domain Examples
1. **Compile+play** — A supported knot/stitch/divert/glue/variable-interpolation
   `.ink` source compiles in-process on Linux and plays identically to the macOS fixture.
2. **No external binary** — The Linux container has no inklecate installed; compilation
   still succeeds fully in-process.
3. **Unsupported construct (boundary)** — A source using an unsupported construct raises
   a located, construct-named `CompileError` on Linux (identical failure to macOS; no silent wrong output).

#### UAT Scenarios (BDD)
```gherkin
Scenario: A real .ink compiles and plays identically on Linux
  Given a real supported-set .ink source with a committed macOS fixture
  When Nadia compiles it in-process on Linux and plays it via "swift test"
  Then the played transcript matches the fixture line-for-line and choice-for-choice

Scenario: Compilation needs no external binary on Linux
  Given a Linux host with no inklecate binary installed
  When Nadia compiles a supported .ink source in-process
  Then compilation succeeds without invoking any external process

Scenario: An unsupported construct fails loud on Linux
  Given an .ink source using a construct outside the supported set
  When Nadia compiles it on Linux
  Then a located CompileError names the construct and no story is produced
```

#### Acceptance Criteria
- [ ] A real supported `.ink` compiled in-process on Linux plays identically to the committed macOS fixture.
- [ ] Compilation on Linux invokes no external process (no inklecate).
- [ ] An unsupported construct raises a located, construct-named `CompileError` on Linux (parity with macOS).

#### Outcome KPIs (link)
KPI-2 (compiler fixture parity), KPI-1 (suite green).

#### Technical Notes
- Entry point exists: `InkCompiler.compile(source:)` (`Compiler/InkCompiler.swift:31`).
  The file overload (`compile(fileURL:)`) may remain scaffolded — source-string path suffices.
- Compiler pipeline is expected platform-neutral; this story *verifies* that on Linux.
- Dependency: US-02.

---

### US-04 — Linux CI guards parity on every push

**job_id**: job-linux-portability · **Slice**: 04 · **MoSCoW**: Must · **Depends on**: US-01..03

#### Elevator Pitch
- **Before**: CI runs only macOS-arm64; a change can pass on the Mac and silently
  break Linux, and Nadia only finds out when she pulls it into her container build.
- **After**: On every push, the forgejo workflow runs `swift test` on a **Linux**
  runner over the committed-fixture oracle and reports a green (or red) Linux job
  next to the macOS one.
- **Decision enabled**: Nadia can *decide to merge or block a change* based on a
  trustworthy Linux signal, without owning a Mac.

#### Problem
Nadia relies on CI to protect Linux parity, but `.forgejo/workflows/tests.yml` runs
only macOS-arm64. She finds it risky that a Linux-only regression is invisible until
it reaches her container build downstream.

#### Who
- Nadia (and Maarten reviewing PRs) | reads CI status to gate merges | needs a continuous Linux signal.

#### Solution
Add a Linux `swift test` job to the forgejo workflow that runs the committed-fixture
oracle suite on every push and pull_request, reporting pass/fail visibly.

#### Domain Examples
1. **Green path** — A PR that preserves Linux parity shows a green Linux job alongside green macOS.
2. **Regression caught** — A change that misclassifies a float on Linux turns the Linux job red while macOS stays green, before merge.
3. **JS-bridge excluded (boundary)** — The Linux job builds SwiftInkRuntime but not the
   `.macOS`-conditioned `InkSwift` JS-bridge target; its absence does not fail the Linux job.

#### UAT Scenarios (BDD)
```gherkin
Scenario: Linux verification runs on every push
  Given the forgejo workflow defines a Linux swift-test job
  When a commit is pushed
  Then the Linux job runs the committed-fixture oracle suite and reports pass or fail

Scenario: A Linux-only regression is caught before merge
  Given a change that breaks number classification only on Linux
  When the workflow runs
  Then the Linux job reports red while the macOS job reports green

Scenario: The Apple-only JS-bridge does not break Linux CI
  Given the InkSwift JS-bridge target is conditioned to .macOS
  When the Linux job builds and tests
  Then it excludes that target and still reports a valid pass/fail
```

#### Acceptance Criteria
- [ ] A Linux `swift test` job exists in `.forgejo/workflows/tests.yml`, triggered on push and pull_request.
- [ ] The Linux job runs the committed-fixture oracle suite and reports pass/fail.
- [ ] A deliberate Linux-only regression turns the Linux job red while macOS stays green (verified on a scratch branch).
- [ ] The macOS job and SwiftLint boundary job are unchanged and still green (guardrail).

#### Outcome KPIs (link)
KPI-4 (Linux CI on every push, regressions caught before merge).

#### Technical Notes
- Extends `.forgejo/workflows/tests.yml` (currently `test-macos` + `lint` only).
- Not `@infrastructure`: it produces an observable signal Nadia acts on (merge/block).
- DEVOPS handoff: runner provisioning / container image is a DEVOPS concern; the
  *requirement* (a Linux job over committed fixtures) is fixed here.
- Dependency: US-01..03 (a green Linux suite must exist to guard).

---

## Wave: DISCUSS / [REF] Outcome KPIs

### Objective
Within this feature's DELIVER cycle, make Linux a first-class, continuously-verified
target: SwiftInkRuntime builds, tests green, and plays/compiles Ink identically to macOS.

### Outcome KPIs

| # | Who | Does What | By How Much | Baseline | Measured By | Type |
|---|-----|-----------|-------------|----------|-------------|------|
| 1 | Nadia (server-side Swift dev) | builds SwiftInkRuntime + TestSupport and runs the suite to green on Linux | 100% of those targets' tests pass on Linux | 0% (does not compile on Linux) | `swift test` result on Linux runner | Leading |
| 2 | Nadia | plays/compiles supported stories on Linux producing text+choices identical to macOS | 100% of the committed fixture corpus is line-for-line / choice-for-choice identical | N/A (no Linux path exists) | committed-fixture oracle diff on Linux | Leading |
| 3 | Nadia | decodes real stories on Linux without value-type errors | 0 int/float/bool/bool-vs-int misclassifications across the fixture corpus | unknown/likely nonzero (CF-drift) | decode-parity fixture assertions on Linux | Leading (secondary) |
| 4 | Nadia / Maarten (reviewers) | catch Linux parity regressions before merge | Linux CI runs on 100% of pushes; 0 Linux-breaking merges | 0 Linux coverage in CI | forgejo workflow run history | Leading (secondary) |

### Metric Hierarchy
- **North Star**: full SwiftInkRuntime suite green on a Linux CI runner (KPI-1 × KPI-4).
- **Leading indicators**: fixture-corpus transcript parity (KPI-2); zero misclassifications (KPI-3).
- **Guardrail metrics** (must NOT degrade): macOS suite stays 100% green; JS-bridge oracle path on macOS unaffected; no new external dependency.

### Measurement Plan
| KPI | Data Source | Collection | Frequency | Owner |
|-----|------------|-----------|-----------|-------|
| 1 | Linux CI job | `swift test` exit status | every push | DEVOPS |
| 2 | committed-fixture oracle | transcript diff (golden files) | every push | DISTILL/DELIVER |
| 3 | decode-parity fixture | per-node type assertions | every push | DELIVER |
| 4 | forgejo run history | job presence + red/green trend | continuous | DEVOPS |

### Hypothesis
We believe that portable number classification + a committed-fixture oracle + a Linux
CI job for **Nadia** will achieve trustworthy Linux parity. We will know this is true
when the full SwiftInkRuntime suite passes on Linux CI and 100% of the fixture corpus
plays identically to macOS.

> Test-quality note: parity is validated by the **execution-equivalence oracle suite**
> (committed golden files), NOT mutation kill-rate (mutation testing is disabled).

---

## Wave: DISCUSS / [REF] Pre-requisites

- A supported Swift toolchain available on a Linux host / CI runner (`swift-toolchain-version`).
- Committed macOS-captured fixtures for the chosen corpus (The Intercept + a compiler
  sample + a float/bool decode sample). Capturing these on macOS ground truth is a
  DISTILL/DELIVER task — flagged here as an open question (see below).
- No new package dependency expected; `Package.swift` `platforms:` needs no Linux entry
  (SPM implies Linux) — the blocker is source-level, not the manifest.

---

## Wave: DISCUSS / [REF] Definition of Ready — Validation

9-item hard gate, per story. Evidence summarized; full ACs above.

| DoR Item | US-01 | US-02 | US-03 | US-04 |
|---|---|---|---|---|
| 1. Problem in domain language | PASS | PASS | PASS | PASS |
| 2. Persona w/ specific characteristics | PASS (Nadia) | PASS | PASS | PASS |
| 3. 3+ domain examples, real data | PASS (health=2.5, alive=true, Intercept) | PASS (Intercept transcript/choices) | PASS (supported .ink, no inklecate) | PASS (green/red/JS-bridge-excluded) |
| 4. UAT in GWT (3-7) | PASS (3) | PASS (3) | PASS (3) | PASS (3) |
| 5. AC derived from UAT | PASS | PASS | PASS | PASS |
| 6. Right-sized (1-3 days, 3-7 scenarios) | PASS (~1d, 3) | PASS (~1d, 3) | PASS (~1d, 3) | PASS (~1d, 3) |
| 7. Technical notes (constraints) | PASS | PASS | PASS | PASS |
| 8. Dependencies resolved/tracked | PASS (none) | PASS (US-01) | PASS (US-02) | PASS (US-01..03) |
| 9. Outcome KPIs w/ measurable targets | PASS (KPI-1,3) | PASS (KPI-1,2) | PASS (KPI-2,1) | PASS (KPI-4) |

**Elevator Pitch (Dimension 0) check**: all 4 stories have Before/After/Decision-enabled;
every "After" references a real driving port (`swift test`/`swift build` on Linux,
`InkCompiler.compile(source:)`, forgejo CI job) with concrete observable output
(rendered text `2.5`/`true`, full transcript, red/green job). No `@infrastructure`
story; no slice is infra-only. **JTBD traceability**: every story carries
`job_id: job-linux-portability`.

### DoR Status: PASSED (all 4 stories, all 9 items + Elevator Pitch gate)

---

## Wave: DISCUSS / [REF] Wave Decisions Summary

Locked decisions (D-numbered; D-1..D-4 are the orchestrator decisions carried in):

- **D-1 (JTBD framing)**: New persona `nadia` + new job `job-linux-portability`; full
  JTBD treatment; related to job-story-playback + job-native-compilation (extends reach).
- **D-2 (Scope boundary)**: `SwiftInkRuntime` + `SwiftInkRuntimeTestSupport` IN; legacy
  `InkSwift` JS-bridge OUT (Apple-only, already `.macOS`-conditioned).
- **D-3 (UX depth)**: Lightweight journey, happy-path focus, minimal error paths (toolchain, CF-drift).
- **D-4 (Density)**: DISCUSS hard default (lean + Tier-1 [REF] only). Ask-intelligent
  triggers evaluated at wave end — see below.
- **D-5 (Oracle on Linux)**: Verification uses a committed-fixture oracle (golden files
  captured on macOS), replacing the macOS-only live JS-bridge comparison. Flagged for DESIGN.
- **D-6 (No manifest platform change)**: `Package.swift platforms:` needs no Linux entry;
  the blocker is source-level CF usage, not the manifest.
- **D-7 (Solution-neutral classification)**: DISCUSS fixes only observable int/float/bool
  behaviour; the portable *mechanism* is a DESIGN decision (open question below).
- **D-8 (Guardrail)**: macOS suite + JS-bridge path must remain green — no Apple regression.

**Prior-wave consultation**: No DISCOVER/DIVERGE artifacts exist for this feature
(new). Noted as a risk: JTBD grounding was authored fresh in this wave rather than
inherited from a validated DIVERGE recommendation. Mitigated by the existing
`maarten` persona and delivered `native-runtime`/`native-ink-compiler` features
providing strong domain grounding.

**Ask-intelligent expansion triggers**: evaluated — **none fired**. A single new
persona is introduced (the ≥3-persona multi-stakeholder trigger does not fire); scope
is right-sized (no split trigger); depth is lightweight by decision. No scoped
expansion menu surfaced.

---

## Wave: DISCUSS / [REF] Open Questions for DESIGN

1. **Portable number/bool classification approach** (highest risk). How to reproduce
   macOS int/float/bool tagging on Linux without relying on CoreFoundation type
   identity — e.g. `JSONDecoder` with typed models, manual numeric-token typing at
   the JSON layer, or a `#if canImport`/os-conditional path. DISCUSS fixes behaviour
   (US-01 ACs); DESIGN chooses the mechanism. `InkDecoder.swift:24-36, 123-138`.
2. **Committed-fixture oracle strategy** (D-5). How fixtures are captured on macOS
   ground truth, stored, and diffed on Linux without the JS-bridge — golden transcript
   format, corpus selection (The Intercept + compiler sample + float/bool sample), and
   how the same fixture feeds both the local Linux suite and the Linux CI job.

---

## Wave: DISCUSS / [REF] Handoff

- **→ solution-architect (DESIGN)**: this feature-delta + journey SSOT + slice briefs +
  the two open questions above.
- **→ platform-architect (DEVOPS)**: outcome KPIs (esp. KPI-4 Linux CI job + measurement plan).
- **→ acceptance-designer (DISTILL)**: journey Gherkin (happy path + CF-drift) + embedded
  UAT scenarios + committed-fixture constraint + System Constraints (backtick style,
  `.disabled` AT authoring, oracle-based test quality).

---

## Wave: DESIGN / [REF] Design Decisions (DDD)

Guided-discovery locked three decisions (DD-1..DD-3); DESIGN adds two derived ones
(DD-4/DD-5). Full rationale + alternatives in ADR-013 and ADR-014.

- **DD-1 — Portable number/bool classification** (ADR-013). Replace the CoreFoundation
  type-identity path (`InkDecoder.decode` `:24-36`, `classifyNumber` `:123-138`) with
  **`JSONDecoder` + a custom `Decodable`** that types node scalars **Bool → Int →
  Double** (first successful decode wins). Typing is driven by the JSON token grammar
  (identical across Foundation implementations), not `CFGetTypeID`/`CFBooleanGetTypeID`/
  `CFNumberGetType`. Stays inside `Decoder/`. No new source files required.
- **DD-2 — Hybrid oracle** (ADR-014). Golden played-transcript files (full text +
  choices) are the primary black-box parity oracle (KPI-2); PLUS a small set of
  targeted float/int/bool **decode-parity assertions** guarding KPI-3. NO full
  decoded-node-tree snapshots (white-box, brittle, leaks `NodeKind`).
- **DD-3 — Ground truth = inklecate committed fixtures** (ADR-014). inklecate generates
  golden fixtures at **capture time** on a dev machine; fixtures are committed and
  diffed by BOTH macOS and Linux native runtimes. inklecate is **capture-time-only** —
  never a Linux-runtime or Linux-CI dependency. Supersedes the JS-bridge as this
  feature's cross-platform oracle; builds on `docs/how-to/native-compile-story-equivalence.md`.
- **DD-4 — Earned-Trust probe extension** (ADR-013). `InkDecoder.probe()` gains a
  float/bool/int triple in its embedded fixture and asserts the resulting node tags, so
  a platform that lies about number typing (CF-drift) fails the probe and
  `Story.init(json:)` throws `decoderProbeFailure` — the mistyping bug is
  non-representable at startup, not merely testable-around.
- **DD-5 — R3 boundary generalization** (ADR-013). R3 becomes "Ink-format JSON decoding
  (`JSONSerialization`/`JSONDecoder` for `.ink.json`→node-tree) confined to `Decoder/`".
  `.swiftlint.yml` regex is a DELIVER task, scoped to avoid a false positive on the
  ADR-003 `StoryState` save/restore (`Engine/InkEngine.swift:1056`).

---

## Wave: DESIGN / [REF] Architecture Recommendation

Fits the existing modular-monolith / ports-and-adapters design with **zero new
production components**. The only production change is EXTEND `InkDecoder` (classify
path + probe). No new container, module, target, actor, data store, or external
system. inklecate stays a capture-time-only test oracle. Rationale: parity-only scope,
single bounded context (`SwiftInkRuntime`), single maintainer — simplest solution
that satisfies Correctness + Portability.

---

## Wave: DESIGN / [REF] Component Decomposition

| Component | Path | Change type |
|---|---|---|
| `InkDecoder` (classify + probe) | `Sources/SwiftInkRuntime/Decoder/InkDecoder.swift` | EXTEND (only production change) |
| `FixtureTranscriptOracle` (test-support harness) | `Sources/SwiftInkRuntimeTestSupport/` | CREATE NEW (existing target, no new SPM target) |
| Golden transcript + decode-sample fixtures | `Tests/SwiftInkRuntimeTests/Fixtures/` | EXTEND (already `.process`-bundled) |
| `test-linux` CI job | `.forgejo/workflows/tests.yml` | EXTEND |
| R3 enforcement regex | `.swiftlint.yml` | EXTEND (DELIVER task) |

---

## Wave: DESIGN / [REF] Driving Ports

Reused verbatim from the DISCUSS Driving Ports list (all exist today, observable on
Linux): `swift build` / `swift test` on Linux; `StoryBlueprint(json:)` + `Story`
playback (`continue()`, `chooseChoice(at:)`, `continueMaximally()`);
`InkCompiler.compile(source:) -> StoryBlueprint`; `git push` → forgejo Linux job.

---

## Wave: DESIGN / [REF] Driven Ports and Adapters

| Driven port (substrate) | Adapter | Probe / fault-injection (Earned Trust) |
|---|---|---|
| Ink-JSON decode substrate (`JSONDecoder`, Foundation) | `InkDecoder` (`Decoder/`) | `probe()` decodes an embedded float/bool/int fixture, asserts `.floatValue`/`.boolValue`/`.intValue` — exercises the swift-corelibs-foundation CF-drift lie; failure → `decoderProbeFailure`. |
| Filesystem / bundle resources (`Bundle.module`, golden files) | `InkDecoder.probe()` + `FixtureTranscriptOracle` | Probe resolves `Bundle.module` on Linux (US-02); golden transcript reads are the single static artifact both local + CI diff. |
| CI execution substrate (Linux runner) | `test-linux` forgejo job | US-04 AC: a deliberate Linux-only misclassification reds the Linux job while macOS stays green. |

---

## Wave: DESIGN / [REF] Technology Choices

| Choice | Version / pin | License | Rationale |
|---|---|---|---|
| `JSONDecoder` + custom `Decodable` | Foundation (bundled) | APSL (macOS) / Apache 2.0 (Linux) | Present already; token-driven typing platform-stable; no new runtime dependency. |
| Swift toolchain (Linux CI) | floor = `Package.swift` `swift-tools-version`; exact Linux pin = DEVOPS open Q | Apache 2.0 | Build/test `SwiftInkRuntime` + `SwiftInkRuntimeTestSupport` on Linux. |
| inklecate (capture-time only) | pinned at capture; supported inkVersion 21 | MIT | Generates golden fixtures offline; never a Linux-runtime/CI dependency. |

---

## Wave: DESIGN / [REF] Decisions Table

| ID | Decision | ADR | Status |
|---|---|---|---|
| DD-1 | Portable classification: JSONDecoder + custom Decodable (Bool→Int→Double), in `Decoder/` | ADR-013 | Accepted |
| DD-2 | Hybrid oracle: golden transcripts + decode-parity asserts; no node-tree snapshots | ADR-014 | Accepted |
| DD-3 | Ground truth = inklecate committed fixtures, capture-time-only | ADR-014 | Accepted |
| DD-4 | Earned-Trust probe extension exercises the CF-drift lie | ADR-013 | Accepted |
| DD-5 | R3 generalized to Ink-format JSON decoding; `.swiftlint.yml` regex = DELIVER task | ADR-013 | Accepted |

---

## Wave: DESIGN / [REF] Reuse Analysis

Full table (with the CREATE NEW justification) is in `brief.md`
`### native-runtime-linux (Feature Addition)`. Verdicts:

Contract shape per **principle 12 (Effect Isolation)** — no component is `unbounded-preservation`; none performs unbounded effects.

| Component | Decision | Contract shape · universe |
|---|---|---|
| `InkDecoder` classify path | EXTEND (swap CF → JSONDecoder+Decodable; not a new decoder) | **bounded-change** · Ink-JSON scalar classification → value node-tree |
| `InkDecoder.probe()` | EXTEND (add classification fault-injection, DD-4) | **bounded-change** · startup validation, void/throws |
| Fixture corpus / resources | EXTEND (`Tests/.../Fixtures/`, already bundled) | **bounded-change** · static committed test data |
| `FixtureTranscriptOracle` harness | **CREATE NEW** in existing `SwiftInkRuntimeTestSupport` target — evidence: no existing oracle is both platform-portable (JS-bridge is macOS-only) AND hard-asserting on a static artifact (`OracleDivergenceProbe` green-passes on failure by design). **No new SPM target.** | **bounded-change** · test-local: reads static golden, plays story, hard-asserts |
| `OracleDiagnostics` / `OracleDivergenceProbe` | REUSE AS-IS (diagnosis driver, not the gate) | **diagnostic utility** · green-always by design |
| `.forgejo/workflows/tests.yml` | EXTEND (`test-linux` job) | **bounded-change** · CI config; pass/fail signal |
| `.swiftlint.yml` R3 rule | EXTEND (DELIVER task) | **boundary enforcement** · confines Ink-format JSON decoding to `Decoder/` |

**Outcome Collision Check** (`nwave-ai outcomes check-delta`): **correctly skipped** —
`docs/product/outcomes/registry.yaml` does not exist (registry not bootstrapped in this
repo). Not bootstrapped; proceeding.

---

## Wave: DESIGN / [REF] Open Questions for DISTILL / DELIVER / DEVOPS

1. **(DISTILL/DELIVER)** Exact fixture-corpus capture mechanics — golden-transcript
   file format, capture command, REGEN discipline for The Intercept + compiler sample +
   float/bool decode sample.
2. **(DELIVER)** `.swiftlint.yml` R3 regex edit — bind against `JSONDecoder` **for
   Ink-format JSON decoding, confined to `Decoder/`**, with an explicit exception for
   the ADR-003 `StoryState` save/restore in `Engine/` (`InkEngine.swift:1056`).
   Verify no false positive before commit.
   Verify no false positive before commit.
3. **(DEVOPS)** Swift-on-Linux toolchain version pin for the `test-linux` runner + the
   runner/container image (KPI-4). `Package.swift platforms:` needs no Linux entry.

---

## Wave: DESIGN / [REF] Handoff

- **→ acceptance-designer (DISTILL)**: DD-1..5 + ADR-013/014 + the hybrid-oracle
  contract (golden transcripts primary, decode-parity asserts secondary) + corpus
  selection; author ATs `.disabled` per CLAUDE.md; fixture capture mechanics (open Q 1).
- **→ platform-architect (DEVOPS)**: Linux CI runner/toolchain provisioning + version
  pin (open Q 3, US-04/KPI-4); inklecate stays capture-time-only (never in the Linux
  image). **No external integrations requiring contract tests** — `SwiftInkRuntime` has
  no network/third-party API surface; the only boundary is the static `.ink.json` file
  format and capture-time inklecate.
- **→ software-crafter (DELIVER)**: EXTEND `InkDecoder` per ADR-013; extend `probe()`
  (DD-4); `FixtureTranscriptOracle` in `SwiftInkRuntimeTestSupport`; the `.swiftlint.yml`
  R3 regex task (open Q 2). Paradigm OOP (unchanged).

---

## Wave: DISTILL / [REF] Reconciliation Gate

**Reconciliation passed — 0 contradictions.** DISCUSS decisions (D-1..D-8) and
DESIGN decisions (DD-1..DD-5) are consistent; DESIGN back-propagated cleanly and
reported no `upstream-changes.md`. DISCUSS ACs are mechanism-neutral, so DD-1..DD-5
satisfy them without story revision.

## Wave: DISTILL / [REF] Oracle / WS Strategy

**Key finding — the cross-platform oracle already exists.** The committed-fixture
oracle pattern DESIGN specified (ADR-014, DD-2/DD-3) is already the repo's practice:
`Milestone5b`'s Intercept assertion diffs native playback against the committed
`TheIntercept_oracle_walkthrough.json` (`expectedLines`) via `Bundle.module`+`Codable`
— platform-neutral. The JS-bridge (`#if os(macOS) import InkSwift`) is used ONLY to
*regenerate* the fixture offline, never to assert. inklecate is available
(`/Users/…/.local/bin/inklecate`) and the equivalence runbook already captures
`Fixtures/<Story>.ink.json` offline (test-only, never CI) — exactly DD-3.

Consequence: **20 of 28 acceptance files carry no `#if os(macOS)` guard** and run on
Linux the moment `InkDecoder` compiles. Their existing committed-fixture assertions
ARE the US-02 (runtime) and US-03 (compiler) parity verification. The `FixtureTranscriptOracle`
CREATE-NEW (DESIGN) is therefore thinner than assumed — the pattern is in place; DELIVER
consolidates rather than invents.

Architecture-of-Reference treatment: driving port = `Story`/`InkCompiler` facade (real,
in-process); driven port = static `.ink.json`/golden files (real bundled I/O); external
inklecate = capture-time only (fake at runtime — never invoked in CI/Linux).

## Wave: DISTILL / [REF] Scenario List

| Scenario (Swift Testing `@Test`) | Tags | Story | Runs on | State |
|---|---|---|---|---|
| `decoder classifies a fractional number as floatValue on every platform` | @real-io @US-01 @property | US-01 | macOS + Linux | GREEN (macOS); Linux guard after DD-1 |
| `decoder classifies true as boolValue not intValue on every platform` | @real-io @US-01 | US-01 | macOS + Linux | GREEN (macOS); Linux guard after DD-1 |
| `decoder classifies false as boolValue not intValue on every platform` | @real-io @US-01 | US-01 | macOS + Linux | GREEN (macOS); Linux guard after DD-1 |
| `decoder keeps integer and float kinds distinct in one container` | @real-io @US-01 | US-01 | macOS + Linux | GREEN (macOS); Linux guard after DD-1 |
| `The Intercept non-trivial playthrough matches the committed oracle walkthrough…` (existing) | @real-io @US-02 | US-02 | macOS + **Linux (after DD-1)** | GREEN macOS; unblocks on Linux compile |
| Existing `Compiler_*` oracle suite (existing) | @real-io @US-03 | US-03 | macOS + **Linux (after DD-1)** | GREEN macOS; unblocks on Linux compile |
| `InkDecoder probe passes for the bundled test fixture` (existing, DD-4 enriches fixture) | @real-io @US-01 | US-01/DD-4 | macOS + Linux | GREEN; guards enriched probe |

New file: `Tests/SwiftInkRuntimeTests/Acceptance/NativeRuntimeLinux_NumberTypeParityTests.swift`
(4 `@Test`, backtick names per CLAUDE.md, no `#if` guard). Not `.disabled` — green on
macOS immediately; they are the regression net proving the JSONDecoder swap keeps macOS
typing AND makes Linux identical (the RED for US-01 is the Linux *compile* failure, not a
failing macOS test — see red-classification).

## Wave: DISTILL / [REF] Scaffolds

**None required.** No new production module is introduced by the walking skeleton —
US-01 EXTENDS the existing `InkDecoder` (compiles today on macOS). Mandate-7 RED
scaffolding N/A: the ATs bind to existing public API (`InkDecoder.decode`, `.probe()`,
`Story`, `InkCompiler`).

## Wave: DISTILL / [REF] Red Classification

The genuine RED for US-01 is a **compile failure on Linux** (reproduced in the `swiftdev`
container, Swift 6.3.3 aarch64):

```
InkDecoder.swift:126: error: cannot find 'CFGetTypeID' in scope
InkDecoder.swift:126: error: cannot find 'CFBooleanGetTypeID' in scope
InkDecoder.swift:129: error: cannot find 'CFNumberGetType' in scope
InkDecoder.swift:129: error: cannot find type 'CFNumber' in scope
```

Classification: `MISSING_FUNCTIONALITY` (portable classification unimplemented) — a
compile-level RED confined to `classifyNumber`; every other SwiftInkRuntime file compiles
on Linux. The new parity ATs are GREEN on macOS by design (they encode required behaviour
the CF path already satisfies there); DELIVER's job is to make the target *compile and pass
them on Linux* without regressing macOS.

## Wave: DISTILL / [REF] Pre-requisites & Handoff to DELIVER

- Linux verification environment: `podman exec swiftdev` (Swift 6.3.3 aarch64, repo bind-mounted at same path). Toolchain matches macOS 6.3.3 — DEVOPS should pin `swift:6.3.3` for CI.
- inklecate present for offline fixture (re)generation; never invoked on Linux/CI.
- DELIVER (dispatch `@nw-software-crafter` per CLAUDE.md): implement DD-1 (`JSONDecoder`+custom `Decodable`, Bool→Int→Double) in `InkDecoder`; keep macOS green (pre-commit gate); verify the 4 parity ATs + full Linux-runnable suite pass in `swiftdev`; enrich `probe()` fixture (DD-4); the `.swiftlint.yml` R3 regex edit (open Q 2). US-04 (Linux CI) deferred to DEVOPS by user's chosen sequence (DELIVER first, DEVOPS from green).
