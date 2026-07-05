# AGENTS

This file gives AI coding agents and human collaborators a shared entry point into the ForumHub repository.

## Start Here

Read these files first:

1. [README.md](/Users/v/XBP/ForumHub/README.md)
2. [CONTEXT.md](/Users/v/XBP/ForumHub/CONTEXT.md)
3. [docs/architecture.md](/Users/v/XBP/ForumHub/docs/architecture.md)
4. Relevant module docs under [docs/modules](/Users/v/XBP/ForumHub/docs/modules)

## Product Boundaries

- `ForumHub` is the product shell.
- `NGA`, `V2EX`, and `LINUX DO` are source adapters.
- Shared UI should depend on domain models, not source-specific response fields.
- New source behavior should stay inside `Data/<Source>` unless it is clearly generic.

## Code Navigation

- `ForumHub/Data`: repositories, parsers, DTO mapping
- `ForumHub/Domain`: models such as `ForumThread`, `Reply`, and content blocks
- `ForumHub/Features`: feed, thread detail, search, account, history, and management UI
- `ForumHub/Session`: login flows, cookie sync, and Keychain-backed auth state
- `ForumHub/DesignSystem`: colors, typography, and reusable UI styling
- `ForumHub/Sync`: sync-related experiments and future hooks

## Working Norms

- Preserve the multi-source architecture.
- Prefer fixing behavior at the shared seam when the same issue can affect multiple NGA detail paths.
- Do not move parsing logic into views.
- Keep user-visible wording in Chinese unless the surrounding file already uses English.
- Use `apply_patch` for manual file edits.

## Verification

Preferred verification rule:

- Prefer building for a connected iOS device.
- If no iOS device is currently available, skip the build instead of falling back to a simulator build.

Example device build command:

```sh
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -project ForumHub.xcodeproj \
  -scheme ForumHub \
  -configuration Debug \
  -destination 'platform=iOS,id=<CONNECTED_DEVICE_ID>' \
  build
```

## Documentation Rules

- Update [CONTEXT.md](/Users/v/XBP/ForumHub/CONTEXT.md) when domain language or invariants change.
- Update [docs/decisions.md](/Users/v/XBP/ForumHub/docs/decisions.md) when a non-obvious product or architecture choice is made.
- Update [docs/changelog.md](/Users/v/XBP/ForumHub/docs/changelog.md) for user-visible behavior changes.
- Add focused module notes under [docs/modules](/Users/v/XBP/ForumHub/docs/modules) instead of overloading one giant doc.

Useful next module docs:

- [docs/modules/forum-feed.md](/Users/v/XBP/ForumHub/docs/modules/forum-feed.md)
- [docs/modules/community-management.md](/Users/v/XBP/ForumHub/docs/modules/community-management.md)
- [docs/modules/thread-detail.md](/Users/v/XBP/ForumHub/docs/modules/thread-detail.md)
- [docs/modules/feature-matrix.md](/Users/v/XBP/ForumHub/docs/modules/feature-matrix.md)
- [docs/modules/search-and-discovery.md](/Users/v/XBP/ForumHub/docs/modules/search-and-discovery.md)
- [docs/modules/image-handling.md](/Users/v/XBP/ForumHub/docs/modules/image-handling.md)
- [docs/modules/testing-and-fixtures.md](/Users/v/XBP/ForumHub/docs/modules/testing-and-fixtures.md)
- [docs/modules/persistence-and-sync.md](/Users/v/XBP/ForumHub/docs/modules/persistence-and-sync.md)
