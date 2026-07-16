<!-- markdownlint-disable MD024 -->
# Feature Delta — native-runtime-migration (DISCUSS)

> Single DISCUSS narrative. Tier-1 [REF] sections only (density = DISCUSS hard
> default: lean + ask-intelligent). Legacy split files (user-stories.md,
> story-map.md, acceptance-criteria.md, outcome-kpis.md) are intentionally NOT
> emitted — that content lives here. Slice briefs live under `slices/`.

**One-liner**: The "nudge" increment — reposition the README to recommend the native
`SwiftInkRuntime`, add an `@available` deprecation signal on the JS-bridge `InkStory`
API pointing at v3.0.0 removal, ship an `InkStory → Story/InkCompiler` migration
guide, and publish an honest supported-parity / known-gaps statement. **Removing the
JS-bridge is explicitly OUT of scope** (separate future feature — breaking major, v3.0.0).

---

## Wave: DISCUSS / [REF] Persona

**No new persona file.** The migration decision is made by the **existing InkSwift
JS-bridge (v2.x) consumer** — a hat both existing personas already wear:

- `maarten` — Apple-platform app/game developer, the current README's marketed
  audience and the primary `InkStory` consumer (`docs/product/personas/maarten.md`).
- `nadia` — server-side Swift developer on Linux; also an existing JS-bridge consumer
  now that JXKit 3.6.0 builds the bridge on Linux (`docs/product/personas/nadia.md`).

A light "existing v2.x JS-bridge consumer" sub-persona was considered and rejected as
persona sprawl at this density — Maarten + Nadia cover it. The **maintainer**
(`maartene@mac.com`) is a real driver (one runtime, drop the JavaScriptCore
system-lib dependency, less maintenance), but every value-outcome below is framed
around the **consumer's** job, and every Elevator-Pitch "After" line references a
consumer-invocable entry point (README, the compiler deprecation warning on
`import InkSwift`, the migration-guide doc, the parity statement). Two existing
personas → the ≥3-persona multi-stakeholder ask-intelligent trigger does **not** fire.

---

## Wave: DISCUSS / [REF] JTBD

**New job**: `job-runtime-consolidation` (added to `docs/product/jobs.yaml`, schema v4).

> When I have an app or service built on the InkSwift JS-bridge (v2.x) and the
> maintainer is steering toward one native runtime, I want to understand that the
> JS-bridge is now legacy, see exactly how my code maps to the native SwiftInkRuntime
> API, and know honestly what does and does not work yet, so I can decide whether and
> how to migrate — without being surprised by a future breaking removal or misled by
> an over-claimed "full parity".

**Four forces** (full detail in jobs.yaml):
- **Push**: JS-bridge carries a JavaScriptCore/JXKit + bundled inkjs dependency; the
  README markets it as primary and calls native "experimental"; the maintainer wants
  to consolidate on one runtime and reduce maintenance burden.
- **Pull**: one recommended pure-Swift runtime, no JS engine; a clear
  `InkStory → Story/InkCompiler` mapping; an honest parity/gaps statement; advance
  notice of the v3.0.0 removal so migration is planned, not forced.
- **Anxiety**: "If I migrate, will my story behave identically? Native can't play
  LIST, RANDOM/SEED_RANDOM, threads, EXTERNAL, or shuffle `{~a|b}`, and has no Combine
  observation — will I silently lose features?" and "Will the bridge vanish without warning?"
- **Habit**: the established `InkStory()` + `loadStory` + Combine
  `ObservableObject`/`@StateObject` SwiftUI pattern the README teaches; trust in inkjs
  (full Ink) as ground truth.

**Dimensions**:
- *Functional*: reposition README; deprecate `InkStory`; map every call to native;
  publish an honest gaps list; name the v3.0.0 runway.
- *Emotional*: relief from "is my runtime dying?" anxiety; trust earned by honesty
  (documented gaps, not "full parity"); control over the migrate/stay/wait decision.
- *Social*: makes InkSwift a coherent one-runtime project; the maintainer can steer
  the ecosystem onto native without breaking published consumers today.

**Relation to existing jobs** (this job *consolidates* what they built): `job-story-playback`
(RUN native) + `job-native-compilation` (BUILD native) + `job-linux-portability`
(native on Linux) made the native runtime ready on Apple + Linux; this job helps the
consumer switch to it and signals the JS-bridge is legacy.

---

## Wave: DISCUSS / [REF] Scope Assessment

**## Scope Assessment: PASS — 4 stories, 1–2 modules (docs + the `InkSwift` deprecation attribute), estimated ~3 days**

Elephant-Carpaccio early gate (run before journey investment). Oversized signals checked:

| Signal | Threshold | This feature | Trip? |
|---|---|---|---|
| Story count | >10 | 4 | No |
| Bounded contexts / modules | >3 | 2 (docs; one attribute on `InkSwift`) | No |
| Walking-skeleton integration points | >5 | N/A (brownfield; no WS per locked decision) | No |
| Estimated effort | >2 weeks | ~3 days | No |
| Independent shippable outcomes | multiple | 1 coherent "nudge" outcome, sliced thin | No |

Right-sized. No split required. The decisive right-sizer is that **actual removal of
the JS-bridge is out of scope** — this feature is docs + one deprecation attribute +
two documents. If removal were in scope (breaking API deletion, consumer-migration
support, major-version release mechanics) it would be oversized and split; it is
deliberately deferred to a separate future feature (v3.0.0).

---

## Wave: DISCUSS / [REF] Out of Scope

- **Removing or repurposing the `InkSwift` JS-bridge product.** This feature only
  *deprecates and nudges*. The eventual removal is a **separate future feature**: a
  breaking major-version deletion in **v3.0.0**, after which consumers migrate to
  `SwiftInkRuntime`. (The deprecation MESSAGE this feature ships DOES name v3.0.0 — see
  US-02 — but no code is removed here.)
- **Closing any of the documented gaps** (adding LIST / RANDOM / threads / EXTERNAL /
  shuffle / Combine observation to native). Each is its own future increment; this
  feature only *documents* the gaps honestly and sets the maintenance convention for
  pruning them (US-04).
- **Prescribing the `@available` attribute mechanics / API surface changes.** DISCUSS
  fixes the observable warning-text CONTENT (US-02 AC); the exact attribute spelling,
  access modifiers, and any `renamed:`/`unavailable` mechanics are a DESIGN/DELIVER
  concern (per the recorded DISCUSS-scope convention).
- **Package registry / release automation** — publishing the doc changes and the
  deprecated build is normal release flow; no new CI/packaging pipeline is in scope.

---

## Wave: DISCUSS / [REF] Journey & Emotional Arc

Journey SSOT: `docs/product/journeys/native-runtime-migration.yaml` (lightweight).

`discover recommendation (README) → see legacy signal (compiler warning) → map my code (migration guide) → judge the gaps (parity statement) → decide`

Emotional arc (Problem Relief + Confidence Building, **honesty-gated**):
**Uncertain / wary** ("README calls native experimental, yet I hear it's recommended —
is the bridge dying, what breaks?") → **informed / engaged** (clear mapping + an HONEST
gaps list I can trust) → **confident and in control** (I know the v3.0.0 runway and the
gaps; I decide migrate / stay / wait).

Minimal error/edge paths: (1) the deprecation is emitted as an **error / build break**
instead of a warning (guardrail violation); (2) an **over-claim** — README or parity
statement hides a gap (e.g. LIST) and a consumer migrates into a broken story. Both have
Gherkin in the journey SSOT.

---

## Wave: DISCUSS / [REF] Shared Artifacts

| Artifact | Source of truth | Consumers | Integration risk |
|---|---|---|---|
| `recommended-runtime-name` = `SwiftInkRuntime` | `Package.swift` product name | README, deprecation message, migration guide, parity statement | HIGH — a name mismatch makes the recommendation unfollowable |
| `removal-version` = **v3.0.0** | this feature's decision, recorded in the migration guide + parity statement | deprecation message, migration guide, parity statement, README | **HIGH** — the runway must read identically everywhere or trust erodes |
| `api-mapping-table` (`InkStory` → `Story`/`InkCompiler`) | the migration guide doc (single source) | migration guide, deprecation-message pointer, README link | HIGH — a missing/incorrect row strands a consumer mid-migration |
| `known-gaps-list` (feature gaps + API gaps) | **construct gaps: `docs/product/ink-feature-reference.md` (SSOT)**; API gaps (Combine, tag-shape, errors): the parity statement | parity statement (aggregator), README "stay on the bridge if…", migration guide caveats | **HIGH** — divergence = an over-claim; a stale (closed) gap = a stale backlog |
| `deprecation-message-string` | `@available(...message:)` on `InkStory` (`Sources/InkSwift/InkStory.swift`) | Swift compiler warning surfaced in the consumer's Xcode / CLI | HIGH — must name v3.0.0 + SwiftInkRuntime + point to the guide |

Integration checkpoint: `removal-version` and `known-gaps-list` are the two values
that MUST stay consistent across every consumer surface. The parity statement is the
single aggregator of the gaps list — and it **references** `ink-feature-reference.md`
for the language-construct gaps rather than duplicating them (see US-04).

---

## Wave: DISCUSS / [REF] Story Map & Walking Skeleton

**Backbone** (existing consumer's activities, left→right):

| Discover the recommendation | See the legacy signal | Map my code | Judge the gaps & decide |
|---|---|---|---|
| README repositioned | `@available` deprecation on `InkStory` | migration guide (API mapping) | honest parity / known-gaps statement |

**Walking skeleton: N/A (brownfield — per locked decision).** There is no thinnest
end-to-end *code* path to stand up; every activity is an independent, already-reachable
consumer touchpoint (an existing README, an existing compiled API, new docs). Slices are
therefore sliced purely by consumer outcome, each independently shippable.

**Release slices** (each ≤1 day, user-visible, outcome-named; briefs in `slices/`).
Slice NN maps to US-NN (backbone order); delivery order is in Priority Rationale.

1. **Slice 01 — README recommends the native runtime** → US-01. Outcome: a developer reading the README chooses native for new projects, gaps stated up front.
2. **Slice 02 — The JS-bridge API signals it is legacy** → US-02. Outcome: a consumer compiling `InkStory` sees a v3.0.0-removal deprecation warning pointing to native + the guide.
3. **Slice 03 — Migration guide maps every call** → US-03. Outcome: a consumer translates `InkStory` → `Story`/`InkCompiler` call-by-call, incl. the no-equivalent gap.
4. **Slice 04 — Honest parity / known-gaps statement** → US-04. Outcome: a consumer knows what native can't do yet and self-selects migrate/stay.

### Priority Rationale

Priority = **dependency-first, then outcome impact** (Value×Urgency/Effort). The
deprecation warning (US-02) has the highest *reach* (it lands at every consumer's
keyboard), but it must never point into a void — its message links to the migration
guide and the honest gaps must exist first. So the **destinations are built before the
signal**:

- **P1 — US-04 (parity / known-gaps)**: the honesty foundation everything else
  references (README "stay on the bridge if…", migration-guide caveats, and the
  deprecation tone all depend on the gaps list). Riskiest *content* assumption — if the
  gaps are wrong or over-claimed, the entire nudge misleads. Ships first.
- **P2 — US-03 (migration guide)**: the destination the signal and the README point to;
  must exist before US-02's warning message can honestly reference it.
- **P3 — US-01 (README reposition)**: high visibility, low risk; references the parity
  statement (P1) and the guide (P2), so it lands after them.
- **P4 — US-02 (deprecation signal)**: highest reach, but blocked by P1–P3 — its warning
  text links to the guide + names the runway, so it ships last, when every link resolves.

---

## Wave: DISCUSS / [REF] Driving Ports

The observable surfaces every Elevator Pitch "After" line references (all
consumer-invocable):

- The **README** at `github.com/maartene/InkSwift` (and `README.md`) — observable: recommendation text + gaps.
- The **Swift compiler deprecation warning** emitted when a consumer builds against
  `import InkSwift` / `InkStory` — observable: the warning string in Xcode / `swift build` output.
- The **migration guide doc** (`docs/how-to/migrate-from-js-bridge.md`) — observable: the rendered API-mapping table.
- The **parity statement doc** (`docs/reference/js-bridge-vs-native-parity.md`) — observable: the rendered gaps list + stay/migrate guidance.

---

## Wave: DISCUSS / [REF] System Constraints

Cross-cutting constraints inherited by DISTILL/DELIVER (recorded from CLAUDE.md +
locked decisions):

- **The deprecation is a WARNING, not an error.** Existing consumer builds MUST keep
  compiling; no public API is removed in this feature (guardrail).
- **Parity tone = "encourage, gaps documented".** Never over-claim "full parity". The
  honest form: "We recommend SwiftInkRuntime for new projects. Known gaps vs the
  JS-bridge: <list>. Stay on the JS-bridge if you need <X>."
- **Removal endpoint is v3.0.0.** The deprecation message and both docs name it; no code
  removal happens here.
- **Construct-gap SSOT is `docs/product/ink-feature-reference.md`.** The parity statement
  *references* its MUST-REJECT rows for language-construct gaps rather than duplicating
  them; it aggregates those with the API gaps (Combine, tag-shape, error-handling).
- **Living parity backlog convention** (maintainer, this feature): the published gaps
  list is a *living backlog / native to-do list toward v3.0.0*. Each later feature that
  closes a gap (moves a construct MUST-REJECT → MUST-COMPILE in `ink-feature-reference.md`,
  or lands a missing API-parity capability like Combine observation) MUST revisit the gap
  list and **prune the closed item as part of its GREEN/finalize step**. A closed gap
  left listed is a stale backlog — same failure class as a stale test.
- **Swift Testing backtick style is mandatory**; string-label `@Test("…")` forbidden.
  `.disabled("…")` reasons are traits, not display names.
- **Trunk-based dev**: every DELIVER step commits to `main` green (pre-commit gate:
  SwiftLint boundary rules + `swift test`). New ATs authored `.disabled(...)` until
  their DELIVER step re-enables; **zero `.disabled` ATs at finalize**.
- **Mutation testing disabled** project-wide. Test quality = execution-equivalence
  oracle suite + code review + CI boundary gates. Note: most of this feature's ACs are
  **documentation-accuracy** checks (link resolves, table covers the public surface,
  gaps list matches the SSOT) rather than runtime behaviour — verifiable by doc audit
  and, for US-02, a compile that emits the expected warning without erroring.
- **Guardrail**: the macOS suite (incl. the JS-bridge path) and the Linux suite must
  stay green — no regression; the JS-bridge remains fully functional while deprecated.

---

## Wave: DISCUSS / [REF] User Stories

All stories trace to `job_id: job-runtime-consolidation`. None are `@infrastructure`
(each enables a real consumer decision and references a real driving port).

### US-01 — The README recommends the native runtime (with honest gaps)

**job_id**: job-runtime-consolidation · **Slice**: 01 · **MoSCoW**: Must

#### Elevator Pitch
- **Before**: The README markets the JS-bridge as primary and calls SwiftInkRuntime
  "experimental… plays the first 100 lines of the Intercept" — stale and misleading;
  a new adopter picks the JS-bridge by default.
- **After**: A developer viewing `github.com/maartene/InkSwift` (README.md) reads
  "SwiftInkRuntime is the recommended runtime for new projects — pure Swift, no
  JavaScript engine, native compiler, runs on Apple and Linux", followed by an honest
  "Known gaps vs the JS-bridge" note.
- **Decision enabled**: a developer starting a new project can *choose the native
  runtime with confidence* — and knows immediately if a gap sends them to the bridge.

#### Problem
An existing or prospective InkSwift user (Maarten) reads the README to decide which
runtime to adopt. He finds it misleading that the README still calls SwiftInkRuntime
"experimental / first 100 lines" when the native runtime in fact executes The Intercept
fully, has a native compiler, and runs on Linux — so he defaults to the heavier
JS-bridge and never learns native is recommended.

#### Who
- Maarten / Nadia (existing or new InkSwift adopter) | reading the README to pick a runtime | wants the recommended, honestly-scoped choice.

#### Solution
Reposition the README so the native `SwiftInkRuntime` is presented as the recommended
runtime for new projects (accurate capabilities, no "experimental" language), with an
honest, linked "Known gaps vs the JS-bridge" note and a pointer to the migration guide.
The JS-bridge section remains, reframed as the legacy path.

#### Domain Examples
1. **New-project adopter** — A developer starting a fresh SwiftUI game reads the README,
   sees SwiftInkRuntime recommended (no JS engine, native compiler), and adds
   `SwiftInkRuntime` as the dependency instead of `InkSwift`.
2. **Gap-aware adopter (boundary)** — A developer whose story uses `LIST` reads the same
   README, sees LIST listed under "Known gaps", and knowingly stays on the JS-bridge.
3. **Stale-claim removed** — The README no longer contains the string "plays the first
   100 lines of the Intercept"; it states the runtime executes The Intercept fully and
   runs on Apple + Linux.

#### UAT Scenarios (BDD)
```gherkin
Scenario: The README recommends the native runtime for new projects
  Given the InkSwift README
  When a developer reads the top-of-README runtime guidance
  Then SwiftInkRuntime is presented as the recommended runtime for new projects
  And the "experimental / first 100 lines" description of it is gone

Scenario: The README states the known gaps honestly
  Given the README recommends SwiftInkRuntime
  When a developer reads the runtime guidance
  Then a "Known gaps vs the JS-bridge" note lists the feature and API gaps
  And it links to the parity statement and the migration guide
  And it does not claim "full parity"

Scenario: A gap sends a specific consumer to the JS-bridge
  Given a developer whose story uses LIST
  When they read the README's known-gaps note
  Then LIST is listed as a native gap and they are advised to stay on the JS-bridge
```

#### Acceptance Criteria
- [ ] The README presents `SwiftInkRuntime` as the recommended runtime for new projects; the "experimental / first 100 lines" wording is removed.
- [ ] The README includes an honest "Known gaps vs the JS-bridge" note that links to the parity statement (US-04) and migration guide (US-03), and makes no "full parity" claim.
- [ ] The JS-bridge section remains present but reframed as the legacy path (with a pointer to the migration guide).

#### Outcome KPIs (link)
KPI-1 (new adopters choose native), KPI-4 (gaps list complete & honest). See KPI section.

#### Technical Notes
- Edits `README.md` (top banner line 4 + "Supported features" + "Getting started"
  sections currently teach `InkStory`).
- Depends on US-03 (migration guide) and US-04 (parity statement) existing so the links resolve.
- No code change.

---

### US-02 — The JS-bridge API signals it is legacy (deprecation warning)

**job_id**: job-runtime-consolidation · **Slice**: 02 · **MoSCoW**: Must · **Depends on**: US-03, US-04

#### Elevator Pitch
- **Before**: A consumer compiling `let story = InkStory()` gets no signal that the
  JS-bridge is legacy or that a removal is coming — the runtime choice is invisible at
  the keyboard.
- **After**: When the consumer builds against `import InkSwift`, the Swift compiler
  emits a deprecation warning on `InkStory` reading, in effect: *"legacy; will be
  removed in v3.0.0 — migrate to SwiftInkRuntime (see the migration guide)"*, and the
  **build still succeeds**.
- **Decision enabled**: the consumer can *plan a migration on a known runway (v3.0.0)*
  — or knowingly suppress the warning and stay, eyes open.

#### Problem
An existing consumer (Maarten) has an app built on `InkStory`. He finds it risky that
nothing tells him the JS-bridge is now the legacy path or that a breaking removal is
planned — he could discover it only when v3.0.0 deletes the API out from under him.

#### Who
- Maarten / Nadia (existing JS-bridge consumer) | rebuilding an app that calls `InkStory` | needs an unmissable, non-breaking legacy signal with a runway.

#### Solution
Attach an `@available` deprecation to the JS-bridge `InkStory` public API whose warning
text names the v3.0.0 removal, names `SwiftInkRuntime` as the destination, and points to
the migration guide. It is a WARNING (build succeeds), never an error. (DESIGN/DELIVER
own the exact attribute mechanics; this story fixes the observable warning-text content.)

#### Domain Examples
1. **Warning on construction** — A consumer's `let story = InkStory()` compiles and emits
   a deprecation warning naming v3.0.0 and SwiftInkRuntime; the app still builds and runs.
2. **Runway is explicit** — The warning text contains "v3.0.0" so the consumer knows the
   removal version, matching the migration guide and parity statement.
3. **Non-breaking (boundary)** — A CI build that treats warnings as warnings (not errors)
   still goes green; the JS-bridge behaviour is unchanged (a full story still plays).

#### UAT Scenarios (BDD)
```gherkin
Scenario: Building against the JS-bridge surfaces a legacy warning
  Given a consumer app that calls "let story = InkStory()"
  When it is compiled against the InkSwift JS-bridge
  Then the Swift compiler emits a deprecation warning on InkStory
  And the warning names the removal version v3.0.0
  And the warning names SwiftInkRuntime and points to the migration guide

Scenario: The deprecation does not break the build
  Given the deprecated InkStory API
  When a consumer compiles normally (warnings not treated as errors)
  Then the build succeeds and the JS-bridge still plays a story
  And no public API has been removed

Scenario: The runway version is consistent everywhere
  Given the deprecation warning names v3.0.0
  When a consumer cross-checks the migration guide and parity statement
  Then both also name v3.0.0 as the removal version
```

#### Acceptance Criteria
- [ ] Compiling against `InkStory` emits a Swift deprecation warning whose text names the removal version **v3.0.0**, names `SwiftInkRuntime`, and references the migration guide.
- [ ] The deprecation is a warning, not an error: existing consumer builds still succeed; no public API is removed; the JS-bridge still plays stories (guardrail).
- [ ] The removal version in the warning matches the migration guide (US-03) and parity statement (US-04) exactly (`removal-version` shared artifact).

#### Outcome KPIs (link)
KPI-2 (consumers see the warning & can find the guide), KPI-5 (guardrail: 0 build breaks).

#### Technical Notes
- Touches `Sources/InkSwift/InkStory.swift` (adds a deprecation attribute to the public
  `InkStory` type / entry points). **Open for DESIGN/DELIVER**: exact `@available`
  spelling, whether to deprecate the type vs individual entry points, any `renamed:`.
- Warning-text CONTENT is the requirement (it is user-observable compiler output);
  attribute mechanics are not prescribed here (DISCUSS-scope convention).
- Depends on US-03 + US-04 so the referenced guide + runway exist when the message ships.

---

### US-03 — Migration guide maps InkStory to the native API

**job_id**: job-runtime-consolidation · **Slice**: 03 · **MoSCoW**: Must · **Depends on**: US-04

#### Elevator Pitch
- **Before**: A consumer who wants to migrate has to reverse-engineer the mapping
  from `InkStory` to the native `Story`/`InkCompiler` API by reading source — and can't
  tell which calls have no native equivalent.
- **After**: A consumer opens `docs/how-to/migrate-from-js-bridge.md` and finds a table
  mapping every `InkStory` public call to its native `Story`/`InkCompiler` equivalent,
  including shape differences and the one call with **no native equivalent** (Combine
  reactive observation).
- **Decision enabled**: the consumer can *rewrite their code call-by-call* and knows in
  advance the single place they must find a workaround.

#### Problem
An existing consumer (Maarten) has decided to evaluate migrating. He finds it a blocker
that there is no guide mapping his `InkStory` calls to native — `continueStory()` vs
`continue()`, `options` vs `currentChoices`, `stateToJSON()` (String) vs `saveState()`
(Data), and especially whether his Combine variable-observation code has any native
equivalent (it does not).

#### Who
- Maarten / Nadia (existing consumer, migrating) | translating real `InkStory` calls | needs a complete, honest one-for-one mapping.

#### Solution
Publish a migration guide (`docs/how-to/migrate-from-js-bridge.md`) with an
`InkStory → Story/InkCompiler` mapping table covering the full public surface,
flagging shape differences and the no-equivalent Combine-observation gap, and naming the
v3.0.0 runway. Backbone table:

| JS-bridge (`InkStory`) | Native (`Story` / `InkCompiler`) |
|---|---|
| `InkStory()` + `loadStory(json:)` | `Story(blueprint: try StoryBlueprint(json:))` |
| `loadStory(ink:)` (in-process compile) | `Story(blueprint: try InkCompiler.compile(source:))` |
| `continueStory()` | `continue()` |
| `canContinue` / `currentText` / `currentErrors` | same names |
| `options: [Option]` | `currentChoices: [Choice]` |
| `chooseChoiceIndex(_:)` | `chooseChoice(at:) throws` |
| `moveToKnitStitch(_:stitch:)` | `moveToKnot(_:stitch:) throws` |
| `currentTags: [String:String]` | `currentTags: [String]` (shape differs) |
| `globalTags: [String:String]` | `globalTags: [String]` (shape differs) |
| `getVariable(_:) -> JXValue` | `getVariable(_:) -> Any?` |
| `setVariable(_:to:)` String/Int/Double overloads | `setVariable(_:to: some Any)` |
| `stateToJSON() -> String` / `loadState(_:)` | `saveState() throws -> Data` / `restoreState(_:) throws` (String→Data) |
| `registerObservedVariable` / `oberservedVariables` / Combine observe | ⚠️ **no native equivalent** (Combine observation gap) |
| — | native extras: `visitCount(forKnot:)`, `continueMaximally()` |

#### Domain Examples
1. **Playback loop migration** — A consumer's `while story.canContinue { story.continueStory() }`
   maps to `while story.canContinue { try story.continue() }` per the guide's basic-flow row.
2. **State migration (shape change)** — A consumer's `stateToJSON()` String save maps to
   `saveState() -> Data`; the guide flags the String→Data shape change and the `throws`.
3. **Combine gap (no equivalent)** — A consumer using `registerObservedVariable` +
   Combine `@Published` observation finds the guide's ⚠️ row stating there is no native
   equivalent, so they know to poll `getVariable` or stay on the bridge.

#### UAT Scenarios (BDD)
```gherkin
Scenario: Every InkStory public call has a mapping row
  Given the migration guide's InkStory-to-native table
  When a consumer looks up any public InkStory method or property they use
  Then the table has a row mapping it to a native equivalent or an explicit "no equivalent"

Scenario: Shape differences are called out, not hidden
  Given a consumer migrating state persistence and tags
  When they read the mapping for stateToJSON/loadState and currentTags/globalTags
  Then the guide flags String-to-Data for state and dictionary-to-array for tags

Scenario: The Combine-observation gap is stated explicitly
  Given a consumer using registerObservedVariable and Combine observation
  When they read the migration guide
  Then the guide states there is no native equivalent for Combine reactive observation
```

#### Acceptance Criteria
- [ ] `docs/how-to/migrate-from-js-bridge.md` exists and maps 100% of the `InkStory` public API (per `Sources/InkSwift/InkStory.swift`) to a native equivalent or an explicit "no native equivalent".
- [ ] Shape differences are flagged: tags `[String:String]`→`[String]`, state `String`→`Data`, `getVariable` `JXValue`→`Any?`, and the added `throws` on choice/knot/state calls.
- [ ] The Combine reactive-observation gap is stated explicitly as having no native equivalent; the guide names the v3.0.0 runway.

#### Outcome KPIs (link)
KPI-3 (guide covers 100% of the public surface incl. the no-equivalent gap).

#### Technical Notes
- Source of truth for the public surface: `Sources/InkSwift/InkStory.swift` (verified —
  incl. `retainTags`, `deregisterObservedVariable`, and the `Option` struct). Native
  targets: `Sources/SwiftInkRuntime/Facade/Story.swift`, `StoryBlueprint.swift`,
  `Compiler/InkCompiler.swift`.
- New doc; no code change. Depends on US-04 for the gaps cross-reference.

---

### US-04 — Honest supported-parity / known-gaps statement (living backlog)

**job_id**: job-runtime-consolidation · **Slice**: 04 · **MoSCoW**: Must

#### Elevator Pitch
- **Before**: A consumer weighing migration has no honest, single place telling them
  what native *can't* do yet — so they either distrust an implied "parity" or discover a
  gap after shipping.
- **After**: A consumer opens `docs/reference/js-bridge-vs-native-parity.md` and reads:
  "We recommend SwiftInkRuntime for new projects. Known gaps vs the JS-bridge:
  <LIST, RANDOM/SEED_RANDOM, threads, EXTERNAL, shuffle `{~a|b}`; Combine observation,
  tag shape, error handling>. Stay on the JS-bridge if you need any of these."
- **Decision enabled**: the consumer can *self-select migrate vs stay* against their
  actual story's feature use — no over-claim to distrust.

#### Problem
An existing consumer (Nadia/Maarten) needs to know honestly whether native can run
*their* story before committing to migrate. She finds it impossible today: there is no
published parity statement, and an implied "full parity" would be untrustworthy given
native genuinely cannot play LIST, RANDOM, threads, EXTERNAL, or shuffle, and has no
Combine observation.

#### Who
- Nadia / Maarten (existing consumer deciding) | comparing native's supported set against their story | needs an honest, complete, maintained gaps list.

#### Solution
Publish a supported-parity / known-gaps statement (`docs/reference/js-bridge-vs-native-parity.md`)
that **encourages migration with gaps documented** (never "full parity"). It aggregates
two gap sources without duplicating the SSOT:
- **Feature (construct) gaps** — it **references `docs/product/ink-feature-reference.md`**
  (the construct SSOT, MUST-REJECT rows) for LIST, RANDOM/SEED_RANDOM, threads `<-`,
  EXTERNAL functions, and shuffle `{~a|b}` — it does not re-list them independently.
- **API gaps** — Combine reactive observation (no native equivalent), tag shape
  (`[String:String]` → `[String]`), and error handling (`currentErrors` array vs native `throws`).

**Living parity backlog convention** (maintainer): this list is the native runtime's
*to-do list toward v3.0.0*, not a one-time snapshot. **Each later feature that closes a
gap** — moves a construct MUST-REJECT → MUST-COMPILE in `ink-feature-reference.md`, or
lands a missing API-parity capability (e.g. Combine observation) — MUST revisit this
statement and **prune the closed item as part of its GREEN/finalize step**. The
maintenance note recording this already lives at the top of the "Known gaps / future
work" section of `ink-feature-reference.md`; this statement restates it for the API gaps
it owns.

#### Domain Examples
1. **LIST/RANDOM user stays** — Nadia's story uses a `LIST` and `RANDOM`; the statement
   lists both (via the construct SSOT) as gaps and advises staying on the JS-bridge.
2. **Combine user stays** — A consumer relying on Combine variable observation reads the
   API-gaps section, sees "no native equivalent", and stays on the bridge for that reason.
3. **No-gap user migrates (boundary)** — A consumer whose story uses only supported
   constructs and no Combine reads the statement, finds none of their features listed,
   and migrates with confidence.
4. **Backlog stays accurate** — When a future feature moves shuffle `{~a|b}` to
   MUST-COMPILE, that feature prunes shuffle from this statement at finalize — a later
   reader never sees a closed gap still listed.

#### UAT Scenarios (BDD)
```gherkin
Scenario: The parity statement is honest, not a full-parity claim
  Given the supported-parity / known-gaps statement
  When a consumer reads it
  Then it recommends SwiftInkRuntime with an explicit "Known gaps vs the JS-bridge" list
  And it advises staying on the JS-bridge for those gaps
  And it makes no "full parity" claim

Scenario: Construct gaps reference the feature-reference SSOT
  Given the parity statement lists feature (construct) gaps
  When a consumer checks LIST, RANDOM, threads, EXTERNAL, and shuffle
  Then those are sourced from docs/product/ink-feature-reference.md (not duplicated)
  And the API gaps (Combine observation, tag shape, error handling) are listed alongside

Scenario: A consumer with an unsupported feature is correctly told to stay
  Given a consumer whose story uses a LIST and Combine variable observation
  When they read the parity statement
  Then both are listed as gaps and they are advised to stay on the JS-bridge

Scenario: The gap list is maintained as a living backlog
  Given the parity statement documents the living-backlog maintenance convention
  When a future feature closes a gap
  Then that feature prunes the closed item from the list at its finalize step
  And no closed gap remains listed after the feature that closed it
```

#### Acceptance Criteria
- [ ] `docs/reference/js-bridge-vs-native-parity.md` exists, recommends `SwiftInkRuntime`, lists the known gaps, advises staying on the JS-bridge for them, and makes no "full parity" claim.
- [ ] Feature (construct) gaps **reference `docs/product/ink-feature-reference.md`** (LIST, RANDOM/SEED_RANDOM, threads, EXTERNAL, shuffle) rather than duplicating the list; API gaps (Combine observation, tag shape, error handling) are stated alongside.
- [ ] The statement documents the living-parity-backlog maintenance convention (each gap-closing feature prunes the closed item at finalize); it names the v3.0.0 endpoint.

#### Outcome KPIs (link)
KPI-4 (gaps list complete & honest), KPI-6 (backlog accuracy: no stale closed gap).

#### Technical Notes
- Construct-gap SSOT: `docs/product/ink-feature-reference.md` MUST-REJECT rows (28, 36–39
  per ground truth); the maintenance note already lives at the top of its "Known gaps /
  future work" section. API gaps derive from the `InkStory` vs native surface (US-03 table).
- New doc; no code change. Referenced by US-01 (README) and US-03 (migration guide).

---

## Wave: DISCUSS / [REF] Outcome KPIs

### Objective
Within this feature's cycle, turn the existing JS-bridge consumer from "uncertain about
a possibly-dying runtime" into a consumer who can make an informed, eyes-open
migrate/stay/wait decision — nudged toward the recommended native runtime, honestly.

> Measurement caveat (honest): InkSwift is an open-source SPM package with **no runtime
> telemetry**. These KPIs are therefore **content-completeness checks** (auditable
> against the SSOTs) plus **issue-tracker / discussion proxies** for behaviour change —
> not instrumented conversion metrics. This is stated so DEVOPS does not plan telemetry
> that cannot exist.

### Outcome KPIs

| # | Who | Does What | By How Much | Baseline | Measured By | Type |
|---|-----|-----------|-------------|----------|-------------|------|
| 1 | New InkSwift adopter | starts new projects on `SwiftInkRuntime` rather than the JS-bridge | new-project questions/issues predominantly reference the native runtime | today README markets the JS-bridge; native called "experimental" | issue-tracker / discussion references (proxy) | Leading (secondary) |
| 2 | Existing JS-bridge (v2.x) consumer | on rebuild, sees the deprecation warning and can reach the migration guide | 100% of consumers compiling `InkStory` see the warning; the guide link resolves | 0 (no signal today) | compiler-warning presence + link validity (doc audit) | Leading |
| 3 | Existing consumer evaluating migration | maps their `InkStory` usage to native without asking the maintainer | migration guide covers 100% of the `InkStory` public API (incl. the no-equivalent Combine gap) | 0 (no guide) | API-coverage audit vs `InkStory.swift` public surface | Leading |
| 4 | Existing consumer | self-selects stay-vs-migrate against their story's features | published gaps list names 100% of known feature + API gaps | 0 (undocumented) | gaps-list completeness vs `ink-feature-reference.md` MUST-REJECT rows + API no-equivalent rows | Leading (secondary) |
| 5 | Every existing consumer (guardrail) | keeps building against the deprecated JS-bridge without breakage | 0 builds break; macOS + Linux suites stay green; 0 public API removed | builds pass today | `swift build`/`swift test` on macOS + Linux (warning, not error) | Guardrail |
| 6 | Future maintainers/consumers (backlog accuracy) | never see a closed gap still listed | 0 stale (closed) gaps remain after the feature that closed them | N/A (list created here) | gap-list ↔ `ink-feature-reference.md` MUST-COMPILE diff at each feature's finalize | Guardrail |

### Metric Hierarchy
- **North Star**: an existing consumer can make an informed migrate/stay/wait decision
  unaided (KPI-2 × KPI-3 × KPI-4 all complete).
- **Leading indicators**: deprecation-warning reach (KPI-2); migration-guide coverage
  (KPI-3); gaps-list completeness (KPI-4).
- **Guardrail metrics** (must NOT degrade): 0 consumer build breaks & suites green
  (KPI-5); 0 stale closed gaps in the living backlog (KPI-6).

### Measurement Plan
| KPI | Data Source | Collection | Frequency | Owner |
|-----|------------|-----------|-----------|-------|
| 1 | issue tracker / discussions | manual reference tally (proxy) | periodic | maintainer |
| 2 | consumer build output + doc | warning-present check + link audit | at release + on doc change | DELIVER / maintainer |
| 3 | `InkStory.swift` vs guide | public-API coverage audit | at release + when `InkStory` changes | DISTILL / DELIVER |
| 4 | `ink-feature-reference.md` + API rows | gaps-list completeness diff | at release | DISTILL / DELIVER |
| 5 | macOS + Linux CI | `swift build`/`swift test` green, warning-not-error | every push | DEVOPS |
| 6 | `ink-feature-reference.md` MUST-COMPILE diff | prune-on-finalize check | at every gap-closing feature's finalize | maintainer |

### Hypothesis
We believe that repositioning the README, a non-breaking v3.0.0 deprecation signal, a
complete migration guide, and an honest living-backlog parity statement for the
**existing JS-bridge consumer** will let them decide about migrating with confidence. We
will know this is true when the deprecation warning reaches 100% of `InkStory`
consumers, the guide covers 100% of the public API, and the gaps list names 100% of
known gaps — with 0 consumer builds broken.

> Test-quality note: this feature's checks are largely documentation-accuracy audits;
> where behaviour is involved (US-02 warning-not-error) it is validated by the build/CI
> gate, not mutation kill-rate (mutation testing is disabled project-wide).

---

## Wave: DISCUSS / [REF] Changed Assumptions

> **Back-propagation contract**: this feature sets a course that contradicts a
> deliberate decision recorded by the just-finalized `native-runtime-linux` feature.
> Documented here per the DISCUSS back-propagation contract. **The evolution doc is
> NOT modified.**

**Prior decision (verbatim)** — `docs/evolution/2026-07-16-native-runtime-linux.md`,
"Falsified Assumptions" #2:

> **"The `InkSwift` JS-bridge is Apple-only and Linux CI does not build it."** False:
> JXKit **3.6.0 ships a Linux JavaScriptCoreGTK backend**, so the JS-bridge *does* build
> and test on Linux (needs the `libjavascriptcoregtk-4.1-dev` system lib). The correct
> call was to **keep** it on Linux, not exclude it — excluding the `InkSwift` product
> would be a **breaking change** for existing Linux consumers (a published open-source
> package). This was a deliberate maintainer decision over architectural tidiness.

And Lesson 4: *"Not-breaking-consumers beats architectural tidiness for a published
package — keeping the JS-bridge on Linux (vs excluding it) was the right maintainer call."*

**New direction (this feature)**: **deprecate now / remove in v3.0.0 later.** This
feature does **not** reverse that decision yet — the JS-bridge is *kept and remains fully
functional* on both Apple and Linux. It only (a) marks the JS-bridge `InkStory` API as
deprecated with a warning naming a **future** v3.0.0 removal, and (b) repositions native
as recommended. The actual removal (the breaking change the evolution doc protected
against) is deferred to a **separate future feature** and will be a deliberate,
announced major-version break — not a silent one.

**Rationale**: the native runtime is now approaching parity and, crucially, `job-linux-portability`
made it run identically on Linux — so "one recommended runtime for every platform" is
now credible, which it was not when the "keep the JS-bridge" decision was made. The
maintainer is consolidating on one runtime (less maintenance; drop the JavaScriptCore
system-lib dependency). The v3.0.0 runway + honest gaps list are precisely the
"don't-break-consumers" discipline from Lesson 4, applied to a *planned* removal:
consumers get advance, versioned notice and a migration path instead of a surprise break.

**Continuity, not contradiction, of the principle**: the evolution doc's underlying
principle ("don't break published consumers") is *honored*, not overturned — this
feature breaks nobody today and gives a long runway. Only the tactical assumption ("keep
the JS-bridge indefinitely / it is Apple-only") is superseded by "keep it now, remove it
deliberately at v3.0.0".

---

## Wave: DISCUSS / [REF] Definition of Ready — Validation

9-item hard gate, per story. Evidence summarized; full ACs above.

| DoR Item | US-01 | US-02 | US-03 | US-04 |
|---|---|---|---|---|
| 1. Problem in domain language | PASS | PASS | PASS | PASS |
| 2. Persona w/ specific characteristics | PASS (existing JS-bridge consumer: Maarten/Nadia) | PASS | PASS | PASS |
| 3. 3+ domain examples, real data | PASS (new adopter, LIST user, stale-claim) | PASS (InkStory(), v3.0.0, CI green) | PASS (loop, state shape, Combine gap) | PASS (LIST/RANDOM, Combine, no-gap, prune) |
| 4. UAT in GWT (3-7) | PASS (3) | PASS (3) | PASS (3) | PASS (4) |
| 5. AC derived from UAT | PASS | PASS | PASS | PASS |
| 6. Right-sized (1-3 days, 3-7 scenarios) | PASS (~0.5d, 3) | PASS (~0.5d, 3) | PASS (~1d, 3) | PASS (~1d, 4) |
| 7. Technical notes (constraints) | PASS | PASS (mechanics deferred to DESIGN) | PASS | PASS |
| 8. Dependencies resolved/tracked | PASS (US-03, US-04) | PASS (US-03, US-04) | PASS (US-04) | PASS (none) |
| 9. Outcome KPIs w/ measurable targets | PASS (KPI-1,4) | PASS (KPI-2,5) | PASS (KPI-3) | PASS (KPI-4,6) |

**Elevator Pitch (Dimension 0) check**: all 4 stories have Before/After/Decision-enabled;
every "After" references a real driving port (the README, the compiler deprecation
warning on `import InkSwift`, the migration-guide doc, the parity-statement doc) with
concrete observable output (recommendation + gaps text, the warning string naming
v3.0.0, the rendered mapping table, the rendered gaps list). No `@infrastructure` story;
no slice is infra-only (each slice IS a user-visible deliverable). **JTBD traceability**:
every story carries `job_id: job-runtime-consolidation`.

### DoR Status: PASSED (all 4 stories, all 9 items + Elevator Pitch gate)

---

## Wave: DISCUSS / [REF] Wave Decisions Summary

Locked decisions (carried in from the orchestrator + this wave):

- **D-1 (Feature type)**: Cross-cutting — docs + deprecation signal + packaging +
  possible API-parity alignment. Mandatory JTBD; no walking skeleton (brownfield);
  comprehensive research depth.
- **D-2 (Scope = nudge only)**: IN — reposition README (US-01), `@available` deprecation
  on `InkStory` (US-02), migration guide (US-03), honest parity/gaps statement (US-04).
  OUT — actually removing/repurposing the JS-bridge (separate future feature).
- **D-3 (Parity tone)**: "Encourage, gaps documented." Never over-claim "full parity".
- **D-4 (Removal endpoint)**: v3.0.0 breaking major removal (future feature); the
  deprecation MESSAGE this feature ships names v3.0.0.
- **D-5 (Persona)**: reuse Maarten (primary) + Nadia (secondary) as the existing
  JS-bridge consumer; no new persona file.
- **D-6 (Construct-gap SSOT)**: `docs/product/ink-feature-reference.md` — the parity
  statement references it, does not duplicate.
- **D-7 (Living parity backlog)**: the gaps list is a maintained backlog; each
  gap-closing feature prunes the closed item at finalize (KPI-6 guardrail).
- **D-8 (Guardrail)**: deprecation is a warning, not an error; no consumer build breaks;
  macOS + Linux suites stay green; JS-bridge remains fully functional.

**Prior-wave consultation**: **No DISCOVER/DIVERGE artifacts exist for this feature**
(new). Noted as a **risk**: JTBD grounding was authored fresh in this wave rather than
inherited from a validated DIVERGE recommendation. Mitigated by the existing `maarten`
and `nadia` personas, the ground-truth API mapping + gaps list supplied by the
maintainer, and the delivered `native-runtime` / `native-ink-compiler` /
`native-runtime-linux` features providing strong domain grounding.

**Ask-intelligent expansion triggers**: evaluated — **one candidate fired** (see below).
Two existing personas (the ≥3-persona multi-stakeholder trigger does not fire); scope is
right-sized (no split trigger).

---

## Wave: DISCUSS / [REF] Density / Expansion Menu

Density = **lean + ask-intelligent** (DISCUSS hard default): Tier-1 [REF] sections only.

**Trigger-fired expansion offered — `migration-playbook` [HOW]**: this feature *is* a
migration, and the strongest single downstream aid for the consumer is a step-by-step
migration playbook (walk a real `InkStory`-based app to `SwiftInkRuntime` end-to-end:
swap the dependency, rewrite the playback loop, port state persistence String→Data,
handle the Combine-observation gap with a polling workaround, and verify with the
oracle). The [HOW] expansion is **strongly warranted** here and is **offered at wave
end**, not auto-authored (lean default). If accepted, it would live at
`docs/how-to/migrate-from-js-bridge-playbook.md` and complement the US-03 reference-style
mapping table with a task-oriented (Diataxis how-to) walkthrough.

No other expansion menu items surfaced.

---

## Wave: DISCUSS / [REF] Open Questions for DESIGN

1. **`@available` deprecation mechanics** (US-02). Deprecate the `InkStory` *type*, or
   its individual public entry points, or both? Use `message:` only, or also `renamed:`
   pointing at a native symbol (note: native lives in a different module, so `renamed:`
   may not resolve cleanly)? DISCUSS fixes the warning-text CONTENT (names v3.0.0 +
   SwiftInkRuntime + guide); DESIGN/DELIVER choose the attribute form.
   `Sources/InkSwift/InkStory.swift`.
2. **Doc homes & cross-links** (US-03/US-04). Confirm `docs/how-to/migrate-from-js-bridge.md`
   (how-to) and `docs/reference/js-bridge-vs-native-parity.md` (reference) as the Diataxis
   homes, and that the README (US-01) links both. Confirm the parity statement's
   API-gaps section is the SSOT for the non-construct gaps (Combine, tag-shape, errors)
   while construct gaps reference `ink-feature-reference.md`.

---

## Wave: DISCUSS / [REF] Handoff

- **→ solution-architect (DESIGN)**: this feature-delta + journey SSOT + slice briefs +
  the two open questions (esp. `@available` mechanics). Note: near-zero architecture
  surface — one deprecation attribute + three docs.
- **→ platform-architect (DEVOPS)**: outcome KPIs — esp. KPI-5 (guardrail: warning not
  error, suites green on macOS + Linux) and the honest "no telemetry" measurement caveat.
- **→ acceptance-designer (DISTILL)**: journey Gherkin (happy path + deprecation-not-a-break
  + honest-gap-keeps-consumer) + embedded UAT scenarios + System Constraints (backtick
  style, `.disabled` AT authoring, doc-accuracy verification, living-backlog convention).
  Most ACs are documentation-accuracy audits; US-02 needs a compile that emits the
  expected warning WITHOUT erroring.

---

## Wave: DESIGN / [REF] Design Decisions (DDD)

Application scope (propose mode). Near-zero architecture surface — one non-behavioral
attribute + two docs. Full detail in `docs/product/architecture/brief.md`
(`### native-runtime-migration (Feature Addition)`) + `adr-015-inkstory-deprecation-mechanics.md`.

- **DD-1 — `@available` FORM = type-level `message:`, NO `renamed:`** (ADR-015,
  **status Accepted — maintainer confirmed Option 1, 2026-07-16**). `@available(*, deprecated,
  message: "…v3.0.0 … SwiftInkRuntime … migration guide")` on the `InkStory` type.
  Rejects `renamed: "Story"` (native `Story` is a *different module* and NOT
  API-compatible → the fix-it produces non-compiling code, violating the feature's honesty
  goal). Rejects per-member annotation (Option 2: ~20 noisy sites, negligible extra reach).
- **DD-2 — Axis `*, deprecated` (unconditional, all-platform) → WARNING, not error.**
  Guardrail PASS. Known edge: a consumer opting into warnings-as-errors sees an error —
  their opt-in, not a break this feature imposes; suppression path documented in the guide.
- **DD-3 — `InkSwift` invariant REFINED to "behaviorally frozen".** The `native-runtime`
  D8 / ADR-002 "frozen — no changes permitted" invariant is narrowed to *no behavioral /
  logic / API-signature change; the sole permitted edit is a non-behavioral `@available`
  annotation*. `brief.md` L46 (Container node) + L103 (folder layout) updated in place;
  ADR-002 **refined, not edited** (ADRs are immutable). See Changed Assumptions.
- **DD-4 — Diataxis doc homes confirmed** (Open Question 2). how-to =
  `docs/how-to/migrate-from-js-bridge.md` (SSOT for the `api-mapping-table`); reference =
  `docs/reference/js-bridge-vs-native-parity.md` (SSOT for the **API** gaps — Combine,
  tag-shape, error-handling — and **references** `ink-feature-reference.md` for construct
  gaps, no duplication). README links both. No separate playbook doc — folded into how-to.
- **DD-5 — Outcome Collision Check = N/A.** `docs/product/outcomes/registry.yaml` does not
  exist; registry not bootstrapped; CLI not run.

## Wave: DESIGN / [REF] Component Decomposition

| Component | File | Change | Kind |
|---|---|---|---|
| `InkStory` (public type) | `Sources/InkSwift/InkStory.swift` | **EXTEND** — attach one `@available` attribute (~3 lines); zero behavior | code |
| `Option` (public struct) | `Sources/InkSwift/InkStory.swift` | **EXTEND (optional)** — same attribute for symmetry; DELIVER decides | code |
| Migration guide | `docs/how-to/migrate-from-js-bridge.md` | **CREATE NEW** (doc, not a code component) | doc |
| Parity statement | `docs/reference/js-bridge-vs-native-parity.md` | **CREATE NEW** (doc, not a code component) | doc |
| README | `README.md` | **EXTEND** — reposition + link both docs | doc |

No new module, target, port, adapter, or runtime dependency.

## Wave: DESIGN / [REF] Driving Ports

- **Swift compiler deprecation warning** on any consumer build against `import InkSwift` /
  `InkStory` — the new observable surface (US-02).
- **README**, **migration-guide doc**, **parity-statement doc** — documentation surfaces.

No new programmatic driving port (no CLI/HTTP/skill entry point added).

## Wave: DESIGN / [REF] Driven Ports & Adapters

**None.** The feature adds no outbound side-effect. The `@available` attribute is
compile-time only (mutation universe ∅); the docs are static content. No adapter mapping.

## Wave: DESIGN / [REF] Technology Choices

| Choice | Version / License | Rationale |
|---|---|---|
| Swift `@available(*, deprecated, message:)` | language feature (Apache 2.0) | Native, zero-dependency deprecation; warning honored by `swift build` + Xcode |
| Markdown Diataxis docs (how-to + reference) | n/a | Plain repo docs; no tooling change |

No new runtime or dev dependency. Existing SwiftLint R1/R3/R5 + Swift access control cover
the change unchanged; no new architecture boundary rule needed.

## Wave: DESIGN / [REF] Decisions Table

| DDD | Decision | Status |
|---|---|---|
| DD-1 | Type-level `@available` `message:`, no `renamed:` (ADR-015) | Accepted (Option 1, 2026-07-16) |
| DD-2 | Axis `*, deprecated` → warning not error | Locked |
| DD-3 | `InkSwift` refined to *behaviorally* frozen | Locked (brief.md + ADR-002 refined) |
| DD-4 | Diataxis homes (how-to + reference), README links both | Locked |
| DD-5 | Outcome Collision Check N/A (no registry) | Locked |

## Wave: DESIGN / [REF] Reuse Analysis

Zero unjustified CREATE NEW (full table with contract-shape · mutation-universe columns in
`brief.md`). Summary: `InkStory`/`Option` = **EXTEND** (pure annotation, universe ∅);
README = **EXTEND** (doc); the two migration docs = **CREATE NEW (doc, not code)** — no new
module/target/port. A new *type* would be absurd: the goal is to signal legacy on the
existing type in place.

## Wave: DESIGN / [REF] Changed Assumptions

**Refines the `native-runtime` D8 / ADR-002 "frozen `InkSwift`" invariant.** Original
(quoted verbatim in `brief.md`): Container node L46 *"…existing, frozen … No changes
permitted."*; folder layout L103 *"existing module, frozen, no changes"*; ADR-002 §3
*"InkStory.swift is frozen — zero changes."* → **Refined**: `InkSwift` is *behaviorally*
frozen — no logic/behavior/API-signature change; the sole permitted modification is a
non-behavioral `@available` deprecation annotation, which changes zero runtime behavior.
**Rationale**: the freeze protected (a) behavioral stability for published consumers and
(b) the JS-bridge's macOS-oracle role; a deprecation attribute preserves both. `brief.md`
frozen-language updated in place; ADR-002 refined (not edited). **No upstream story/AC
change** — the DISCUSS US-02 guardrail ("warning, not error; no public API removed")
already scopes this exactly; no `design/upstream-changes.md` needed.

## Wave: DESIGN / [REF] Open Questions (deferred to DISTILL/DELIVER)

1. **ADR-015 accepted.** Maintainer confirmed **Option 1** (2026-07-16); ADR-015 is
   Accepted. (Resolved.)
2. **`Option` annotation.** DELIVER decides whether `Option` also carries the attribute
   (reach-neutral — its only access path is the already-deprecated `InkStory.options`).
3. **Warnings-as-errors suppression wording** in the migration guide (DELIVER content).
4. **US-02 verification shape.** DISTILL authors the AT as a build-log assertion: the
   deprecation string is present AND the build succeeds (warning, not error).
