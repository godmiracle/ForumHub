# Changelog

## 2026-06

### Product Evolution

- Evolved the app from an NGA prototype into the multi-source `ForumHub` shell
- Kept source-specific behavior behind adapters while moving product-level naming to `ForumHub`

### Sources And Accounts

- Added LINUX DO source integration
- Added LINUX DO web login with cookie reuse
- Kept NGA web login and session persistence as a first-class source flow
- Continued V2EX support through the existing token-based account path

### Home And Community

- Moved source switching into the Home top-left menu
- Refocused the Community tab on channel management instead of primary source switching
- Added channel subscription management
- Added drag reordering for subscribed channels

### Thread Detail

- Added thread detail floor labels
- Added only-author mode
- Added reverse reply ordering
- Added NGA thread-detail explicit pagination with previous/next controls and a page picker
- Moved NGA pagination controls into the lower-right floating control area for faster one-handed access
- Fixed NGA page switching so later pages replace the visible reply slice instead of appearing unchanged
- Fixed NGA floor labels and page-count display so explicit pagination no longer reuses page-local reply counts as global paging state
- Restored downward scroll-to-next-page behavior for NGA while keeping explicit page state in sync
- Fixed NGA downward auto-pagination so entering a new page no longer immediately re-triggers another page jump before the user scrolls through that page
- Reworked NGA downward auto-pagination to observe SwiftUI geometry from the page top and pagination footer instead of footer row appearance, improving reliability when continuing to the next page by scrolling
- Replaced the thread-detail `List` container with a `ScrollView` stack so NGA auto-pagination can receive stable continuous scroll geometry again
- Replaced the NGA reply `LazyVStack` with a regular `VStack` so auto-pagination keeps stable top/footer anchors instead of losing geometry state and ignoring further downward scrolling
- Reworked NGA thread detail into a continuous infinite-scroll reading flow that appends later reply pages instead of replacing the visible reply slice
- Updated the lower-right NGA page control so its page number follows the currently visible scroll position and page jumps can load intermediate pages before scrolling into place
- Removed the mid-stream NGA "continue scrolling to load next page" card so continuous reading now preloads later pages without interrupting the reply flow
- Reduced NGA detail scroll-time geometry work by tracking visible page from page anchors instead of every reply row, improving long-thread scrolling smoothness
- Simplified NGA infinite-scroll triggering to a single footer-sentinel `onAppear` path and removed the extra gesture-driven and geometry-threshold trigger branches
- Cached thread rich-content parsing and precomputed visible reply page metadata so very large NGA threads no longer reparse the first page on every scroll-driven redraw
- Debounced NGA footer auto-pagination to one trigger per source page and removed the floating page-control loading spinner so long-thread reading no longer looks or feels stuck on page 1
- Replaced NGA footer `onAppear` auto-pagination with footer-geometry gating tied to the currently visible page, preventing first-screen runaway preloading on very long threads
- Relaxed NGA footer auto-pagination gating to depend on actual downward scroll depth plus footer proximity, and made the scroll-to-top button appear whenever the reader has scrolled far enough down
- Reduced extra bottom spacing for NGA direct-pagination detail pages so the next-page trigger can be reached before the reader gets stranded above a large blank gap
- Fixed NGA detail auto-pagination locking so a blocked or skipped next-page request no longer prevents later refresh or continued scrolling from retrying normally
- Replaced the fragile NGA footer-geometry auto-pagination trigger with near-end reply-row preloading, so scrolling near the end of the loaded replies requests the next page through the same loading path as the manual page arrow
- Separated NGA automatic preloading from explicit page navigation so the floating page control follows the visible page while previous/next buttons still scroll to adjacent page anchors
- Pulled the lower-right thread-detail controls closer together and restored the scroll-to-top affordance whenever the reader has moved beyond the opening page
- Refined the NGA page-picker sheet with a cleaner glass layout and quicker first/last-page actions
- Further polished the NGA pagination controls so the floating capsule and picker sheet feel like one visual system
- Unified the thread-detail scroll-to-top button with the pagination control's glass material treatment
- Unified the floating control entrance and exit animations in thread detail for a smoother shared motion language
- Reworked the thread detail action bar into a floating icon-first layout
- Added extra protection against duplicate main-post rows during NGA thread pagination

### Replies And Favorites

- Added thread favorites and local persistence
- Added thread reply support
- Added NGA reply image attachment support

### Images And Rich Content

- Added in-thread image preview
- Added GIF playback support
- Added image saving to Photos
- Added preview zoom support
- Improved GIF loading with request reuse and local file-backed playback

### Stability And UX

- Hardened feed cancellation handling to avoid showing `cancelled` as a user-facing error
- Continued refining thread pagination and loading-state behavior
- Updated the dark and tinted iOS app-icon variants to the latest provided artwork
- Localized the app display name so Simplified Chinese shows `汇坛` while English continues to show `ForumHub`
- Centered the thread-detail reply loading state so the temporary loading card reads like a page-level status instead of left-aligned body content
- Prevented the first forum-feed render from flashing the empty-state message before the initial topic request completes
- Reduced thread-detail image decode cost by downsampling remote image previews before display while keeping GIF playback available inline
- Unified thread-detail image tap handling so GIFs and static images both reopen the same preview surface reliably
- Refined thread-detail image preview actions so save and close sit together in a right-side centered floating group while link actions remain in the long-press menu
- Reduced long-thread GIF energy cost by keeping inline animation active only for a few images near the visible viewport

## How To Update

- Add new entries under the current month until a versioned release process exists.
- Group user-visible changes by feature area instead of file or implementation detail.
- Pair major product or architecture changes with updates to [docs/decisions.md](/Users/v/XBP/ForumHub/docs/decisions.md).
