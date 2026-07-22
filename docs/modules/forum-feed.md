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
- `ForumHub/Features/ForumFeed/AuthoritativeChildForumDirectoryStore.swift`
- `ForumHub/Domain/AuthoritativeChildForumDirectory.swift`
- `ForumHub/Domain/ForumTime.swift`
- `ForumHub/Features/ForumManagement/ForumSubscriptionStore.swift`

## Notes

- Home is the main place where users switch sources and browse content.
- Feed content is source-agnostic at the view layer and depends on shared `ForumThread` models.
- Feed rows consume structured `Date` values and present `回复 MM-dd HH:mm` or `发布 MM-dd HH:mm`; source strings are compatibility input, not display authority.
- Sorting remains an immediate presentation concern. Child-channel and pinned visibility changes are edited as a draft in one filter sheet and committed once on Apply.
- Sort and pinned preferences are scoped by source. NGA child-channel selections use stable keys, are scoped by source plus parent channel, and are intersected with the latest confirmed authoritative directory on restore. Legacy numeric selections migrate only after a directory can map them uniquely.
- Home channel navigation, highlighting, horizontal paging and subscription ordering use canonical source-scoped keys. NGA ordinary numeric channels normalize to `nga:fid:<id>`, while authoritative `stid` targets remain `nga:stid:<id>`.
- A subscribed authoritative child is a normal independent Home channel and loads only its own Feed. This is separate from the 网事杂谈 filter, which continues to aggregate the main forum and selected children.
- The complete header is source → search/refresh/compose → channels → sort/filter → conditional session prompt. Scrolling collapses the first two rows while channels and sort/filter remain discoverable.
- Compose is capability-driven. NGA uses the verified same-session Web compose destination; V2EX and LINUX DO keep the action hidden until a supported destination is verified.
- Feed loads use cancellable tasks plus request generations. A response may update feed state only when its generation is still current, preventing stale Home/Hot responses from surfacing errors after a tab or source change.
- Tab reselection is observed without replacing `TabView`'s native delegate and routed as a target-specific scroll request. Home and Hot scroll immediately, refresh in the background, then confirm their own scroll position after refreshed data is installed; other tabs only receive a scroll request.
- The 网事杂谈 filter consumes only the parent forum's confirmed authoritative child directory. The main forum is always included; users can select multiple true children or reset to main-only. Unrelated global NGA channels never appear in this section or count toward its status.
- Confirmed child directories are persisted by source and parent. A first sync establishes a quiet baseline; later complete snapshots track added, renamed, and cancelled stable keys. Failed or structurally invalid refreshes retain the last confirmed snapshot and do not infer cancellations.
- When a complete foreground refresh cancels an active child selection, the feed view model invalidates the current request generation and performs exactly one reload using the remaining authoritative stable keys. Startup, source switching, and channel switching keep their existing explicit reload so the same transition is not loaded twice.
- New children stay unselected and carry a dismissible “新” state. Cancelled selected children are removed from the effective selection and surfaced once. When no confirmed snapshot exists, the filter reports that the directory is temporarily unavailable.
- NGA child-channel aggregation is handled in the feed view model and must not leak parser details into views. The main forum must succeed; individual child failures preserve successful content and expose a retryable partial-failure state. Generation cancellation, remote page numbers, current sorting, and `source + tid` deduplication remain in force.
- The child list exposes local title/stable-key search when at least 12 true children are available. Static accessibility labels, dynamic type-compatible text, and minimum hit targets are implemented.
- Durable acceptance evidence (2026-07-22, Xcode Beta, physical device “哥谭之王”, UDID `00008150-001A4D5E1428401C`): the user manually completed and answered “一切正常” for main-always-included/default-main-only, multi-select Apply, reopen restoration, local search, larger text, VoiceOver, draft cancellation, and one-Apply behavior. Foreground refresh, partial-child failure, added/cancelled-directory simulation, snapshot failure retention, and request-generation boundaries are automated Swift Testing coverage rather than manual claims; 39 tests in 4 focused suites passed on the same device with fresh DerivedData, including directory cancellation producing exactly one reload with remaining stable keys and rejecting the old in-flight generation.
- The first feed render should prefer a loading state until the initial request has completed once; an empty-state message is only valid after that first load resolves with no visible topics.

## Current Risks

- Refresh, tab switching, source switching and filter changes can create overlapping async tasks; all must continue through the existing generation/cancellation seam.
- Canonical channel selection must remain the generation boundary when equal numeric `fid` and `stid` targets coexist.
- Authoritative child metadata is a remote NGA contract; unknown or incomplete shapes must preserve the last confirmed directory instead of guessing.
- Aggregated child-channel content needs careful deduplication and stable pagination behavior.
- User perception is strongly affected by loading-state timing, even when data is technically correct.
