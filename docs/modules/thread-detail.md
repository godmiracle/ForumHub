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
- V2EX reply hierarchy is a derived forest over the canonical linear API replies. The View consumes optional relation metadata, never reparses V2EX `@username` or `#floor` text, and can fall back to the unchanged flat list.
- V2EX tree mode caps visual indentation at three levels, reverses root groups without reversing parent-child direction, and yields to exact flat only-author filtering.
- A verified leading V2EX reference may be omitted only from the visible tree projection; accessibility, sharing, snapshots and the authoritative content document retain the full text.
- Rich reading, long-image snapshots, image enumeration, reply previews, accessibility text and pagination signatures consume `ForumPostDocument.blocks` or explicit projectors; they never reparse flattened text.
- NGA API/Web 正文共用一个来源层 HTML 容错扫描器，不按站点 class 逐项适配：块级容器保留段落边界，行内/未知元素去壳保留可读子内容，列表保留项目符号，安全链接、图片与视频降低为正式语义节点；`script/style/template`、事件属性和 `javascript:` 链接不会进入阅读文档。远端字号/行高不接管 App 字体与动态字体，原始 HTML 只保留在 representation 中用于追溯。
- 视频封面整块作为原位播放入口，点击后使用系统 `VideoPlayer`；同一个详情页共享单视频协调器，激活新视频会暂停旧视频。浏览器打开仅保留在长按菜单作为失败兜底，长图使用视频封面、播放标记和文本语义降级。
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
- NGA 回复编辑器在同一 Sheet 内切换正文输入与内嵌表情面板；切换过程保留回复目标、富文本选择位置和附件，点击正文可返回键盘模式。Sheet 固定使用 `.large`，不再根据键盘高度动态压缩，避免标题和快捷表情被裁切。富文本编辑器以每代只执行一次的异步焦点命令管理 first responder，关闭期间不会重新抢占键盘；回复目标统一在 Sheet `onDismiss` 清理。发布期间显示明确的“发布中”，禁用重复发布、附件修改和下滑关闭，但关闭按钮仍可取消当前 Task、退出面板并保留草稿；主动取消不显示失败。发布状态不得切换底层 `UITextView.isEditable`，避免 UIKit 键盘退出与 SwiftUI Sheet 更新形成 watchdog 循环。登录校验、超时或 Repository 错误必须由当前回复 Sheet 呈现，失败后保留编辑器、回复目标、正文草稿和附件，不得从背后的详情页发起竞争式弹窗。NGA 回复上下文和附件上传等待完整响应；最终 POST 收到正文静默 1 秒后结束读取。若写连接不收尾，Repository 并行以只读详情 API 确认回复总数增长，确认后取消悬挂请求，令成功分支关闭编辑页并刷新详情；数秒内无法确认则显示明确提示。服务器返回的拒绝文案必须原样呈现。六组分类使用横向滚动导航，表情网格支持连续插入且不因单项图片加载失败关闭面板；标准 NGA smile PNG 由 App 内置资源优先兜底，运行时缓存按文件名保存；工具栏在空间不足时切换为两行，并为主要操作和分类按钮保留至少 44pt 点击区域。
- The bottom action bar should separate hierarchy without adding text labels: reply remains an independent prominent circular action, while author filtering, sharing, and more actions sit on one compact secondary glass capsule; inactive secondary actions do not add nested circular surfaces.
- When the source returns quote metadata, the detail body should render it as a dedicated inline quote card instead of flattening it into plain text, so users can immediately distinguish "回复主题" from "回复某层".
- Reply pagination must protect against duplicate content from source-specific continuation pages.
- Refresh, explicit page jumps, and automatic continuation loading share one cancellable content-load task. A monotonically increasing generation prevents a stale request from committing state after a newer load has begun.
- Reply filtering, ordering, and page-anchor entries are cached as derived presentation state and refreshed only when their source replies, paging metadata, filter settings, or blocked-user list changes.
- Thread detail converts repository and transport errors into `ForumError` before presentation, keeping raw transport and parser descriptions out of user-visible error cards.
- Floating controls and page selection surfaces use the shared `ForumGlass` DesignSystem components, keeping iOS 26 glass rendering and older material fallbacks visually aligned.
- NGA continuation pages are merged through `ThreadDetailPaginationMerger`; it removes repeated main-post payloads and deduplicates replies by both source identifier and reply signature before the view updates pagination state.
- Image handling mixes static images, GIF playback, preview, zoom, and save-to-photos behavior.
