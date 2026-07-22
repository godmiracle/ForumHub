# Community Management Module

## Scope

Community management controls which channels are visible and in what order they appear.

It includes:

- A source-scoped catalog that combines ordinary channels with confirmed authoritative child forums
- Local search across channel titles and stable browsing identifiers
- Channel subscription
- Channel visibility management
- An explicit edit mode for drag reordering subscribed channels
- Source-aware channel lists
- Local persistence of selected channel order

## Key Files

- `ForumHub/Features/Community/CommunityView.swift`
- `ForumHub/Features/Community/ForumChannelCatalog.swift`
- `ForumHub/Features/ForumManagement/ForumSubscriptionStore.swift`
- `ForumHub/Features/ForumFeed/ForumViewModel.swift`

## Notes

- Community is no longer the main source-switching surface; it now focuses on channel management.
- Source switching happens from the Home top-left menu, but visible channels still depend on this module.
- NGA ordinary channels and confirmed 网事杂谈 direct children are combined by canonical browsing identity. A matching ordinary `fid` and authoritative `fid` render once, while `fid:N` and `stid:N` remain distinct.
- An authoritative child such as `[股市]技术分析` can be subscribed as an independent Home channel. Opening it loads only that child; the subscription does not change the 网事杂谈 aggregation filter.
- Channel subscriptions use versioned canonical keys such as `nga:fid:-7` and `nga:stid:47206901`. Legacy numeric NGA keys migrate without overwriting the old rollback snapshot.
- The page separates “已添加到首页” from discoverable channels. Search results retain parent context, and drag handles only appear in explicit reorder mode.
- Channel order is persisted locally and should remain stable across launches and directory renames.
- At least one subscribed channel must remain active.

## Current Risks

- Reordering and subscription state must stay consistent across multiple sources and canonical key migrations.
- A complete authoritative snapshot may remove a subscribed child; failed or incomplete refreshes must retain the cached directory and subscription.
- Independent Home child subscriptions and parent aggregation filters must never write into each other.
- Any future sync work must preserve per-source ordering semantics.
