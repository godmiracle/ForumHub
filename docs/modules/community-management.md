# Community Management Module

## Scope

Community management controls which channels are visible and in what order they appear.

It includes:

- Channel subscription
- Channel visibility management
- Drag reordering of subscribed channels
- Source-aware channel lists
- Local persistence of selected channel order

## Key Files

- `ForumHub/Features/Community/CommunityView.swift`
- `ForumHub/Features/ForumManagement/ForumSubscriptionStore.swift`
- `ForumHub/Features/ForumFeed/ForumViewModel.swift`

## Notes

- Community is no longer the main source-switching surface; it now focuses on channel management.
- Source switching happens from the Home top-left menu, but visible channels still depend on this module.
- Channel order is persisted locally and should remain stable across launches.
- At least one subscribed channel must remain active.

## Current Risks

- Reordering and subscription state must stay consistent across multiple sources.
- UX can become confusing if source switching and channel management drift apart conceptually.
- Any future sync work must preserve per-source ordering semantics.

