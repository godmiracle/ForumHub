# Forum Feed Module

## Scope

Forum Feed is the primary reading surface of ForumHub.

It includes:

- Source switching
- Home feed loading
- Hot feed loading
- Channel tab display
- Pinned thread display
- Immediate sorting and a unified filter sheet
- Conditional source-session and compose actions
- Feed pagination
- Feed-level loading and error states

## Key Files

- `ForumHub/ContentView.swift`
- `ForumHub/Features/ForumFeed/ForumViewModel.swift`
- `ForumHub/Features/ForumFeed/ForumFeedViews.swift`
- `ForumHub/Features/ForumFeed/FeedPreferences.swift`
- `ForumHub/Domain/ForumTime.swift`
- `ForumHub/Features/ForumManagement/ForumSubscriptionStore.swift`

## Notes

- Home is the main place where users switch sources and browse content.
- Feed content is source-agnostic at the view layer and depends on shared `ForumThread` models.
- Feed rows consume structured `Date` values and present `回复 MM-dd HH:mm` or `发布 MM-dd HH:mm`; source strings are compatibility input, not display authority.
- Sorting remains an immediate presentation concern. Child-channel and pinned visibility changes are edited as a draft in one filter sheet and committed once on Apply.
- Sort and pinned preferences are scoped by source. Child-channel selections are scoped by source plus parent channel and intersected with the current channel list on restore.
- The complete header is source → search/refresh/compose → channels → sort/filter → conditional session prompt. Scrolling collapses the first two rows while channels and sort/filter remain discoverable.
- Compose is capability-driven. NGA uses the verified same-session Web compose destination; V2EX and LINUX DO keep the action hidden until a supported destination is verified.
- Feed loads use cancellable tasks plus request generations. A response may update feed state only when its generation is still current, preventing stale Home/Hot responses from surfacing errors after a tab or source change.
- Tab reselection is observed without replacing `TabView`'s native delegate and routed as a target-specific scroll request. Home and Hot scroll immediately, refresh in the background, then confirm their own scroll position after refreshed data is installed; other tabs only receive a scroll request.
- NGA child-channel aggregation is handled in the feed view model and must not leak parser details into views.
- The first feed render should prefer a loading state until the initial request has completed once; an empty-state message is only valid after that first load resolves with no visible topics.

## Current Risks

- Refresh, tab switching, source switching and filter changes can create overlapping async tasks; all must continue through the existing generation/cancellation seam.
- Aggregated child-channel content needs careful deduplication and stable pagination behavior.
- User perception is strongly affected by loading-state timing, even when data is technically correct.
