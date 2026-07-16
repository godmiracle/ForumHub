# Changelog

## 2026-07-16 NGA 详情语义内容与 API-first 架构

- 用带来源 representations、版本、质量、diagnostics、provenance 和 occurrence 身份的 `ForumPostDocument.blocks` 替代 `normalizedText` 正文权威；共享渲染、长图、预览、图片枚举和分页签名直接消费语义节点。
- NGA API/Web Parser 分别将 BBCode 与精确 `postcontent<floor>` HTML 降低为相同语义节点，未知标记安全保留；NGA 表情与附件 URL 规则移回 NGA 适配层。
- 详情改为 API-first：valid/degraded API 零 Web 请求；仅 unusable 正文按同楼层整文档回退 Web，并保留 API 身份、元数据、成员与顺序。
- 删除 `NGAThreadDetailMerger` 的逐行拼接、contains、空白/大小写归一化、全局去重和末尾追加逻辑；API transport 完全失败返回 typed error，并保留浏览网页原帖入口。
- 新增脱敏 `47185513` 形状、API 空正文、API 失败、Web 可回退、Web 权限拒绝和双源 unusable Fixture；修复 BBCode tokenizer 失效正则、continuation 页空主楼误判，以及迟到的跳页/fallback 请求覆盖新状态或遗留 loading 状态的问题。真机完整 `ForumHubTests` 121 项通过；真实 `47185513` 的图片、表情、引用和两页连续阅读，以及确定性的 GIF、Web fallback、Web access denial 和取消路径均已验证。
- 修复 NGA `[quote][tid]Topic[/tid]` 引用变体被当作原始字符显示的问题；Parser 现在按标记边界读取引用目标、作者、时间、换行与引用后正文，并保留脱敏真机形状 Fixture 防止回归。
- 修复 NGA 无外层 `[quote]` 的 `<b>Reply to [pid]...` 回复目标头泄漏问题；回复目标作者/时间现在形成独立引用卡片，当前回复正文和表情继续保持为后续有序语义节点。
- 修复 NGA API 正文内 `<del class='gray'>` 行内 HTML 泄漏问题；Parser 将删除线降低为来源中立的 inline semantic node，在原生阅读与长图中保留删除线，纯文本投影保留可读文字。
- 修复 unusable API 楼层在来源策略前被 Parser 丢弃的问题；主楼和回复现在保留 API 身份进入同楼层 Web fallback。组合来源时 Web block provenance 会指向偏移后的 Web representation；已获取 Web 时的有效同楼语义差异继续保留 API blocks，并记录不含正文的结构化 conflict diagnostic。

## 2026-07-15 NGA 主楼图片去重修复

- NGA API 与网页正文合并时按规范化后的图片 URL 识别跨来源重复项，避免相对地址和绝对地址指向同一附件时在 0 楼重复显示。

## 2026-07-13 iCloud 同步可靠性修复

- 屏蔽名单改为逐记录 KVS key，避免首次同步或并发修改整包覆盖；
- 区分首次同步、服务端变化、配额异常和 Apple Account 切换；
- 屏蔽页显示 iCloud 同步状态与失败降级；
- Token/Cookie Keychain 写入改为原子 upsert，失败时保留旧凭证；
- App 返回前台时节流重试凭证恢复；
- 明确 App 退出登录不等同于论坛服务端的全设备会话撤销。

## 2026-07

### Thread Detail And Content

- Split the icon-only thread action bar into a prominent circular reply action and a compact secondary tool capsule, removing nested backgrounds from inactive secondary icons while retaining full-size hit targets.
- Combined the lower-right scroll-to-top and direct-pagination controls into one compact capsule, removing redundant `TOP` and `PAGE` labels while preserving standalone scroll-to-top access for sources without direct pagination.
- Unified thread sharing under one detail action, with separate choices for the original thread link, the main-post snapshot, and loaded-content snapshots; link shares include the post title before the original URL.
- Branded generated snapshots as “汇坛”, added source-provided floor numbers to reply snapshots, and made the footer describe whether the image contains the main post, one reply, or the currently loaded reply count.
- Promoted sharing to the thread detail action bar after the author filter, and moved the state-aware favorite action into the More menu.
- Prioritized the main-post snapshot as the first action in the thread sharing menu.
- Prevented an empty detail response from promoting a feed summary into the main post; feed metadata can still fill title, author, counts, and channel information.
- Made saved favorites restore as lightweight thread metadata without storing their summary as authoritative post content.
- Updated long-image generation to consume `ForumPostDocument` projections directly instead of extending the legacy `body` dependency.
- Updated reply previews, pagination main-post deduplication, and NGA content-quality checks to use the authoritative `ForumPostDocument` projection.

### V2EX Accounts And Favorites

- Upgraded the existing V2EX web-login shell into a verified, Keychain-persisted cookie session that restores into WebKit and shared HTTP cookie storage without exposing the API token.
- Added V2EX source-native favorite listing, add, and remove flows through the authenticated website session; action URLs are parsed from the current topic page and restricted to the matching V2EX host and topic ID.
- Kept the existing local favorite Store as a lightweight mirror after the remote V2EX operation succeeds.
- Verified favorite mutations by reloading the topic page because V2EX action responses do not consistently contain the updated topic controls.

### iCloud Sync

- Enabled the iCloud key-value-store entitlement for the production app target.
- Added per-source blocked-user synchronization using timestamped records and deletion tombstones, with UserDefaults retained as an offline cache.
- Moved NGA, V2EX, and LINUX DO Token/Cookie Keychain items to iCloud-synchronizable storage; credentials never enter iCloud KVS.
- Removed the standalone local-favorites screen and disabled favorite actions for sources without source-native favorites. NGA and V2EX retain only a lightweight UI cache.
- Unified V2EX web-session status with the default WebKit cookie store so account connection state, original-page browsing, and source-native favorites observe the same verified session.

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

- Fixed same-thread detail refreshes being ignored when the full main post replaced a feed summary; thread content equality now includes all rendered fields while identity checks remain explicitly source-and-ID based.
- Prevented feed summaries from being shown as 0楼正文 while a thread detail request is pending; the detail page now waits for the authoritative post content before rendering it.
- Fixed NGA main-post media loading so a SwiftUI task cancellation is not shown as an image failure; the main-post floor tag now correctly displays `0楼`.
- Made NGA detail loading reconcile every page with the source web document before presenting it, preventing a transient first API response from showing a truncated main post; nested HTML containers now preserve their full post content during extraction.
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
- Redesigned the thread reply composer as a compact expandable glass panel above the keyboard, with a clearer reply target, inline attachments, fixed publishing controls, and a quick emoji row while preserving the existing NGA posting pipeline
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
