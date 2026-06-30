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
- NGA thread detail now supports explicit page jumping with previous/next controls plus a picker sheet, exposed from the lower-right floating control area instead of the reply list body, while still allowing downward scrolling at page end to advance to the next page.
- Downward auto-pagination for NGA should only re-arm after the user has actually scrolled through the current page, preventing immediate double-jumps when a newly loaded page footer briefly appears on screen.
- Automatic page advance for NGA should use SwiftUI geometry signals from the top anchor and pagination footer instead of relying on footer row appearance, because `List` row lifecycle events are not a stable signal for "the reader actually reached the bottom".
- The geometry-based auto-pagination path should use a non-lazy reply stack. With roughly 20 replies per page, `LazyVStack` can recycle the off-screen top anchor and bottom footer sentinel, which shows up as missing baseline/footer measurements and makes downward paging appear completely unresponsive.
- The page picker should feel visually related to the floating controls: compact glass surfaces, quick first/last-page shortcuts, and a lightweight confirmation row instead of a dense divider-heavy list.
- Floor labels in NGA thread detail should prefer source-provided floor numbers and only fall back to page-aware local inference when the parser cannot recover them.
- Reply pagination must protect against duplicate content from source-specific continuation pages.
- Image handling mixes static images, GIF playback, preview, zoom, and save-to-photos behavior.
