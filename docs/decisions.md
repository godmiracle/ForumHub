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

## ADR-007 NGA Thread Pagination Keeps Source Fetches But Uses A Continuous Reading Flow

### Status

Accepted

### Date

2026-06

### Context

NGA still returns reply data in discrete source pages, but reading one page at a time made the detail screen feel interrupted and made the floating page control reflect only the last loaded page instead of the reader's actual scroll position.

### Decision

Keep NGA thread fetching source-shaped, but let the detail screen accumulate continuation pages into one continuous reply list. The floating page control should derive its current page from scroll position, while still using source-page fetches and duplicate protection underneath. Intermediate page loads should happen through an invisible footer trigger instead of a visible "load next page" card, reserving visible terminal state only for the true end of the thread.

### Consequences

- Cross-page reading becomes continuous instead of requiring page-by-page replacement
- The floating page indicator can track the reader's visible page instead of only the latest fetched page
- Mid-thread reading stays visually uninterrupted, while the UI still has an explicit end-of-thread state when no more replies remain
- Detail-state logic must keep page anchors and duplicate filtering stable while local presentation options remain layered on top

## ADR-008 Flutter Rebuild Uses A Parallel Incremental Migration

### Status

Accepted

### Date

2026-07

### Context

The SwiftUI app has reached a point where interaction-heavy screens, especially thread detail, are expensive to stabilize and verify. At the same time, the product direction benefits from a cross-platform shell. A direct big-bang rewrite would force source adapters, reading flows, persistence, and auth behavior to be re-debugged all at once.

### Decision

Rebuild `ForumHub` in Flutter on a separate branch and in a separate app directory, while preserving the current SwiftUI project during migration. Migrate read-only flows first, then local product features, then authenticated and write flows. Keep the existing product boundaries: source adapters remain source-local, shared UI depends on normalized domain models, and thread-detail presentation options remain presentation state.

### Consequences

- We can ship or validate Flutter in phases instead of waiting for full parity
- SwiftUI remains the fallback reference while Flutter behavior is still being stabilized
- Migration work now requires explicit documentation, milestones, and parity audits
- Some logic may temporarily exist in both codebases until cutover is complete

## ADR-009 Flutter NGA Transport Reads The Flutter Host Cookie Store

### Status

Accepted

### Date

2026-07

### Context

The Flutter rebuild needs real NGA read-only requests before the full Flutter login flow exists. Reusing the SwiftUI app's existing persisted cookies across a separate Flutter host target would require target-level sharing decisions that are not stable yet, especially while the rebuild is still running as a parallel app shell.

### Decision

Connect the Flutter NGA transport to the Flutter host app's native cookie storage through a thin iOS method-channel bridge. The bridge reads cookies from the host's `WKWebsiteDataStore.default()` and mirrors them into `HTTPCookieStorage.shared` for outgoing Dart HTTP requests. Do not assume direct reuse of the old SwiftUI app's persisted login state at this stage.

### Consequences

- Flutter can load public NGA data immediately and is ready to reuse cookies once a Flutter Web login flow is added
- Auth transport stays close to the proven `WebView -> native cookie store -> HTTP requests` boundary
- Existing SwiftUI app cookies are not automatically visible to the Flutter app target during the migration phase
- The next auth milestone is a Flutter-native Web login surface, not cross-target credential sharing
- Startup-sensitive host code must avoid querying WebKit cookie state during early app launch on device; shared HTTP cookie storage is the safe default until login sync is explicitly triggered after Web auth
- Session code should live in a dedicated Flutter session layer instead of being embedded directly into generic account or app-bootstrap files
- Read-only feature controllers should observe a lightweight session epoch instead of importing account-specific UI concerns, keeping session invalidation explicit while preserving module boundaries

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
