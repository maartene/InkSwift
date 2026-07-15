# Slice 04 — Linux CI Guards Parity

**Feature**: native-runtime-linux
**Story**: US-04
**Job**: job-linux-portability
**Size**: ≤ 1 day
**Depends on**: Slices 01–03 (a green Linux suite exists to run)

## Learning hypothesis

> The full committed-fixture oracle suite that passes on a developer's Linux host
> also passes on a clean Linux CI runner — with no hidden macOS-only dependency
> leaking in — and turning it red on a Linux-only regression is visible before merge.

Closes the "green on my Mac, broken on Linux, nobody noticed" gap. This is a
user-facing outcome for Nadia (a Linux CI signal she can trust), NOT pure
infrastructure — she makes a real merge/no-merge decision from the job status.

## In scope

- A Linux `swift test` job added to `.forgejo/workflows/tests.yml`, running the
  committed-fixture oracle suite on every push and pull_request.
- Confirmation that the suite is green on a clean Linux runner (no macOS-only leak).

## Out of scope

- Introducing new test content (the corpus comes from Slices 01–03).
- The macOS job and the SwiftLint boundary job (already present, unchanged).
- The JS-bridge module (`.target ... condition: .when(platforms: [.macOS])` is
  already correct — Linux CI simply won't build it).
- Deployment/observability instrumentation → DEVOPS handoff (outcome KPIs feed it).

## Real-story data (not synthetic)

- The same committed fixtures (The Intercept + compiler corpus) the local Linux
  suite runs in Slices 02–03 — one source of truth, exercised by CI.

## Dogfood moment

Push a branch; watch the forgejo workflow report a green **Linux** job next to the
macOS job. Introduce a deliberate Linux-only regression on a scratch branch and
confirm the Linux job turns red while macOS stays green.

## Taste tests

- **Thin?** Yes — one CI job addition over an existing green suite.
- **End-to-end?** Yes — push → Linux runner builds+tests → visible red/green signal.
- **User-visible?** Yes — the CI job status is the observable output Nadia acts on.
- **Independent value?** Yes — makes Linux a continuously-verified first-class target.
- **Not infra-only?** Correct — enables Nadia's merge/no-merge decision (has an Elevator Pitch, not `@infrastructure`).

## Acceptance criteria

See US-04 in `../feature-delta.md`. Green = a Linux job runs on every push and
reports pass/fail from the committed-fixture oracle suite.
