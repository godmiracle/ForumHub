# Decisions

## ADR-001 Product Shell Stays `ForumHub`

### Status

Accepted

### Date

2026-06

### Context

The app started as an NGA-specific prototype but now supports multiple community sources with shared reading flows, account surfaces, and local user state.

### Decision

Product-level naming stays `ForumHub`, while `NGA`, `V2EX`, and `LINUX DO` remain only where they describe source adapters or remote behavior.

### Consequences

- Multi-source UX can evolve without fighting an NGA-branded shell
- Shared modules are easier to reason about at the product level
- Legacy file names and notes may still need gradual cleanup

## ADR-002 Source Switching Lives In Home

### Status

Accepted

### Date

2026-06

### Context

Users spend most of their time in the feed, and routing source switching through a separate community page added friction to a very common action.

### Decision

Move source switching to the Home top-left menu and let the Community tab focus on channel management, visibility, and ordering.

### Consequences

- Source switching becomes faster and closer to the active reading context
- Community has a clearer responsibility
- Feed and channel-management state must stay aligned across multiple entry points

## ADR-003 Thread Detail Ordering Is Presentation State

### Status

Accepted

### Date

2026-06

### Context

Users want reading preferences such as reverse order and only-author mode, but remote sources do not expose one consistent ordering contract.

### Decision

Handle reverse order and only-author filtering in the thread detail view layer instead of mutating repository output or source-specific parser behavior.

### Consequences

- Provider behavior stays stable and easier to debug
- Reading preferences can be combined locally
- Views must be careful to preserve true floor labels and pagination semantics

## ADR-004 iCloud Sync Is Disabled For Now

### Status

Accepted

### Date

2026-06

### Context

Favorites, blocked users, and other user state would benefit from sync, but the current project setup does not include the developer-account prerequisites to ship iCloud-backed behavior safely.

### Decision

Keep sync-related hooks in the repository, but disable iCloud-backed sync and avoid presenting it as an active product feature.

### Consequences

- Local-first behavior remains explicit and predictable
- Uninstall or device migration can still lose state
- Future sync work will need deliberate migration rules rather than implicit rollout

## ADR-005 LinuxDo Login Uses Web Login Plus Cookie Reuse

### Status

Accepted

### Date

2026-06

### Context

Direct authenticated API access for LINUX DO can be blocked by site protections or validation flows that are easier to complete in a browser context.

### Decision

Use a WebKit-driven login flow and shared cookie reuse instead of trying to implement a fully native authenticated API path first.

### Consequences

- Login is more resilient to browser-style validation flows
- The account experience depends on cookie correctness and session reuse
- This approach is pragmatic but less elegant than a clean native auth contract

## ADR-006 GIF Handling Uses A Shared Image Pipeline

### Status

Accepted

### Date

2026-06

### Context

Inline GIF rendering was slow and unstable when every view independently downloaded and initialized animated assets.

### Decision

Use a shared remote image pipeline with in-memory reuse, in-flight request reuse, and local file-backed GIF playback support.

### Consequences

- GIF rendering becomes more stable across scrolling and preview flows
- Image behavior is centralized, which reduces duplicated networking logic
- Bugs in the shared image path can affect multiple rich-content surfaces at once

## Template

Use this structure for future decisions:

```md
## ADR-XXX Title

### Status

Accepted | Proposed | Superseded

### Date

YYYY-MM

### Context

Why this decision was needed.

### Decision

What was chosen.

### Consequences

What this enables, costs, or constrains.
```
