# ADR-006: Compiler Output Contract and Module Placement

**Status**: Accepted (user-confirmed 2026-06-14)
**Date**: 2026-06-14
**Deciders**: Maarten Engels (project owner), Morgan (nw-solution-architect)
**Feature**: native-ink-compiler

---

## Context

The `native-ink-compiler` feature adds a native, in-process Swift compiler that converts `.ink` source into a runnable story the existing pure-Swift `SwiftInkRuntime` plays. DISCUSS decision **D3** wants the compiler's **primary output to be an in-process runnable story the runtime consumes directly, with no JSON round-trip**. D4 makes JSON a **secondary, lower-priority** artifact (oracle structural comparison, caching, interop).

The runtime's integration contract is fixed and was read directly:

- `StoryBlueprint` is a `public struct` in `Facade/`. Its only initializer is `public init(json: String) throws`. It wraps `let root: ContainerNode` (an `internal let`).
- `ContainerNode` and `NodeKind` are **internal** to `SwiftInkRuntime`. Boundary rule **R2** forbids making `NodeKind` public (a `public` modifier on `NodeKind` is a build-time error).
- `Story.init(blueprint: StoryBlueprint)` is the public construction path; `Story.init(json:)` is a convenience wrapper over `StoryBlueprint(json:)`.
- `InkDecoder` already transforms structured input (`[String: Any]` from `JSONSerialization`) into the `ContainerNode`/`NodeKind` tree. **The compiler's codegen target IS this tree.** The decoder is the existing "structured data → node tree" stage.

Achieving D3 literally (no JSON anywhere) requires the compiler to construct `ContainerNode`/`NodeKind` values and hand them to a `Story` without serialising to JSON and re-parsing. Because the node types are internal, where the compiler lives determines whether this is possible without piercing R2.

**Quality attributes for this decision**: Correctness (oracle-match), Maintainability (boundary integrity — R1/R2/R3), Testability, No new runtime dependencies, Simplicity (fewest moving parts), and honoring the parallel-module integration pattern.

---

## Decision

Adopt **Option A — co-locate the compiler as a new `Compiler/` layer inside the `SwiftInkRuntime` module**, and add a new **internal** `StoryBlueprint(root: ContainerNode)` initializer plus a thin **public** compile entry point on the facade.

Concretely:

- A new `Compiler/` source directory inside `Sources/SwiftInkRuntime/`. Its codegen stage constructs `ContainerNode`/`NodeKind` values directly (it is inside the module, so the internal node types are visible to it).
- `StoryBlueprint` gains an **internal** `init(root: ContainerNode)`. The existing `public init(json:)` is untouched. The internal init is the no-JSON path D3 requires; it constructs no JSON and invokes no decoder.
- A new public driving port — a compile entry point (working name `InkCompiler.compile(source:) throws -> StoryBlueprint`, or a `Story` convenience `init(inkSource:) throws`) — returns a runnable story (via `StoryBlueprint`) or throws a located `CompileError`.

**R2 preservation (explicit)**: the new initializer is `internal init(root: ContainerNode)`. Both the initializer *and* its parameter type (`ContainerNode`, which is `internal`) are non-public, so no internal type is leaked into the public API. There is no public constructor for `ContainerNode`/`NodeKind` anywhere; only code *inside* `SwiftInkRuntime` (the decoder and the co-located compiler) can construct them. Public callers still construct a story only via `StoryBlueprint(json:)` or the public compile entry. R2 ("`NodeKind` carries no `public` modifier; any `public` is a build-time error") is therefore preserved by construction — co-location grants visibility without export.

**DISCUSS decision traceability**: this ADR resolves D3 (no JSON round-trip — honored literally by the internal `init(root:)` path), D1 (compiler scope == runtime scope — Option A accepts only the internal node types the runtime already plays, so over-acceptance is structurally bounded), and D8 (frozen `InkSwift` — untouched by all options here).
- The secondary JSON emit (D4) is a separate, optional codegen sink: the same AST/codegen produces an Ink-JSON string for oracle structural comparison and caching. It does NOT sit on the primary runnable-story path.
- A new boundary rule **R5** governs the `Compiler/` layer's dependency direction (see Consequences and the brief).

---

## Alternatives Considered

### Option B — Separate compiler module depending on `SwiftInkRuntime`, reaching node types via `@_spi` / `package` access

A parallel `SwiftInkCompiler` SPM target that depends on `SwiftInkRuntime` and exposes `ContainerNode`/`NodeKind` across the module boundary using `package` access level or `@_spi(Compiler)`.

**Evaluation**:
- Keeps the compiler as a parallel module, matching the existing `InkSwift` ∥ `SwiftInkRuntime` topology aesthetically.
- **Pierces the encapsulation R2 was created to protect.** `package`/`@_spi` exposure of `NodeKind` across the module boundary is exactly the "NodeKind escapes its module" outcome R2 forbids in spirit, even if the literal `public` keyword is avoided. The protection becomes a convention (`@_spi` tag) rather than a language-enforced wall.
- `@_spi` is an underscored, semi-private Swift feature; relying on it for a load-bearing internal contract is fragile across toolchain versions.
- Requires the runtime to annotate and re-export internal types — a change to the runtime's public-ish surface that the decoder feature deliberately kept minimal.

**Rejection rationale**: Defeats R2's purpose, depends on an underscored language feature for a core contract, and grows the runtime's exported surface. Higher long-term maintenance risk than Option A for no correctness or simplicity gain.

### Option C — Compiler emits JSON; runnable-story path is `StoryBlueprint(json:)`

The compiler's codegen emits the Ink-JSON string the runtime already consumes. The runnable-story path is the existing `StoryBlueprint(json:)` → `InkDecoder.decode`.

**Evaluation**:
- **Simplest possible integration.** Zero new initializers, zero new boundary rules, R1/R2/R3 entirely untouched. Reuses `InkDecoder` and `StoryBlueprint(json:)` exactly as they are — maximum reuse, zero new runtime surface.
- Strong correctness leverage: emitting the same JSON the runtime is already validated against means Level-2 structural oracle comparison is the *native* output, not a secondary artifact.
- **But it relegates D3 to "logically in-process."** There is a real `String` JSON round-trip (codegen → JSON text → `JSONSerialization` → node tree) on the primary path. It is in-process (no subprocess, no inklecate), but it is not "no JSON round-trip." It inverts D3/D4: JSON becomes primary and the direct node tree is unreachable.
- Marginal, irrelevant performance cost (compile-time, document-sized input — not a hot path).

**Rejection rationale**: Contradicts the literal D3 ("no JSON round-trip") and inverts the D3/D4 priority the user set. Chosen as the *fallback* if the user, on reflection, values boundary-rule minimalism and JSON-as-oracle over a strict no-round-trip path. (See "If the user overrides" below.)

---

## Consequences

**Positive**:
- D3 is honored literally: the primary path constructs the node tree directly and hands it to `Story` with no JSON serialisation.
- R2 is preserved exactly — `NodeKind` and `ContainerNode` stay internal; the compiler sees them only because it is *inside* the module. Nothing is exported.
- D4 (secondary JSON) is a clean, optional sink off the same codegen — it does not compromise the primary path, and it doubles as the Level-2 oracle artifact.
- Maximum reuse downstream: the runtime's `InkEngine`/`TreeWalker` consume the compiler's output through the exact same `ContainerNode` they already consume from `InkDecoder`. The two producers (decoder, compiler) converge on one consumer contract.
- The frozen `InkSwift` module is untouched (D8).

**Negative**:
- The `SwiftInkRuntime` module grows: it now contains both a runtime and a compiler. Mitigated by R5 (the `Compiler/` layer is dependency-isolated) and by the fact that the node tree is the natural shared seam.
- A new boundary rule (**R5**) is required and must be enforced (see below). Without enforcement, the compiler could reach into `Engine/` internals.
- `StoryBlueprint` gains an internal initializer — a small, additive surface change to a `Facade/` type (still no new *public* surface beyond the compile entry point).

**New boundary rule R5** (defined fully in the brief):
> `Compiler/` may import the node types in `Decoder/` (it constructs `ContainerNode`/`NodeKind`). `Compiler/` may NOT import `Engine/` (no execution-state coupling) and may NOT call `JSONSerialization` on the primary path (R3 still binds — JSONSerialization stays in `Decoder/`; the secondary JSON *emitter* writes strings via `JSONEncoder`/manual string building in `Compiler/`, not `JSONSerialization` parsing). `Decoder/`, `Engine/`, and `Facade/` may NOT import `Compiler/` except the single facade compile entry point.

Enforcement: SwiftLint `custom_rules` (path-scoped import/call-site regexes, per ADR-004 / R1-R3 precedent) plus Swift access control. R5 is the language-appropriate architecture-rule enforcement mandated for every style choice.

---

## If the user overrides to Option C

If the user prefers boundary minimalism and JSON-as-native-oracle over a strict no-round-trip path: switch the primary path to emit JSON and construct the story via `StoryBlueprint(json:)`. No new initializer, no R5. D3 is then documented as "logically in-process (in-memory JSON round-trip, no external binary)"; D4's JSON becomes the primary artifact. This is a one-section revision to the feature-delta and this ADR; the rest of the component decomposition (lexer/parser/AST/codegen/error-reporter) is unchanged — only the final codegen *sink* differs.
