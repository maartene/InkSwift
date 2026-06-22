# Competitive Research — `state-blueprint-compatibility`

**Wave:** DIVERGE · Phase 2 · **Gate G2: PASS** (5 real named systems, ≥1 non-obvious adjacent)
**Job space:** restore persisted state against a changed schema/blueprint.

| # | System (real) | How it serves the job | Where it fails THIS job | Key assumption |
|---|---|---|---|---|
| 1 | **inkle's own ink runtime** (`StoryState.cs`) — `kInkSaveStateVersion=10`, `kMinCompatibleLoadVersion=8`; throws on incompatible load | Versions the save and refuses too-old saves loudly | **CRITICAL nuance: versions the FORMAT, not the CONTENT.** A renamed knot still breaks restore — the exact failure InkSwift inherits. The version check does *not* detect blueprint drift. | The blueprint is immutable across a save's lifetime. |
| 2 | **Protocol Buffers** — wire format carries **field numbers, not names**; `reserved` numbers/names; never reuse a tag | Decouples identity from name → rename a field freely, old data still reads | Requires authoring stable numeric tags up front; InkSwift's paths are **positional/name-derived**, the inverse of protobuf's stable-tag design | Schema authors assign and preserve stable tags. |
| 3 | **Flyway** (DB migrations) — ordered `V1→V2` scripts, **checksum** per migration, `flyway_schema_history` tracks applied versions | Deterministic ordered migration chain + checksum drift detection | Heavyweight: an authored migration per version; assumes a controlled, low-frequency change cadence — a lot of ceremony for a single-player save | Every breaking change gets a hand-authored, ordered migration. |
| 4 | **Game-save versioning** (Unity / GameDev.net pattern) — `save-version` field + chain of conversion functions migrating up to current; **tolerant reader** for missing fields | Mainstream, proven for shipped games; combines version stamp + migration chain | Still needs per-version migrators authored; tolerant-reader handles *added* fields, not *moved* paths | Save layout changes are anticipated and migratable. |
| 5 | **Tolerant Reader / Robustness Principle** (Postel) — *non-obvious adjacent* | Read what you can, ignore what you can't, report rather than crash → best-effort partial restore with explicit result | Pure tolerance without identity risks *masking* corruption (exactly InkSwift's silent `?? root` today, but worse if unreported) | Partial state is better than no state, **if** the gaps are reported. |

## Synthesis

- **ink itself proves the trap** — format ≠ content versioning. Its version check would not catch a renamed knot.
- **Protobuf proves the cure direction** — stable identity decoupled from layout.
- **Flyway / game-saves prove the recover direction** — migration chains for intentional breaks.
- **Tolerant Reader (non-obvious) proves the recover-and-report direction** — best-effort + explicit result; the discipline InkSwift's silent `?? root` currently violates.

Every row names a real mechanism/metric — no generic "most users probably" claims.

## Sources

- [ink `StoryState.cs`](https://github.com/inkle/ink/blob/master/ink-engine-runtime/StoryState.cs)
- [Protobuf — reserved fields & schema evolution](https://protobuf.dev/overview/)
- [Flyway — versioned migrations](https://documentation.red-gate.com/fd/versioned-migrations-273973333.html)
- [Game save versioning (GameDev.net)](https://www.gamedev.net/forums/topic/702903-how-to-transfer-save-data-through-versions/5408625/)
