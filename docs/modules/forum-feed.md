# Forum Feed Module

## Scope

Forum Feed is the primary reading surface of ForumHub.

It includes:

- Source switching
- Home feed loading
- Hot feed loading
- Channel tab display
- Pinned thread display
- Sorting and pinned visibility toggles
- Feed pagination
- Feed-level loading and error states

## Key Files

- `ForumHub/ContentView.swift`
- `ForumHub/Features/ForumFeed/ForumViewModel.swift`
- `ForumHub/Features/ForumFeed/ForumFeedViews.swift`
- `ForumHub/Features/ForumManagement/ForumSubscriptionStore.swift`

## Notes

- Home is the main place where users switch sources and browse content.
- Feed content is source-agnostic at the view layer and depends on shared `ForumThread` models.
- Sorting is currently a presentation concern applied after repository data is loaded.
- Cancellation handling matters because feed refreshes, tab reselection, and source changes can overlap.
- NGA child-channel aggregation is handled in the feed view model and must not leak parser details into views.

## Current Risks

- Refresh and tab switching can create overlapping async tasks.
- Aggregated child-channel content needs careful deduplication and stable pagination behavior.
- User perception is strongly affected by loading-state timing, even when data is technically correct.

