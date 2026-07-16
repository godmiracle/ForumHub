## Why

V2EX 浏览当前存在四个可复现的核心路径缺陷：信息流的下拉刷新没有完整覆盖短内容的“最热”默认频道，“最热”被硬编码为不可续载，普通节点页的有效主题会因脆弱的 HTML selector 被解析为空，恢复 V2EX 作为启动来源时默认“最热”又不会高亮。用户因此不能稳定刷新或继续浏览默认频道、无法浏览“问与答”“二手交易”等栏目，并会看到与实际选择不一致的频道状态。

## What Changes

- 让首页和热门信息流的实际 `ScrollView` 支持下拉刷新，并继续复用 `ForumViewModel.reload()` 的取消与 generation 隔离语义。
- 让内容不足以自然滚动的 V2EX “最热”Feed 仍保留纵向回弹与系统下拉刷新能力。
- 让 V2EX “最热”首屏保留官方每日 Top 10，并在滚动到底部后按 PC 页“更多新主题”的 `/recent` 目标续载、去重。
- 加固 V2EX 普通节点主题列表解析，按语义识别主题链接，不依赖 `topic-link` class 或 HTML 属性顺序；保留 `/go/<node>?p=<page>` 的现有请求路径。
- 让 `ForumViewModel` 恢复持久化 V2EX 来源时，`forum`、默认频道和顶部选中 ID 从初始化开始保持一致。
- 为刷新接线和 V2EX 节点页真实响应变体补充回归测试，确保有效页面不会静默映射为空主题列表。

## Capabilities

### New Capabilities

- `forum-feed-refresh`: 信息流在实际可滚动区域通过下拉手势触发当前上下文的首屏重载。
- `v2ex-channel-topics`: V2EX 普通节点页可稳定解析主题及分页，不受非语义 HTML 属性差异影响。

### Modified Capabilities

- 无。

## Impact

- 受影响代码：`ForumHub/Features/ForumFeed/ForumFeedViews.swift`、`ForumHub/Features/ForumFeed/ForumViewModel.swift`、`ForumHub/ContentView.swift`、`ForumHub/Data/V2EX/V2EXThreadRepository.swift`。
- 受影响测试：Feed 展示/请求代次测试，以及 V2EX 节点 HTML parser/Repository 请求测试。
- 不修改共享领域模型、公开协议、会话模型或依赖；不改变 NGA、LINUX DO 的远端请求语义。
