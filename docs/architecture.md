# Architecture

## Overview

ForumHub is a SwiftUI iOS app built around a shared domain layer and source-specific repository adapters.

The core flow is:

```text
Remote Source
    -> Source Adapter / Parser
    -> Shared Domain Models
    -> Feature ViewModels / Stores
    -> SwiftUI Views
```

## Top-Level Code Layout

- `ForumHub/Data`
  Adapters, parsers, and request logic for NGA, V2EX, and LINUX DO.
- `ForumHub/Domain`
  Shared models such as `ForumThread`, `Reply`, `ForumSummary`, and content parsing utilities.
- `ForumHub/Features`
  User-facing features like feed, thread detail, search, account, history, and channel management.
- `ForumHub/Session`
  Login flows, cookies, Keychain persistence, and auth session helpers.
- `ForumHub/DesignSystem`
  Shared theme primitives and reusable styling.
- `ForumHub/Sync`
  iCloud KVS records, merge policy, and other cross-device sync boundaries.

## Source Adapter Model

All sources conform to the `ThreadRepository` seam.

Current adapters:

- `NGALiveThreadRepository`
- `V2EXThreadRepository`
- `DiscourseThreadRepository`
- `MockThreadRepository`

Responsibilities of adapters:

- Build source-specific requests
- Parse unstable response formats
- Normalize remote fields into shared domain models
- Surface capability flags such as favorites or replies

Views should not read raw source payloads.

## UI Composition

Key feature areas:

- Home feed and source switching
- Channel management and subscription ordering
- Thread detail, replies, pagination, and rich content rendering
- Search, favorites, history, blocked users, and account surfaces

The Home screen is the primary navigation surface. Community is now focused on channel management rather than source switching.

See also:

- [docs/modules/forum-feed.md](/Users/v/XBP/ForumHub/docs/modules/forum-feed.md)
- [docs/modules/community-management.md](/Users/v/XBP/ForumHub/docs/modules/community-management.md)
- [docs/modules/thread-detail.md](/Users/v/XBP/ForumHub/docs/modules/thread-detail.md)
- [docs/modules/feature-matrix.md](/Users/v/XBP/ForumHub/docs/modules/feature-matrix.md)
- [docs/modules/search-and-discovery.md](/Users/v/XBP/ForumHub/docs/modules/search-and-discovery.md)
- [docs/modules/image-handling.md](/Users/v/XBP/ForumHub/docs/modules/image-handling.md)
- [docs/modules/testing-and-fixtures.md](/Users/v/XBP/ForumHub/docs/modules/testing-and-fixtures.md)
- [docs/modules/persistence-and-sync.md](/Users/v/XBP/ForumHub/docs/modules/persistence-and-sync.md)

## Persistence

ForumHub currently uses local persistence for:

- Selected source
- Channel subscriptions and ordering
- Source-native favorite UI caches
- iCloud-synchronized blocked users
- Browsing history

Credential-like state uses synchronizable Keychain items and shared cookie stores where appropriate.

See also:

- [docs/modules/persistence-and-sync.md](/Users/v/XBP/ForumHub/docs/modules/persistence-and-sync.md)

## Image Handling

Thread detail rich content supports:

- Static image rendering
- GIF playback
- Image preview, zoom, and save
- Shared download/cache pipeline for remote images

See also:

- [docs/modules/image-handling.md](/Users/v/XBP/ForumHub/docs/modules/image-handling.md)

## Current Technical Risks

- NGA thread detail responses can vary across API and web fallbacks
- Pagination behavior needs continued validation to prevent duplicate main-post rows
- Source feature parity is intentionally uneven and must be expressed through capability flags

## Verification

Build verification is the minimum expected feedback loop.

See also:

- [docs/modules/testing-and-fixtures.md](/Users/v/XBP/ForumHub/docs/modules/testing-and-fixtures.md)
