# Thread Detail Module

## Scope

Thread detail is one of the highest-complexity feature areas in ForumHub.

It includes:

- Main post rendering
- Reply rendering
- Pagination
- Only-author filtering
- Reverse ordering
- Floor labels
- Favorites
- Reply composer
- Reply targeting for thread-level and per-floor reply flows
- Rich image handling

## Key Files

- `ForumHub/Features/ThreadDetail/ThreadDetailView.swift`
- `ForumHub/Features/ThreadDetail/ThreadDetailReplyComposer.swift`
- `ForumHub/Features/ThreadDetail/ThreadDetailRichContent.swift`
- `ForumHub/Features/ThreadDetail/ThreadSnapshotRenderer.swift`
- `ForumHub/Domain/ForumModels.swift`

## Notes

- Presentation state is layered on top of provider data rather than rewriting repository ordering.
- Rich reading, long-image snapshots, image enumeration, reply previews, accessibility text and pagination signatures consume `ForumPostDocument.blocks` or explicit projectors; they never reparse flattened text.
- `ThreadDetailPaginationState` owns remote data progress (`currentPage`, `hasMoreReplies`, page start indices); `ThreadDetailScrollState` owns visible-page tracking, page-picker selection, deferred scroll targets, and the automatic-scroll trigger lock. ViewModel writes pagination progress, while the View writes scroll-derived presentation state.
- 信息流传入的主题只可作为详情页的元数据占位；0 楼正文和回帖必须等待 `fetchThread` 成功后才可展示，避免摘要被误认为完整正文。
- 列表摘要与完整详情即使拥有相同 `source + id` 也不是内容相等值，确保 Observation 能在详情回写时驱动当前页面更新。
- Thread detail should use a scroll container that exposes continuous geometry signals for paging and scroll affordances; `List` cell lifecycle is not reliable enough for NGA's direct-pagination auto-advance.
- NGA thread detail should accumulate fetched continuation pages into one continuous reading flow instead of replacing the visible reply slice page by page.
- Intermediate NGA pages should preload when one of the last few visible reply rows appears, so readers can scroll continuously without seeing a dedicated "load next page" card between reply pages.
- The lower-right floating page control should reflect the page currently near the top of the viewport, not just the highest page fetched so far.
- The lower-right reading controls should stay visually grouped: when direct pagination is available, the scroll-to-top affordance joins the page capsule as its leading action; sources without direct pagination keep a standalone scroll-to-top button.
- Automatic preloading should append data without advancing the visible-page selection; explicit previous/next controls and picker jumps are responsible for scrolling to a page anchor.
- Visible-page tracking should prefer lightweight per-page anchor geometry instead of per-reply listeners, so long threads keep smoother scrolling while the floating control stays in sync.
- NGA auto-pagination should use the simplest possible rule: when a near-end reply row appears, load the next source page once.
- Explicit page jumping with previous/next controls plus a picker sheet should scroll to the corresponding loaded page anchor, loading intermediate pages first when necessary.
- Automatic page advance for NGA should not depend on a tiny invisible footer geometry probe; the near-end reply appearance trigger is more stable for the current non-lazy `ScrollView` stack.
- The page-anchor geometry path should stay lightweight and page-scoped. With roughly 20 replies per page, per-reply geometry listeners are unnecessary and can make long-thread scrolling feel heavier.
- The page picker should feel visually related to the floating controls: compact glass surfaces, quick first/last-page shortcuts, and a lightweight confirmation row instead of a dense divider-heavy list.
- Floor labels in NGA thread detail should prefer source-provided floor numbers and only fall back to page-aware local inference when the parser cannot recover them.
- Reply composition should stay as one shared sheet. The main action bar opens a thread-level reply, while per-floor menus can retarget the same composer to a specific floor when the active source exposes stable reply identifiers.
- The bottom action bar should separate hierarchy without adding text labels: reply remains an independent prominent circular action, while author filtering, sharing, and more actions sit on one compact secondary glass capsule; inactive secondary actions do not add nested circular surfaces.
- When the source returns quote metadata, the detail body should render it as a dedicated inline quote card instead of flattening it into plain text, so users can immediately distinguish "回复主题" from "回复某层".
- Reply pagination must protect against duplicate content from source-specific continuation pages.
- Refresh, explicit page jumps, and automatic continuation loading share one cancellable content-load task. A monotonically increasing generation prevents a stale request from committing state after a newer load has begun.
- Reply filtering, ordering, and page-anchor entries are cached as derived presentation state and refreshed only when their source replies, paging metadata, filter settings, or blocked-user list changes.
- Thread detail converts repository and transport errors into `ForumError` before presentation, keeping raw transport and parser descriptions out of user-visible error cards.
- Floating controls and page selection surfaces use the shared `ForumGlass` DesignSystem components, keeping iOS 26 glass rendering and older material fallbacks visually aligned.
- NGA continuation pages are merged through `ThreadDetailPaginationMerger`; it removes repeated main-post payloads and deduplicates replies by both source identifier and reply signature before the view updates pagination state.
- Image handling mixes static images, GIF playback, preview, zoom, and save-to-photos behavior.
