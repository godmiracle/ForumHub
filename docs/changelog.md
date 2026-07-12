# Changelog

## 2026-06

### Product Evolution

- Evolved the app from an NGA prototype into the multi-source `ForumHub` shell
- Kept source-specific behavior behind adapters while moving product-level naming to `ForumHub`

### Sources And Accounts

- Added LINUX DO source integration
- Added LINUX DO web login with cookie reuse
- Added a LINUX DO browser-context fallback for Cloudflare-blocked JSON requests, plus an in-feed "打开浏览器验证" recovery action that reloads the feed after verification.
- Kept NGA web login and session persistence as a first-class source flow
- Continued V2EX support through the existing token-based account path

### Home And Community

- Moved source switching into the Home top-left menu
- Refocused the Community tab on channel management instead of primary source switching
- Added channel subscription management
- Added drag reordering for subscribed channels

### Thread Detail

- Added an in-app NGA "Browse original web thread" reader in the detail More menu. It restores and injects the active NGA cookie session before loading; a Debug-only action can copy the current raw response for parser regression investigation.
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

- Added a separate V2EX in-app web-login session for authenticated original-page browsing without exposing the API token to webpages.
- Added a unified in-app “浏览网页原帖” action in thread details for NGA, V2EX, and LINUX DO.
- Fixed NGA `[s:…]` smile markup being removed during native thread parsing; common expressions now render inline and unknown ones retain their readable name.
- Added in-thread image preview
- Added GIF playback support
- Added image saving to Photos
- Added preview zoom support
- Improved GIF loading with request reuse and local file-backed playback

### Stability And UX

- Preserved HTML image sources in NGA main-post normalization so detail pages no longer drop those images before rendering.
- Prevented stale feed responses from showing parse errors or replacing content after the reader switches tabs or sources.
- Fixed Home and Hot tab reselection so each feed returns to its own list top immediately while refreshing in the background.
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
- Upgraded thread-detail replies to carry stable source post IDs, added a shared reply-target model, let the composer retarget from thread reply to per-floor reply through the same sheet flow, and render quoted floor replies with an inline reference card so readers can tell whether a post answers the thread or a specific floor
- Removed the default "回复主题" badge from normal replies and added compatibility for legacy NGA reply headers like `Reply to Reply Post by ...`, so older floor-to-floor replies can also render more like structured references
- Expanded the per-floor detail menu with user blocking and single-floor snapshot sharing, and wired blocked users into thread detail so blocked replies disappear immediately there as well
- Restored per-floor snapshot behavior so both the main post and reply floors expose "截图此层", and changed snapshot generation back to a preview-first flow instead of jumping straight into the system share sheet
- Added the first NGA reply-emoji flow in the composer: users can open grouped NG娘 / AC娘v1 / AC娘v2 pickers and append smile assets into the reply body as image UBB markup without touching the attachment upload pipeline
- Upgraded the NGA reply composer from plain text to a rich emoji-aware editor so selected smile assets insert at the current caret position and render inline in the input area while still serializing back to the original body markup for posting
- Stabilized inline emoji editing in the NGA reply composer by giving each inserted smile a hidden text anchor, preventing attachment-only input rows from rendering as blank while keeping outgoing markup unchanged
- Fixed thread "截图此层/长图" rendering so vertically taller images also expand to the card width instead of appearing narrower than earlier images on the same snapshot
- Refactored the account screen's "社区连接" area to render from shared auth session descriptors, unifying `NGA`, `V2EX`, and `LINUX DO` connection summaries without flattening their underlying auth flows
- Redesigned the user screen to emphasize shared account summaries, hide low-level credential implementation details, and group account, personal data, and maintenance actions more clearly
- Restored readable NGA identity text in the user screen so connected `NGA` sessions now show a user-facing `UID` summary just like other sources show their current account identity
- Corrected the first `V2EX` top channel from `最新` to `最热` and wired it to the same hot-feed loading path as the source's `?tab=hot` web entry
- Restored `V2EX` fixed top-channel switching so `最热` stays as the first entry while `最新` also remains available and readers can always switch back to the hot feed after browsing other nodes
- Simplified the `V2EX` top-channel row again so only `最热` stays pinned; `最新` is no longer exposed as a separate tab because the shared "最新发帖" sort already covers that reading mode
- Forced the `V2EX` `最热` channel to remain visible and pinned to the front of the home channel row, so saved local channel orders can no longer hide it behind nodes like `问与答`
- Relaxed the `V2EX` `最热` handling so it is only used as the initial/default first channel and a one-time migration target; after that, manual drag reordering is respected normally
- Fixed the `V2EX` default hot-channel selection state so entering the source highlights `最热` correctly again, and switched unauthenticated node lists like `问与答` back to web-page parsing so author names and avatars no longer collapse to placeholder-only metadata
- Decoded common HTML text entities such as `&#39;` and `&quot;` in the shared forum-text cleaning layer so list cards, thread bodies, and quote blocks no longer leak raw entity codes into readable content
- Replaced the custom floating bottom bar with a system `TabView` shell, restoring native tab-bar height and base glass behavior while keeping tab reselect scroll-to-top and refresh actions through a lightweight UIKit bridge
- Refined the new system tab shell so root pages use a unified paper background and tab reselect handling listens at the `UITabBar` level, reducing layout gaps and making scroll-to-top recovery more reliable

## How To Update

- Add new entries under the current month until a versioned release process exists.
- Group user-visible changes by feature area instead of file or implementation detail.
- Pair major product or architecture changes with updates to [docs/decisions.md](/Users/v/XBP/ForumHub/docs/decisions.md).
