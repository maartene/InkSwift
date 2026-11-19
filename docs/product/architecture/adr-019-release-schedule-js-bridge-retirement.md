# ADR-019: Release Schedule for Retiring the JS-Bridge — 2.1 Introduces, 3.0 Switches, 4.0 Removes

**Status**: Accepted
**Date**: 2026-11-19
**Deciders**: Maarten Engels (project owner)
**Supersedes**: the removal version in [ADR-015](./adr-015-inkstory-deprecation-mechanics.md) (v3.0.0), and the decision to deprecate `InkStory` in the 2.x line

---

## Context

The native-runtime-migration feature (ADR-015) planned to deprecate the JS-bridge
`InkStory` straight away and remove it in **v3.0.0**. It shipped that way: 2.1.0 carries
`@available(*, deprecated, message: "… will be removed in v3.0.0 …")` on `InkStory`.

2.1.0 is also the **first release of `SwiftInkRuntime` at all**: the previous release,
2.0.0 (January 2024), shipped only the JS-bridge. Deprecating the only runtime existing
users have ever had, in the same release that first offers its replacement, and
removing it at the next major, leaves them no release in which both are first-class.

## Decision

Three steps, one per version line:

| Version | `SwiftInkRuntime` (native) | `InkStory` (JS-bridge) |
|---|---|---|
| **2.1.x** (now) | First formal release; recommended for new projects | Supported, **not deprecated** |
| **3.0.0** | **The default**: the `InkSwift` product/module becomes the native runtime, so `import InkSwift` gives `Story` / `InkCompiler` | **Deprecated**, and moved to its own product (name to be decided when 3.0.0 is planned, e.g. `InkSwiftJSBridge`) |
| **4.0.0** | — | **Removed** |

Consequences for 2.1.x:

- **2.1.1 removes the `@available(*, deprecated)` attribute** from `InkStory`. Users who
  saw the warning in 2.1.0 stop seeing it; nothing else changes.
- The docs say: native is recommended; the JS-bridge will be deprecated in v3.0.0 and
  removed in v4.0.0.

## Consequences

- ADR-015's *mechanics* still describe how the deprecation will be done in 3.0.0
  (type-level `@available(*, deprecated, message:)`, a warning, never an error, no
  `renamed:`); only its *timing* and *removal version* are replaced here. The 3.0.0
  message must name v4.0.0 and the JS-bridge's new product.
- 3.0.0 is a breaking major for two reasons: the `InkSwift` product changes runtime, and
  the JS-bridge moves to a new product. Both need a migration note.
- The parity statement's living backlog is the to-do list toward **v4.0.0**: the gaps
  that must close before the JS-bridge can be removed.
- The design records written for the earlier plan (`docs/product/jobs.yaml`, the
  native-runtime-migration journey, the native-runtime-migration section of the
  architecture brief) are left as the history of that decision.
