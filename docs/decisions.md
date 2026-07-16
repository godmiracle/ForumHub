# Decisions

## ADR-001 Product Shell Stays `ForumHub`

### Status

Accepted

### Date

2026-06

### Context

The app started as an NGA-specific prototype but now supports multiple community sources with shared reading flows, account surfaces, and local user state.

### Decision

Product-level naming stays `ForumHub`, while `NGA`, `V2EX`, and `LINUX DO` remain only where they describe source adapters or remote behavior.

### Consequences

- Multi-source UX can evolve without fighting an NGA-branded shell
- Shared modules are easier to reason about at the product level
- Legacy file names and notes may still need gradual cleanup

## ADR-002 Source Switching Lives In Home

### Status

Accepted

### Date

2026-06

### Context

Users spend most of their time in the feed, and routing source switching through a separate community page added friction to a very common action.

### Decision

Move source switching to the Home top-left menu and let the Community tab focus on channel management, visibility, and ordering.

### Consequences

- Source switching becomes faster and closer to the active reading context
- Community has a clearer responsibility
- Feed and channel-management state must stay aligned across multiple entry points

## ADR-003 Thread Detail Ordering Is Presentation State

### Status

Accepted

### Date

2026-06

### Context

Users want reading preferences such as reverse order and only-author mode, but remote sources do not expose one consistent ordering contract.

### Decision

Handle reverse order and only-author filtering in the thread detail view layer instead of mutating repository output or source-specific parser behavior.

### Consequences

- Provider behavior stays stable and easier to debug
- Reading preferences can be combined locally
- Views must be careful to preserve true floor labels and pagination semantics

## ADR-004 iCloud Sync Is Disabled For Now

### Status

Accepted

### Date

2026-06

### Context

Favorites, blocked users, and other user state would benefit from sync, but the current project setup does not include the developer-account prerequisites to ship iCloud-backed behavior safely.

### Decision

Keep sync-related hooks in the repository, but disable iCloud-backed sync and avoid presenting it as an active product feature.

### Consequences

- Local-first behavior remains explicit and predictable
- Uninstall or device migration can still lose state
- Future sync work will need deliberate migration rules rather than implicit rollout

## ADR-005 LinuxDo Login Uses Web Login Plus Cookie Reuse

### Status

Accepted

### Date

2026-06

### Context

Direct authenticated API access for LINUX DO can be blocked by site protections or validation flows that are easier to complete in a browser context.

### Decision

Use a WebKit-driven login flow and shared cookie reuse instead of trying to implement a fully native authenticated API path first.

### Consequences

- Login is more resilient to browser-style validation flows
- The account experience depends on cookie correctness and session reuse
- This approach is pragmatic but less elegant than a clean native auth contract
- A direct JSON request that receives `403` may need to be retried from the WebKit context; an explicit verification entry remains necessary when that context is challenged too.

## ADR-006 GIF Handling Uses A Shared Image Pipeline

### Status

Accepted

### Date

2026-06

### Context

Inline GIF rendering was slow and unstable when every view independently downloaded and initialized animated assets.

### Decision

Use a shared remote image pipeline with in-memory reuse, in-flight request reuse, and local file-backed GIF playback support.

### Consequences

- GIF rendering becomes more stable across scrolling and preview flows
- Image behavior is centralized, which reduces duplicated networking logic
- Bugs in the shared image path can affect multiple rich-content surfaces at once

## ADR-007 NGA Thread Pagination Keeps Source Fetches But Uses A Continuous Reading Flow

### Status

Accepted

### Date

2026-06

### Context

NGA still returns reply data in discrete source pages, but reading one page at a time made the detail screen feel interrupted and made the floating page control reflect only the last loaded page instead of the reader's actual scroll position.

### Decision

Keep NGA thread fetching source-shaped, but let the detail screen accumulate continuation pages into one continuous reply list. The floating page control should derive its current page from scroll position, while still using source-page fetches and duplicate protection underneath. Intermediate page loads should happen through an invisible footer trigger instead of a visible "load next page" card, reserving visible terminal state only for the true end of the thread.

### Consequences

- Cross-page reading becomes continuous instead of requiring page-by-page replacement
- The floating page indicator can track the reader's visible page instead of only the latest fetched page
- Mid-thread reading stays visually uninterrupted, while the UI still has an explicit end-of-thread state when no more replies remain
- Detail-state logic must keep page anchors and duplicate filtering stable while local presentation options remain layered on top

## ADR-008 Auth Uses A Shared Session Descriptor But Keeps Source-Level Auth Stores

### Status

Accepted

### Date

2026-07

### Context

ForumHub already supports three different authentication styles: NGA cookie login, V2EX token validation, and LINUX DO web login plus cookie reuse. The current flows work, but the upper layer still reads too much source-specific auth detail directly when rendering account status and coordinating session restore.

### Decision

Add a thin shared auth presentation layer made of a shared session descriptor, a lightweight source-auth protocol, and an auth registry for aggregated restore and display. Keep concrete auth logic, cookie handling, token validation, and source-specific login entry flows inside each existing source auth store.

### Consequences

- The account layer gains one stable vocabulary for auth state across sources
- Future sources can plug into the account UI with fewer custom branches
- Source-specific auth behavior remains isolated instead of being flattened into one oversized global session store
- The project must maintain a careful boundary so the shared descriptor never turns into a raw credential transport object

## ADR-009 Feed Loads Use Cancellation And Request Generations

### Status

Accepted

### Date

2026-07

### Context

Home, Hot, source switching, channel switching, and tab reselection can start overlapping feed requests. Because the feed state is shared, a late NGA response could otherwise replace the active list or show a parse error after the reader had already moved elsewhere.

### Decision

Model each first-page feed load as an immutable request context. Starting a new context cancels the previous load and advances a generation; only the current generation may update feed state. Pagination also checks that generation before applying a result.

### Consequences

- A stale response cannot overwrite the active tab's content or error state
- Cancellation is propagated through NGA's fallback paths where possible
- Genuine parser failures remain visible when they belong to the currently active request
- Feed loading code has a more explicit lifecycle, at the cost of maintaining request-context fields

## ADR-010 Semantic Thread Content Is The Reading Authority

### Status

Accepted

### Date

2026-07

### Context

NGA 详情曾把 API 与网页分别转换成 `normalizedText`，再按行拆分、规范化和去重。该算法把表示差异误当内容差异，会误删合法重复段落/图片、把 Web 中间内容追加到末尾，并让每个新标签都需要扩展全局规则。对帖子 `47185513` 的真实观测显示 API 已包含 0–11 楼、两张图片、三个表情和引用；现有裁剪 Fixture 也不足以证明生产 API 普遍缺正文。

### Decision

每个主楼和回复保存 `ForumPostDocument`：原始 `representations` 用于追溯，带 occurrence 身份与 provenance 的有序语义 `blocks` 是原生阅读、分享、无障碍、快照、图片枚举和内容签名的唯一权威。Parser 返回 valid/degraded/unusable 质量与不含原始正文或凭证的结构化 diagnostics；未知但可读标记保留为 unsupported 节点。

NGA 采用 API-first：API 文档为 valid 或 degraded 时立即返回，不请求 Web。只有 API 已确认楼层的正文为 unusable 时才请求 Web，并按楼层选择整份 Web 语义文档，同时保留 API 的 `pid`、楼层、作者、时间、成员、顺序及 root metadata；Web-only 楼层不加入结果，只记录调查 diagnostic。API transport 完全失败时返回 typed error，详情页继续提供“浏览网页原帖”动作。

`ForumThread.body` 与 `Reply.body` 仅是语义 blocks 的只读纯文本 projector。禁止以 `normalizedText`、按行拆分、contains、大小写/空白归一化、全局 `Set` 或末尾追加方式协调双源正文。

双源 Semantic Reconciler 暂不引入。只有至少两个彼此独立、脱敏且可重复的真实配对 Fixture 都证明“API 与 Web 分别缺少不同的用户可见语义，且整份来源切换仍不足以恢复”时，才重新评估该组件。

### Consequences

- 合法重复内容和原有顺序不再被启发式去重破坏
- API 正常路径减少一次 Web 请求及其 Cookie、HTML 和 DOM 维护成本
- 新标签由来源 Parser 降低为既有或 unsupported 节点，共享 View 无需新增 NGA 分支
- Web 回退不补充 API 未确认楼层；网页结构变化会明确失败而不是污染正文
- 语义 schema、Parser 与 projector 需要版本化契约测试，且真机图片/GIF/长图仍需回归

## ADR-011 Separate Thread Identity From Content Equality

### Status

Accepted

### Date

2026-07

### Context

信息流中的 `ForumThread` 只包含摘要，详情请求会用同一帖子 ID 回写完整正文和回帖。此前手写的 `Equatable` 只比较 `source + id`，导致摘要版与完整详情版被视为内容相等，Observation 无法可靠驱动当前详情页更新。

### Decision

`ForumThread` 使用完整字段的内容相等语义。收藏、历史、信息流去重、搜索追加和导航身份等场景必须显式使用 `source + id`，不再复用 `Equatable` 表达身份。

### Consequences

- 同一帖子正文、内容文档、回帖或展示元数据变化时能触发详情更新
- 帖子身份判断不受内容更新影响，仍由各调用点显式使用 `source + id`
- 新增字段会自动参与合成的内容相等，需要确保字段本身遵循 `Equatable`

## ADR-012 Defer Splitting Thread Summary And Detail Models

### Status

Rejected for the current migration

### Date

2026-07

### Context

`ForumThread` 当前同时经过三个数据源 Repository、Feed、Search、导航、收藏、历史和帖子详情分页。摘要进入详情页后，`ThreadDetailContentState` 会先构造不含正文的 placeholder，再由 `fetchThread` 返回的完整内容替换，并单独保存 `canonicalThread`。此前“列表摘要被当作主楼正文”的真实缺陷已经通过该边界和 `ForumPostDocument` 权威来源修复并覆盖测试。

拆分为 `ThreadSummary` 和 `ThreadDetail` 会同时修改 `ThreadRepository`、所有 Mapper、导航参数、详情加载入口、Mock/Fixture 以及收藏和历史恢复路径。目前没有离线详情缓存、摘要/详情独立持久化或仍无法由现有边界阻止的类型误用，因此缺少足以承担这次迁移成本的收益证据。

### Decision

当前不创建 `ThreadSummary` 或 `ThreadDetail` 新类型，继续使用 `ForumThread` 作为共享传输模型。列表摘要不得作为主楼正文、详情正文以 `ForumPostDocument` 为权威、身份判断显式使用 `source + id`，这些约束继续由现有状态边界和测试保证。

只有出现以下至少一种新证据时才重新评估：

- 引入需要独立 schema 和生命周期的离线详情缓存；
- 两个以上调用点再次发生摘要与详情形态误用，且现有接缝无法在编译期或测试中可靠阻止；
- Repository 需要分别暴露摘要流和可独立分页的详情聚合对象。

### Consequences

- 避免当前阶段横跨所有数据源、导航和持久化的大面积类型迁移
- 保留现有 Repository 和 Feature 接口，既有 Fixture 无需机械重写
- 摘要与详情的形态差异仍是运行期约束，后续必须维持 placeholder、内容权威来源和对应回归测试
- 若未来触发重新评估，应先选择单一数据源和单一详情入口做垂直试点

## ADR-013 Version User Content Separately From Authentication State

### Status

Accepted

### Date

2026-07

### Context

收藏、历史和屏蔽用户此前直接把 Codable 数组写入 UserDefaults，缺少显式 schema version；解码失败只能退回空状态，也无法区分旧裸数组和未来版本。频道订阅使用多组 property-list 键，已有来源迁移但没有统一版本标记和损坏键清洗。认证凭证则分别由 Keychain 和 Cookie Store 管理，生命周期与普通用户内容不同。

### Decision

收藏、历史和屏蔽用户使用包含 `version` 与 `payload` 的本地快照信封，当前版本为 1；读取时兼容旧裸数组并就地升级，损坏或不支持的快照安全降级为空状态。频道订阅保留现有多键格式，增加独立 schema version，并在恢复时丢弃未知来源或缺少 native key 的条目。

数据源选择和网页登录完成标记等单值 Settings 继续使用标量 UserDefaults，由枚举解析或默认值处理非法数据，不套用 JSON 信封。Token、Cookie、密码及账号会话不得进入用户内容快照，继续由 Session 层的 Keychain/Cookie 接缝管理。iCloud 同步边界由 ADR-015 定义。

### Consequences

- 旧收藏、历史和屏蔽数据首次读取后自动迁移，不更换存储键
- 损坏内容不会导致启动失败，也不会让更旧的屏蔽名单意外复活
- 每个持久化类别可以独立演进 schema，不把认证凭证混入通用迁移
- 未来增加版本时必须显式实现迁移，不能假定 Codable 自动兼容

## ADR-014 V2EX Uses Separate Token And Web Sessions

### Status

Accepted

### Date

2026-07

### Context

V2EX API v2 的 Personal Access Token 可读取账号和主题，但当前公开接口没有主题收藏列表及收藏增删能力。V2EX 网站提供账号收藏，不过操作依赖网页登录 Cookie，以及主题页面当次返回的 `once` 参数。此前项目已有 V2EX Web 登录 UI，但只保存一个完成标记，没有持久化、恢复或验证 Cookie，也没有连接收藏调用链。

### Decision

保留 Token 与 Web Cookie 两套相互隔离的会话：Token 只用于官方 `/api/v2/` 请求；Web Cookie 只用于 V2EX 原网页、`/my/topics` 和收藏操作。Web Cookie 仅收集 `v2ex.com` 域名，保存于独立 Keychain item，并在启动时恢复到 WebKit 与共享 HTTP Cookie Store。

收藏和取消收藏不硬编码 `once`。Repository 先加载当前主题页，从 HTML 中解析 `favorite` 或 `unfavorite` action，并验证 HTTPS、`www.v2ex.com`、目标 topic ID 和非空 `once` 后才请求。Action 响应成功后重新加载主题页确认最终状态，不依赖 action 响应正文包含主题操作控件。远端操作成功后再更新本地轻量收藏镜像。

### Consequences

- V2EX 站点账号成为收藏权威来源，换设备后可通过网站账号重新获取收藏列表
- API Token 不会发送到网页接口，Cookie 也不会进入 API Authorization
- 网页结构变化会使收藏操作明确失败，而不会回退为静默本地收藏
- Cookie 过期后需要重新完成 V2EX Web 登录
- 收藏动作依赖未承诺稳定的网页合约，需要 HTML Fixture、同源校验和真机回归保护

## ADR-015 iCloud KVS Syncs Blocked Users And iCloud Keychain Syncs Credentials

### Status

Accepted; supersedes ADR-004

### Date

2026-07

### Context

项目已使用付费开发者团队并具备 iCloud entitlement。收藏已明确由 NGA、V2EX 站点账号负责，不应再维护另一套跨设备收藏真相；需要跨设备同步的是屏蔽名单和账号凭证。屏蔽名单规模小且字段稳定，不需要引入 CloudKit 数据库。

### Decision

使用 `NSUbiquitousKeyValueStore` 同步按数据源隔离的屏蔽记录。每个用户记录使用独立 KVS key，保存最终屏蔽状态与更新时间；解除屏蔽保留墓碑，合并时按单记录 last-write-wins 处理。UserDefaults 保存同结构离线缓存。启动和首次同步通知只读取合并，不把整份本地快照回写云端；server change 可按单记录回写冲突赢家。Apple Account 切换时先丢弃旧账号本地缓存，再读取新账号数据。

NGA、V2EX 和 LINUX DO 的 Token/Cookie 使用 `kSecAttrSynchronizable=true` 的 iCloud Keychain item，并使用兼容同步的 `kSecAttrAccessibleAfterFirstUnlock`。写入使用 `SecItemUpdate`，仅在 item 不存在时 `SecItemAdd`，不得先删除有效凭证。App 启动和返回前台时会节流重读凭证，以覆盖同步项延迟到达。KVS 不保存任何 Token、Cookie、密码、历史或收藏数据。

App 内“退出登录”保证清除本机 WebKit/HTTP Cookie 和本地账号状态，并请求删除同步 Keychain 备份。它不等同于社区服务端的“退出所有设备”：其他设备已经持有的有效 Cookie 仍可能继续有效，只有社区提供并执行服务端会话撤销时才能保证全设备注销。

删除独立“本地收藏”产品入口。NGA 与 V2EX 的 `FavoriteThreadsStore` 仅作为当前 UI 星标缓存；没有远端收藏能力的数据源不显示收藏动作。

### Consequences

- 屏蔽名单能在同一 Apple Account 的设备间按记录合并，独立修改不会整包互相覆盖
- 用户关闭 iCloud 或 iCloud Keychain 时仍可使用本地缓存和本机现有会话，但不能保证跨设备同步
- 删除同步 Keychain 备份不保证撤销其他设备已存在的社区 Cookie 会话
- KVS 墓碑不自动删除，以避免长期离线设备复活旧屏蔽；同步记录达到 900 条安全上限后，新修改只保存在本机并显示错误
- 设备时间严重偏差可能影响同一用户记录的冲突结果
- 浏览历史、频道顺序和站点收藏不进入 iCloud KVS

## ADR-016 V2EX Threading Is An Explainable API-Derived Presentation

### Status

Accepted

### Date

2026-07

### Context

V2EX 回复 API 返回完整的线性回复，但没有服务端 `parentReplyID`。真实主题 `1227563` 和 V2EX Polish 的行为表明，回复正文中的 `@username` 与可选 `#floor` 可以恢复大部分对话分支；若在 `normalizedContent` 后由 View 猜测关系，引用证据会丢失且来源规则会泄漏到共享 UI。为此引入 Web 页面解析会增加 DOM、Cookie 和访问限制维护成本，但 API 原文已经包含所需证据。

### Decision

V2EX 适配层在正文标准化前提取引用证据，并按前序回复解析可解释的可选父链接：楼层和作者一致时为显式关系；单一用户名无楼层时连接最近的前序同名作者；楼层作者冲突时仅回退到最近同名作者并标记 resolution；多用户且没有唯一显式目标时保持根回复。

线性 `[Reply]`、稳定身份和完整 `ForumPostDocument` 继续作为权威数据。楼中楼 forest、最大三层视觉缩进及引用前缀省略都属于可丢弃的 presentation；前缀只有在精确对应已解析父节点时才从视觉投影省略，分享、快照、无障碍和平铺模式保留完整正文。只看楼主保持精确平铺过滤，倒序只反转根分组。关系发现只使用现有 V2EX API，不请求主题 Web HTML。

API `content_rendered` 由 V2EX 适配层映射为有序文本和图片语义块，避免在领域初始化时降级成 `[图片] URL` 普通文本；原始 `content` 仍单独用于关系证据提取。

### Consequences

- 手机端可追踪长对话，同时保留平铺回退，推断错误不会污染原始正文
- V2EX 特有提取规则停留在适配层，共享详情只消费可选关系与派生层级
- 回复关系是启发式结果而非服务端事实；删除楼层、歧义提及仍可能降级为根回复
- 新关系字段参与 `Reply` 内容相等，但所有既有构造器通过默认 `nil` 保持兼容
- 若未来 V2EX 提供稳定 parent ID，应以服务端关系取代推断 resolver，而不是叠加第二套合并规则

## ADR-017 Home Feed Uses Structured Time, Scoped Filters, And Typed Session Presentation

### Status

Accepted

### Date

2026-07

### Context

首页曾直接展示来源时间字符串，以布尔登录状态和分散按钮表达会话、子版与置顶。Unix 技术值会泄漏到 UI，普通网络失败难以与凭证失效区分，筛选扩展会持续增加顶部控件和独立请求。

### Decision

各 Adapter 在来源边界把创建时间和最后回复时间映射为可空结构化 `Date`，共享 Feed 只使用结构化值排序与格式化；旧字符串仅作为持久化迁移输入。会话描述增加 `checking / signedOut / authenticated / expired`，只有明确鉴权失效证据进入 `expired`。筛选以草稿 Sheet 一次性应用；排序与置顶按来源保存，子版选择按来源和父版保存并在恢复时清理失效 ID。

新主题入口通过 `ForumCapabilities.supportsCreateThread` 暴露。当前只启用已验证的 NGA 同会话 Web 入口；其他来源在目的地未验证前隐藏。登录前发帖以来源和频道绑定的 pending action 表达，成功后重新验证上下文才续接。

### Consequences

- 三个来源的 Feed 时间具有同一显示和排序语义，无法解析的旧值不会删除帖子或显示技术原文
- 普通 403、离线、超时和服务端故障不会误导用户重新登录
- 筛选可以扩展新条件而不继续增加首页独立按钮或每次编辑立即发请求
- Web 发帖入口仍依赖站点页面合约，需要真机会话回归；未验证来源不会展示无效按钮

## Template

Use this structure for future decisions:

```md
## ADR-XXX Title

### Status

Accepted | Proposed | Superseded

### Date

YYYY-MM

### Context

Why this decision was needed.

### Decision

What was chosen.

### Consequences

What this enables, costs, or constrains.
```
