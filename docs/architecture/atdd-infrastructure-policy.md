# ATDD Infrastructure Policy

Per `nw-distill` § Project Infrastructure Policy. One file per project. Apply-if-exists;
write-if-absent; rewrite with `--policy=fresh`. Git history is the audit trail.

**Project**: InkSwift (Swift Package Manager library). Acceptance tests are
**Swift Testing** `@Test func` suites with backtick function names (per `CLAUDE.md`),
NOT Gherkin/pytest-bdd. Correctness is judged by the **execution-equivalence oracle**
(inklecate / InkSwift JS-bridge) replaying committed fixtures — see
`Tests/SwiftInkRuntimeTests/Acceptance/`.

Bootstrapped: 2026-06-14 (first DISTILL — feature `native-ink-compiler`).

## Driving
| Port | Mechanism | Note |
|---|---|---|
| `InkCompiler.compile(source:)` / `compile(fileURL:)` | In-process call via `@testable import SwiftInkRuntime` | Primary compile entry point (DDD-10). |
| `InkCompiler.emitJSON(source:)` | In-process call | Secondary Ink-JSON sink (D4). |
| `Story(inkSource:)` | In-process convenience init (Compiler-layer extension) | Source→playable `Story` (DWD-1). |
| `Story` runtime facade (`init(blueprint:)`, `continue()`, `chooseChoice(at:)`) | In-process call | Plays the compiled story; existing runtime driving surface. |

## Driven internal (real)
| Port | Mechanism | Note |
|---|---|---|
| Runnable-story tree (`ContainerNode`) | Real, in-memory — codegen output consumed directly by `Story` | No JSON round-trip (D3). The compiled blueprint IS the integration contract. |
| Source / INCLUDE filesystem read (`SourceReader`, future) | Real I/O from the test bundle (`Bundle.module`) / `tmp` | Earned-Trust `probe()` (DESIGN). DISTILL corpus is read as bundled `.process` resources. |

## Driven external / non-deterministic (fake / test-only)
| Port | Fake | Note |
|---|---|---|
| inklecate compiler | **Committed `.ink.json` oracle fixtures**, generated OFFLINE (`inklecate -o x.ink.json x.ink`) | Test-only/offline (DDD-10). CI never invokes inklecate; it consumes committed fixtures. REGEN by re-running inklecate and committing. |
| InkSwift JS-bridge (`InkStory`) | Real, but `#if os(macOS)`-gated oracle | Secondary ground-truth oracle on macOS, as the existing Milestone harness uses it. Frozen module (D8). |
