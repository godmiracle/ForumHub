# Planning Context

## 已确认现状

- Feed 的真实滚动容器位于 `ForumFeedContent` 内部；`ContentView` 当前只在组合后的外层 View 上添加 `.refreshable`，没有向内部 `ScrollView` 传入刷新动作。
- `ForumViewModel.reload()` 已把首屏页码重置为 1，并通过 ADR-009 定义的 task cancellation 与 generation 防止过期响应回写，无需新增刷新状态机。
- V2EX `fetchForum` 对 `hot`、`latest` 和普通节点分流；普通节点 URL 由 `webBaseURL/go/<channel.nativeKey>?p=<page>` 构造，`qna` 与 `all4all` 的路径与线上节点一致。
- 线上 `qna`、`all4all` 节点当前均有主题；空列表不是服务端“暂时无主题”。
- `V2EXRecentPageParser.parseTopic` 的主题正则要求 `<a href="/t/..." class="topic-link">` 的固定属性顺序与 class；现有单测只覆盖这一理想化结构，缺少普通节点真实 HTML 变体。

## 最小实现接缝

- UI：`ForumFeedContent.onRefresh` → 内部 `ScrollView.refreshable` → `ContentView` 的 `viewModel.reload()`。
- Adapter：只修改 `V2EXRecentPageParser` 的 item 内 anchor 识别；不改 `ThreadRepository`、领域模型、认证或频道 URL。
- Tests：真实形状 HTML Fixture + parser/URL 请求测试 + 固定 Mock 下拉刷新 UI Test + 既有 generation 回归。

## 必须保持的不变量

- View 不解析 V2EX 原始响应。
- 公共论坛浏览不依赖登录；不得以 `getV2NodeTopics` Token API 替换匿名节点页。
- 新刷新继续使用同一 feed request context，过期响应不得覆盖来源、频道或 Tab 切换后的列表。
- 自动化不依赖实时 V2EX 网络；线上节点只用于人工验收。

## 已读取证据

- `README.md`、`docs/context.md`、`CONTEXT.md`、`docs/architecture.md`、`docs/decisions.md` 中 ADR-009/017、`docs/todo.md` 相关 Feed/V2EX 条目、`docs/modules/v2ex.md`。
- `ForumHub/Features/ForumFeed/ForumFeedViews.swift`、`ForumHub/Features/ForumFeed/ForumViewModel.swift`、`ForumHub/ContentView.swift`。
- `ForumHub/Data/V2EX/V2EXThreadRepository.swift` 与 `ForumHubTests/ForumHubTests.swift` 的现有 V2EX parser 测试。

## 待实现阶段确认

- 从当前线上节点页取得并脱敏固化原始 HTML Fixture；若网络受限，先以已确认的 selector 变体构造最小 Fixture，并在真机人工验证补齐证据。
- 结合现有 `UITestScenario` 选择最小的刷新可观测标记，避免让 UI Test 访问真实网络。
