## Context

`ContentView.feedTabContent` 当前把 `.refreshable` 修饰在 `ForumFeedContent` 的外层返回值上，而真正承载纵向滚动的是 `ForumFeedContent` 内部的 `ScrollView`。刷新环境没有可靠落到实际滚动容器，因此顶部刷新按钮和 `ForumViewModel.reload()` 可用，但下拉手势不可用。

首轮接线后真机反馈进一步显示：普通长节点可以下拉，但默认“最热”仍不能稳定触发。两者复用相同刷新 closure；结构差异是热门 API 结果短或失败空态时内容可能不足以自然滚动，而 Feed 没有显式保证纵向回弹。该原因在回归复现前保持“高概率”，不得描述为已确认。

启动高亮另有独立且已确认的状态根因：`ForumViewModel.init()` 从 `active-forum-source-v1` 恢复 `.v2ex` 后设置了 `selectedForum = .v2exHot` 和 `channels = [.v2exHot]`，但 `forum` 仍保留属性默认的 NGA `defaultForum`。`ContentView.task` 在首次 reload 前把 `viewModel.forum.id` 写入 `selectedChannelID`，于是得到 `-7`；reload 虽更新 `forum`，却不会再次同步顶部选中 ID。来源切换路径会显式写入 V2EX 默认 forum，因此切换时高亮正常。

用户提供的 `/api/nodes/list.json?fields=name,title,topics,aliases&sort_by=topics&reverse=1` 返回按累计主题数排序的节点目录，适合 `fetchChannels()`，不返回热门主题。V2EX “最热”主题继续使用 `/api/topics/hot.json`，不盲接节点列表接口。

进一步核对 PC `/?tab=hot` 后确认，页面底部“More Recent Topics / 更多新主题”的链接目标是 `/recent`；点击时观察到的 `nodes/list.json` 是同页节点目录辅助请求，不包含帖子 ID、标题或作者。因此 App 的“最热”第 1 页保留官方每日 Top 10，第 2 页开始映射为 `/recent?p=1`、`/recent?p=2`，并复用 Feed 的主题 ID 去重。“最热”是跨节点聚合视图而非真实节点，主题继续保留 API `topic.node` 或 HTML 条目 `/go/<node>` 所表达的真实节点标签。

V2EX 普通栏目已使用正确的 `/go/<nativeKey>?p=<page>` 路径，并且线上“问与答”(`/go/qna`) 与“二手交易”(`/go/all4all`) 页面确实包含主题。空列表发生在适配层：真实节点主题位于 `TopicsNode` 内的 `cell from_<uid> t_<topicid>` 容器，而旧 parser 只切分 `cell item` 并要求属性顺序固定且带 `class="topic-link"` 的 `<a>`。节点页主题链接的稳定语义实际是容器 `t_<topic-id>` 与局部 `/t/<topic-id>` 锚点；页面结构差异会使 `compactMap` 全部失败，却仍被当作成功的空 payload。真实下一页控件也使用带 `title="Next Page"` 的 onclick，而非固定 `<link rel="next">`。

约束包括：View 不解析来源响应；刷新继续遵守 ADR-009 的取消和 request generation；修改不得引入第三方 HTML parser 或改变多来源 Repository 协议。

## Goals / Non-Goals

**Goals:**

- 把下拉刷新接到 Feed 的实际 `ScrollView`，覆盖首页与热门页。
- 让 V2EX 普通节点页按稳定的主题链接语义提取 ID、标题、作者与回复数，并保留分页能力。
- 用刷新交互回归和接近真实节点页的 HTML Fixture 防止两个缺陷复发。

**Non-Goals:**

- 不重构 `ForumViewModel` 的加载状态、取消或 generation 机制。
- 不改用需要 Token 的 V2EX API v2 节点主题接口，也不要求用户登录后才能浏览公共栏目。
- 不实现完整 DOM 引擎，不覆盖主题列表之外的 V2EX 网页结构。
- 不改变频道订阅、排序、筛选或横向切换语义。

## Decisions

### 1. 在 `ForumFeedContent` 内部注入异步刷新动作

为 `ForumFeedContent` 增加 `onRefresh: () async -> Void`，在内部 `ScrollView` 直接应用 `.refreshable { await onRefresh() }`；`ContentView` 传入 `viewModel.reload()` 并移除外层重复 modifier。这样刷新指示器的生命周期由 async action 驱动，同时所有来源继续共享现有重载入口。

替代方案是保留外层 modifier 或自己实现 `DragGesture` 阈值。前者正是当前失效接线，后者会与频道横滑、滚动和系统刷新交互竞争，均不采用。

### 2. V2EX 节点页按语义锚点解析，不绑定 class 和属性顺序

保留 `getWebNodeTopics` 的 `/go/<node>` URL 构造。节点页存在 `TopicsNode` 时，Parser 只切分其中同时带 `cell` 与 `t_<digits>` class token 的主题容器，并要求局部 `/t/<digits>` 锚点 ID 与容器 ID 一致；`/recent` 和收藏页不存在 `TopicsNode` 时继续兼容旧 `cell item`。主题锚点允许 `#reply...` 或 query，并从 inner HTML 生成清理后的标题；不要求 `class="topic-link"`，也不假定属性顺序。作者头像、member fallback 和回复数解析同样只依赖局部 item，现有字段缺失时保持安全默认值。分页同时接受 `title="Next Page"` 的真实 onclick 控件。

替代方案是启用已有但当前未调用的 Token API v2 节点请求。该方案会把公共浏览变成认证依赖，违反现有产品不变量，因此不采用。引入 SwiftSoup 等依赖对本次窄修复也过重。

### 3. 用真实形状 Fixture 覆盖 selector 变体和空页面边界

新增脱敏的 V2EX 节点页 Fixture，至少包含无 `topic-link` class、属性顺序变化、回复锚点和下一页标记。测试断言主题 ID/标题/作者/回复数以及 `hasNextPage`。另保留空节点/无有效主题时返回空数组的边界，避免把任意 `/t/` 导航链接误识别为主题。

Feed 侧增加可重复的 UI 回归：在固定 Mock 场景对 Feed 执行下拉，断言刷新动作被触发并完成；`ForumViewModel.reload()` 的 generation 行为继续由既有请求代次测试保护。

### 4. 启动来源初始化保持单一一致状态

默认初始化复用已有 `init(repositories:initialSource:)` 的 forum 构造，不在 `ContentView` 增加第二套补偿同步。测试用隔离 `UserDefaults` 恢复 V2EX，断言 `source`、`forum.id`、首个 channel 和 Repository 默认频道在首帧一致。

### 5. 短 Feed 下拉使用系统回弹能力

先在固定 V2EX hot 短列表 UI 场景验证修复前是否稳定无法触发下拉。若可稳定复现，在真实 Feed `ScrollView` 上显式使用 `.scrollBounceBehavior(.always, axes: .vertical)`，继续由系统 `.refreshable` 处理手势，不增加自定义 DragGesture。若自动化无法稳定复现，则只把测试作为结构/状态验收，并在结论中保留未确认标记。

### 6. “最热”续载遵循 PC 页的更多新主题入口

`/api/topics/hot.json` 只提供每日 Top 10 且没有分页参数，所以第 1 页之后不得伪造热门页码。将 App 的 hot page 2 映射到 `/recent?p=1`，hot page 3 映射到 `/recent?p=2`，以此类推；`V2EXRecentPageParser` 解析主题、真实节点和下一页标记，`ForumViewModel.loadNextPage()` 保持现有 generation 检查和 ID 去重。`nodes/list.json` 继续只负责频道目录，虚拟“最热”不得覆盖主题自身的真实节点。

Home 顶部“最热”通过 `.forum` 路径展示相同 Repository 结果，底栏“热门”通过 `.hot` 路径展示。`.forum` 首屏与分页不得无条件调用 `withChannel(selectedForum)`；仅当 Repository 结果缺少有效 `channelID/channelTitle` 时才把当前选择作为 fallback。这样两条入口的主题 ID、顺序与真实节点标签保持一致，同时普通 Repository 未提供节点元数据时仍有展示兜底。

## Risks / Trade-offs

- [V2EX 再次调整 item 容器] → Fixture 使用当前真实响应形状；匹配范围与主题 anchor 规则分离，后续只需调整容器定位。
- [宽松 anchor 误取非主题链接] → 仅在主题 item 容器内部接受 `/t/<纯数字>`，并用包含头像、回复链接等干扰项的测试验证。
- [刷新与横向频道手势并存] → 使用系统 `.refreshable` 而非新增纵向 DragGesture，并在真机对下拉和横滑分别验收。
- [线上 V2EX 页面无法稳定用于 CI] → 自动化只使用脱敏 Fixture/可控 Mock，线上页面仅作为人工验证。

## Migration Plan

无数据迁移。实现可按“Parser + 单测”与“刷新接线 + UI 回归”两个独立小步落地。若出现回归，可分别回滚 `ForumFeedContent` 的 refresh closure 接线或 Parser selector 变更，不影响持久化状态。

## Open Questions

- 无。实现前从当前线上节点页重新脱敏固化 Fixture 即可；若网络不可用，使用已确认的节点页结构变体手工最小化 Fixture，并在真机阶段补做线上验证。
