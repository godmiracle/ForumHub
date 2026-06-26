# Testing And Fixtures Module

## Scope

This module describes how ForumHub verifies behavior and where reusable test data should live.

It includes:

- Unit test targets
- UI test targets
- Test fixtures
- Build verification commands
- Recommended seams for regression tests

## Key Paths

- `ForumHubTests`
- `ForumHubTests/Fixtures`
- `ForumHubUITests`
- `ForumHub/Data`
- `ForumHub/Domain`

## Notes

- Parser and repository behavior should be validated as close to the adapter seam as possible.
- Shared domain behaviors such as deduplication, sorting, and pagination heuristics are good candidates for unit coverage.
- UI regressions that depend on navigation or async loading are better suited for UI tests or narrowly scoped view-model tests.
- Build success is currently an important baseline verification step even when no new tests are added.

## Recommended Test Priorities

- NGA thread detail parsing and continuation-page behavior
- Feed cancellation and refresh behavior
- Reply deduplication and pagination merging
- Favorites, blocked users, and browsing history persistence rules
- Source capability gating for unsupported actions

## Common Verification Command

```sh
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -project ForumHub.xcodeproj \
  -scheme ForumHub \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

## Current Risks

- Some user-visible behaviors still rely more on manual validation than automated tests.
- Source-specific fallbacks can drift if fixtures do not cover both normal and degraded responses.
- Pagination bugs are easy to reintroduce if there is no fixture-backed regression coverage.

