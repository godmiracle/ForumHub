# Flutter Rebuild Plan

## Status

In progress on a separate branch.

Current milestone status:

- Flutter app shell is up and `flutter analyze` is clean
- home/source/channel state already runs through a repository seam
- thread-detail mock pagination state is wired
- NGA parser and live-repository seam are being ported before cookie-backed transport is connected
- Flutter iOS host project now exists, and NGA live transport reads through a native cookie bridge plus Dart `HttpClient`
- The first real-device crash on iPhone was traced to startup-time WebKit cookie access; the bridge now reads shared HTTP cookies only, and Web login sync will be added later as a separate step
- A first-pass NGA session layer now exists in Flutter: user tab account card, embedded Web login screen, and an explicit post-login cookie sync action
- Session changes now propagate through a lightweight epoch provider so read-only feature controllers can rebuild after NGA login/logout without directly depending on account-screen widgets
- Navigation and shell polish is now being handled as dedicated Flutter components, including iOS-native detail transitions and a custom glass bottom tab bar instead of default Material navigation chrome

## Goal

Rebuild `ForumHub` as a Flutter application without blocking the existing SwiftUI codebase, while preserving the current product model:

- `ForumHub` remains the product shell
- `NGA`, `V2EX`, and `LINUX DO` remain source adapters
- shared UI depends on normalized domain models rather than source-specific payloads

This plan is intentionally incremental. The first objective is not feature parity on day one. The first objective is a stable Flutter reading shell that can replace the most valuable read-only flows before account and write flows are migrated.

## Why Rebuild

Current pressure points in the SwiftUI codebase:

- thread-detail scroll and pagination behavior has been expensive to stabilize
- complex reading-state logic is tightly coupled to view lifecycle behavior
- UI verification is currently less reliable than we want for interaction-heavy flows
- the long-term product direction benefits from a cross-platform shell

This rebuild is justified if we want:

- a unified `iOS + Android` client
- more explicit control over scroll containers and gesture-driven detail flows
- clearer separation between source adapters, state machines, and rendering

## Non-Goals

- do not rewrite source business rules during the initial migration
- do not chase visual parity before reading behavior is correct
- do not migrate every feature before shipping a usable read-only build
- do not couple Flutter widgets directly to raw API response models

## Product Boundaries To Preserve

The Flutter project must preserve these boundaries from the existing app:

- source-specific parsing stays inside adapter modules
- thread-detail ordering, only-author mode, and reverse order remain presentation state
- favorites, history, blocked users, and subscriptions remain product-level features, even if source capability differs
- capability gaps stay explicit through source capability flags

## Migration Strategy

### Recommended Approach

Use a parallel rebuild on a separate branch and a separate Flutter app directory.

Do not delete or mutate the existing SwiftUI app as part of the first migration phase.

### Why Not A Big-Bang Rewrite

A big-bang rewrite would force us to re-debug:

- multi-source feed state
- thread-detail pagination
- cookie-backed login
- image and GIF handling
- local persistence

all at once. That would turn one hard problem into six hard problems with no stable fallback.

### Execution Model

1. freeze the current product scope and write down behavior
2. stand up a Flutter shell with shared domain boundaries
3. migrate read-only flows first
4. migrate local persistence features
5. migrate authenticated flows
6. retire SwiftUI only after Flutter covers the needed production path

## Proposed Repository Layout

```text
ForumHub/
├── ForumHub/                     # Existing SwiftUI app
├── ForumHubTests/
├── ForumHubUITests/
├── flutter_forumhub/            # New Flutter app
│   ├── lib/
│   │   ├── app/
│   │   ├── core/
│   │   ├── domain/
│   │   ├── data/
│   │   ├── features/
│   │   └── shared/
│   ├── test/
│   ├── integration_test/
│   └── pubspec.yaml
├── docs/
│   ├── flutter-rebuild-plan.md
│   └── ...
└── ...
```

## Flutter Architecture

## Layering

### `app`

Owns:

- app bootstrap
- routing
- themes
- dependency registration
- source-wide navigation shell

### `core`

Owns cross-cutting infrastructure:

- HTTP clients
- cookie synchronization helpers
- local storage adapters
- secure storage
- image caching pipeline
- logging and diagnostics
- error mapping

### `domain`

Owns source-agnostic models and use cases:

- `ForumSource`
- `ForumChannel`
- `ForumThread`
- `Reply`
- `ForumSummary`
- `FavoriteThread`
- `BlockedUser`
- detail pagination state contracts

This layer should stay free of Flutter widgets.

### `data`

Owns per-source implementation:

- `nga/`
- `v2ex/`
- `linux_do/`
- DTOs
- parsers
- repositories
- capability mapping

### `features`

Owns product state and screens:

- `feed`
- `thread_detail`
- `community`
- `search`
- `favorites`
- `history`
- `account`

### `shared`

Owns reusable presentation pieces:

- thread cards
- avatars
- capability badges
- floating page controls
- media viewer
- rich-content block renderer

## State Management

Recommended default:

- `flutter_riverpod`

Why:

- good async-state ergonomics
- clean dependency injection
- easier separation between repositories and UI state than ad hoc widget state
- suitable for per-source capability and pagination state

Avoid in phase one:

- over-abstracted BLoC setup
- heavy code generation before the domain is stable

## Rendering Strategy

### Feed

Use:

- `CustomScrollView`
- `SliverAppBar`
- `SliverList`

Do not start with deeply nested generic list abstractions.

### Thread Detail

The thread-detail screen should be built around an explicit reading state machine rather than scroll side effects embedded inside widgets.

Suggested state model:

- canonical thread metadata
- currently materialized reply slice or loaded reply pages
- visible page
- total page count
- only-author filter
- reverse order
- loading-next-page state
- manual page-jump state

### Rich Content

Parse remote text into normalized content blocks before rendering:

- text
- quote
- image
- GIF
- code block
- link

Do not pass raw source text directly into widget trees.

## Technology Choices

Recommended initial package set:

- state: `flutter_riverpod`
- navigation: `go_router`
- HTTP: `dio`
- cookies: `cookie_jar` plus a custom sync bridge for WebView cookies
- Web login: `webview_flutter`
- persistence: `isar` or `drift`
- key-value settings: `shared_preferences`
- secure storage: `flutter_secure_storage`
- images: `cached_network_image` plus a unified media abstraction

Package choice is less important than architecture consistency. We can swap packages later; we cannot cheaply unwind a bad domain boundary later.

## Source Migration Notes

## NGA

Priority:

- feed
- thread detail
- manual pagination
- only-author mode
- reverse order
- favorites
- reply flow

High-risk areas:

- unstable response formats
- duplicate main-post protection
- direct pagination semantics
- cookie-backed auth
- reply with image upload

## V2EX

Priority:

- feed
- thread detail
- local favorites
- token-backed account state

Lower-risk than NGA, but still needs normalized thread and reply mapping.

## LINUX DO

Priority:

- feed
- thread detail
- web login plus cookie reuse

The Discourse-shaped model should be kept adapter-local even if it is structurally cleaner than NGA.

## Migration Phases

## Phase 0 — Freeze And Spec

Deliverables:

- this plan
- source capability inventory
- page behavior inventory for feed and thread detail
- explicit list of what will not be migrated in MVP

Exit criteria:

- product scope is documented well enough that Flutter work does not depend on memory of the SwiftUI implementation

## Phase 1 — Flutter Skeleton

Deliverables:

- `flutter_forumhub/` app created
- source enum, channel model, thread model, reply model
- app shell with tabs matching current product structure
- theme tokens and basic navigation shell

Exit criteria:

- app boots on device
- source switching shell exists
- no source-specific logic lives in widgets

## Phase 2 — Read-Only MVP

Deliverables:

- home feed for all supported sources
- source switching
- channel switching
- thread detail read-only screen
- image preview
- manual pagination for NGA detail

Exit criteria:

- a user can browse source feeds and open threads end-to-end in Flutter
- NGA detail pagination works without duplicate main-post rows
- no login required for the MVP path

## Phase 3 — Local Product Features

Deliverables:

- local favorites
- browsing history
- blocked users
- channel subscriptions and drag ordering

Exit criteria:

- local reading-state features match current product intent

## Phase 4 — Authenticated Flows

Deliverables:

- NGA web login plus cookie reuse
- LINUX DO web login plus cookie reuse
- V2EX token account path
- source capability gating in UI

Exit criteria:

- authenticated source requests work from Flutter
- account state is source-aware and persistent

## Phase 5 — Write Flows

Deliverables:

- NGA favorites API integration
- NGA reply
- NGA reply image upload

Exit criteria:

- Flutter can fully cover the current NGA write path

## Phase 6 — Cutover Review

Deliverables:

- feature parity audit
- known-gap list
- cutover plan

Exit criteria:

- we can decide whether SwiftUI becomes legacy, fallback, or archive

## MVP Scope

The first real Flutter milestone should be intentionally narrow.

### Included

- source switch
- subscribed channel selection
- feed rendering
- thread detail rendering
- NGA manual pagination
- image preview
- local history
- local favorites

### Excluded

- cloud sync
- reply composer
- image upload
- source-native favorites
- advanced account management

This keeps the first Flutter milestone focused on reading quality rather than authentication complexity.

## Testing Strategy

## Unit Tests

Required for:

- domain models
- parser normalization
- pagination state transitions
- duplicate-reply protection
- capability mapping

## Widget Tests

Required for:

- feed cards
- thread-detail state rendering
- pagination controls
- only-author and reverse-order combinations

## Integration Tests

Required for:

- source switching
- feed to detail navigation
- thread-detail manual pagination

Do not depend on flaky gesture-only tests for core correctness. The pagination state machine must be testable without a live scroll gesture.

## Documentation To Keep Updated During Rebuild

During execution, update:

- `docs/flutter-rebuild-plan.md`
- `docs/todo.md`
- `docs/roadmap.md`
- `docs/decisions.md`
- module notes when Flutter behavior clarifies or changes product rules

## First Implementation Step

After this document is accepted, the next concrete step should be:

1. create `flutter_forumhub/`
2. initialize a Flutter app shell
3. add the base folder structure under `lib/`
4. define the first shared domain models:
   - `ForumSource`
   - `ForumChannel`
   - `ForumThread`
   - `Reply`
5. wire a placeholder tab shell for `Home`, `Community`, `History`, and `User`

That gives us a stable starting point before any source adapter work begins.
