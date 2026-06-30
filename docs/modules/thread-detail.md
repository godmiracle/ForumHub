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
- Rich image handling

## Key Files

- `ForumHub/Features/ThreadDetail/ThreadDetailView.swift`
- `ForumHub/Features/ThreadDetail/ThreadSnapshotRenderer.swift`
- `ForumHub/Domain/ForumModels.swift`

## Notes

- Presentation state is layered on top of provider data rather than rewriting repository ordering.
- Thread detail should use a scroll container that exposes continuous geometry signals for paging and scroll affordances; `List` cell lifecycle is not reliable enough for NGA's direct-pagination auto-advance.
- NGA thread detail should accumulate fetched continuation pages into one continuous reading flow instead of replacing the visible reply slice page by page.
- Intermediate NGA pages should preload through an invisible footer sentinel so readers can scroll continuously without seeing a dedicated "load next page" card between reply pages.
- The lower-right floating page control should reflect the page currently near the top of the viewport, not just the highest page fetched so far.
- Visible-page tracking should prefer lightweight per-page anchor geometry instead of per-reply listeners, so long threads keep smoother scrolling while the floating control stays in sync.
- NGA auto-pagination should use the simplest possible rule: when the bottom sentinel appears, load the next page once.
- Explicit page jumping with previous/next controls plus a picker sheet should scroll to the corresponding loaded page anchor, loading intermediate pages first when necessary.
- Automatic page advance for NGA should use SwiftUI geometry signals from the top anchor and pagination footer instead of relying on footer row appearance, because `List` row lifecycle events are not a stable signal for "the reader actually reached the bottom".
- The geometry-based auto-pagination path should use a non-lazy reply stack. With roughly 20 replies per page, `LazyVStack` can recycle the off-screen top anchor and bottom footer sentinel, which shows up as missing baseline/footer measurements and makes downward paging appear completely unresponsive.
- The page picker should feel visually related to the floating controls: compact glass surfaces, quick first/last-page shortcuts, and a lightweight confirmation row instead of a dense divider-heavy list.
- Floor labels in NGA thread detail should prefer source-provided floor numbers and only fall back to page-aware local inference when the parser cannot recover them.
- Reply pagination must protect against duplicate content from source-specific continuation pages.
- Image handling mixes static images, GIF playback, preview, zoom, and save-to-photos behavior.
