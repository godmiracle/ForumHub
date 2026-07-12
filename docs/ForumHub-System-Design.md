# ForumHub System Design

## 1. 文档目的

本文档用于定义 ForumHub 的长期系统架构、模块边界、领域模型、状态管理、内容处理、网络会话、媒体加载、持久化、测试和迁移策略。

目标不是一次性重写项目，而是在保留现有功能的基础上，通过渐进式迁移降低以下风险：

- 修改一个功能导致已有功能失效；
- 简单 Bug 反复修复失败；
- 多数据源逻辑泄露到 View；
- 状态所有权不清晰；
- 正文、分页、图片、GIF 和登录互相影响；
- 测试无法覆盖真实交互链路；
- 新旧模型并存造成双写和数据不一致。

### 1.1 文档状态

本文档是**演进式目标架构**，不是当前代码说明，也不是已经批准的重构任务清单。阅读时使用以下标记：

- **现状**：可由当前代码、测试或已接受 ADR 直接证明；
- **已决策**：已写入 `docs/decisions.md`，后续实现必须遵守；
- **目标**：推荐的长期方向，实施前仍需拆成独立待办；
- **提案**：示例接口或目录组织，尚未成为项目合约；
- **待验证**：需要真机、Fixture、性能数据或数据源合约确认。

本文档中的 Swift 类型和目录树，除非明确标记为“现状”，均为设计草图。新增公共协议、迁移持久化结构或移动目录前，必须先形成 ADR 或可验收待办。

### 1.2 总体判断

整体方向合理：共享领域边界、数据源适配、单一状态所有者、保留原始内容、固定 Mock 测试和渐进迁移均与现有项目原则一致。需要修正的不是方向，而是执行粒度：

1. 不能把逻辑分层直接等同于一次性目录重排；
2. 不能在缺少迁移收益和兼容方案时同时替换领域模型、Repository、网络层与持久化层；
3. 已落地能力应从迁移计划中移除，避免重复建设；
4. P0 应只保留会造成身份冲突、内容丢失或核心回归的事项；
5. 每个目标必须绑定触发条件、验收标准和回滚边界。

---

## 2. 项目目标

ForumHub 是一个支持多论坛数据源的原生客户端，当前支持或计划支持：

- NGA；
- V2EX；
- LINUX DO；
- 未来可扩展的其他论坛数据源。

核心能力包括：

- 首页与热门信息流；
- 社区与频道管理；
- 搜索；
- 帖子详情；
- 连续分页；
- 只看楼主；
- 正序与倒序；
- 收藏；
- 浏览历史；
- 屏蔽用户；
- 登录与会话恢复；
- 回复；
- 图片与 GIF；
- 图片预览和保存；
- 长图分享；
- 本地持久化；
- 自动化测试与真实接口测试。

---

## 3. 非目标

以下事项不作为本轮架构设计的直接目标：

- 一次性重写整个项目；
- 为所有数据源强行实现完全一致的功能；
- 在 View 中处理数据源差异；
- 依赖真实网络运行默认 UI Test；
- 为了抽象而抽象；
- 在没有回归测试保护的情况下进行大范围重构；
- 同时重构多个高风险模块。

---

## 4. 当前主要问题与证据状态

### 4.1 `ForumThread` 承担摘要与详情两种形态（已确认）

当前 `ForumThread` 同时承担：

- 信息流摘要；
- 详情正文；
- 分页结果；
- SwiftUI 列表身份；
- 导航参数；
- 收藏持久化；
- 浏览历史；
- API/Web 合并结果。

这使得一个对象在不同场景中不断被补全、替换和变形。当前通过完整字段 `Equatable` 和详情加载后的模型替换保证 Observation 正确更新；这是有效护栏，但没有消除模型形态混用。是否拆成 `ThreadSummary` 与 `ThreadDetail`，需要先评估导航、收藏、历史、分页和 Fixture 的迁移成本。

### 4.2 `body` 与 `contentDocument` 并存（已确认，已有约束）

当前可能同时存在：

```text
summary
body
contentDocument.rawMarkup
contentDocument.normalizedText
```

当前 ADR-010 已明确 `ForumPostDocument` 中的原始标记是内容权威，`body` 是兼容性投影；`summary` 只能用于信息流，不得在详情加载前充当主楼。如果不同模块读取不同字段，就会出现：

- 某个页面已修复，另一个页面仍然错误；
- 分享内容和详情页不同；
- 缓存恢复后正文变化；
- 第一次打开不完整，第二次打开正常。

### 4.3 帖子详情状态已部分收口，滚动与媒体仍待治理（已确认）

详情加载、分页、回复和收藏已经迁移到 `ThreadDetailViewModel` 及其子状态对象。仍需重点检查以下跨组件状态：

- SwiftUI View；
- ViewModel；
- Repository；
- 任务回调；
- 滚动监听；
- 图片和 GIF 组件。

这会导致状态时序冲突和难以复现的回归。

### 4.4 多数据源差异仍有少量向上泄露（已确认）

当 View 中出现大量：

```swift
if source == .nga
```

说明数据源差异已越过 Repository 边界。分页和图片上传入口已经使用 `ForumCapabilities`；但认证等流程仍存在 `repository.source == .nga` 分支。是否消除这些分支，应先确认共享认证描述能表达来源特有前置条件，不能为了形式统一而隐藏真实差异。

### 4.5 内容处理仍包含有损投影（已确认，原始文档已保留）

当前很多正文仍然经过：

```text
Raw Markup
→ structuredForumText
→ String
→ Parser
→ SwiftUI
```

复杂格式在原生投影中仍可能丢失，但原始 `ForumPostDocument` 已保留，因此可以渐进增强解析器，不需要重新抓取内容。

### 4.6 Mock UI Test 治理尚未完全收口（高概率）

项目已经具备固定 UI Test 场景，相关搜索、切换和分页路径已有真机验证；`T-008` 尚未全部验收。未确认所有默认 UI Test 都依赖真实网络，因此本节只保留为待收口风险：

- 测试长时间停在加载；
- 登录状态不稳定；
- 接口限流；
- 数据内容不可预测；
- 测试难以重复。

---

## 5. 架构原则

### 5.1 单一状态所有者

一个业务状态只能有一个主要写入者。

例如：

```text
当前页码
→ ThreadDetailPaginationState

返回顶部按钮
→ ThreadDetailScrollState

GIF 播放集合
→ InlineMediaCoordinator

帖子数据
→ ThreadDetailViewModel
```

### 5.2 数据源差异必须留在 Data 层

View 不应知道：

- NGA 的 Cookie；
- V2EX 的 Token；
- LINUX DO 的 HTML 结构；
- 某数据源页大小；
- 某数据源的图片 Referer。

### 5.3 领域模型不依赖 UI 和网络细节

Domain 层不应依赖：

- SwiftUI；
- UIKit；
- URLSession；
- WKWebView；
- UserDefaults；
- Keychain。

### 5.4 内容只能有一个权威来源

帖子正文的权威来源为：

```text
ForumPostDocument
```

`body` 和 `normalizedText` 只能是从权威文档派生的兼容投影，不能反向覆盖原始标记。目标态可以把 `body` 改为计算属性，但删除现有存储字段属于独立迁移，不是本原则立即要求的代码变更。

### 5.5 Bug 修复必须可回归

每个已确认 Bug：

- 有固定复现步骤；
- 有自动化测试或人工回归项；
- 修复后不能仅依赖“看起来正常”。

### 5.6 渐进迁移，不一次性重写

采用 Strangler Pattern：

```text
旧模块继续工作
→ 新模块接管一部分能力
→ 验证稳定
→ 删除旧逻辑
```

---

## 6. 推荐逻辑分层架构（目标）

这些是**职责边界**，不要求立即创建同名目录。当前 `Features` 可以同时承载 Presentation 和 feature-local Application 代码；只有当共享 Use Case、Policy 或 Infrastructure 出现至少两个稳定消费者时，才考虑上移为独立目录。

```text
ForumHub
├── App
│   ├── AppEntry
│   ├── DependencyContainer
│   ├── Navigation
│   └── FeatureRegistry
├── Presentation
│   ├── Feed
│   ├── Search
│   ├── ThreadDetail
│   ├── Community
│   ├── Account
│   ├── History
│   └── Settings
├── Application
│   ├── UseCases
│   ├── ViewModels
│   ├── FeatureStates
│   ├── Coordinators
│   └── Policies
├── Domain
│   ├── Identity
│   ├── Thread
│   ├── Content
│   ├── Account
│   ├── Repository
│   ├── Capability
│   └── Error
├── Data
│   ├── NGA
│   ├── V2EX
│   ├── LinuxDo
│   ├── Mock
│   ├── Cache
│   └── Persistence
└── Infrastructure
    ├── Networking
    ├── Authentication
    ├── Image
    ├── Web
    ├── Logging
    ├── Diagnostics
    └── TestingSupport
```

---

## 7. 各层职责

## 7.1 App 层

负责：

- App 启动；
- 依赖注入；
- 顶层导航；
- Feature 注册；
- UI Test 场景注入；
- 生命周期分发。

不负责：

- 业务逻辑；
- 数据解析；
- 网络请求；
- 持久化细节。

---

## 7.2 Presentation 层

负责：

- SwiftUI 页面；
- 用户交互；
- 状态展示；
- 事件转发；
- Accessibility Identifier；
- Loading、Empty、Error、Content 四类页面状态。

不负责：

- 直接访问 Repository；
- 解析 JSON/HTML/BBCode；
- 维护网络任务；
- 拼接 Cookie/Header；
- 多数据源分支。

推荐 Feature 结构：

```text
Features/ThreadDetail/
├── ThreadDetailView.swift
├── ThreadDetailScreenState.swift
├── ThreadDetailAction.swift
├── ThreadDetailComponents/
└── ThreadDetailAccessibility.swift
```

---

## 7.3 Application 层

负责：

- ViewModel；
- Use Case；
- 状态机；
- 异步任务；
- generation；
- 请求取消；
- 跨 Repository 流程；
- UI 需要的业务策略。

例如：

```text
LoadThreadDetailUseCase
SearchThreadsUseCase
LoadNextThreadPageUseCase
RestoreForumSessionUseCase
ToggleFavoriteUseCase
```

---

## 7.4 Domain 层

负责：

- 领域模型；
- 业务身份；
- Repository Protocol；
- ForumCapabilities；
- 领域错误；
- 内容节点；
- 业务规则。

Domain 不依赖具体数据源实现。

---

## 7.5 Data 层

负责：

- NGA/V2EX/LINUX DO Adapter；
- DTO；
- Parser；
- Mapper；
- Repository 实现；
- API/Web 合并；
- 数据源专属认证；
- 数据源专属分页；
- 数据源专属图片请求策略。

---

## 7.6 Infrastructure 层

负责：

- HTTP Client；
- Cookie Store；
- Keychain；
- WebKit；
- 图片缓存；
- GIF 解码；
- 日志；
- Metrics；
- URLProtocol Stub；
- 测试工具。

---

## 8. 领域模型设计

本章是目标模型草图。当前代码仍以 `ForumThread`、`Reply`、`ForumPostDocument` 和 `ThreadRepository` 为主。迁移必须通过适配器逐个调用点完成，禁止长期双写两套持久化模型。

## 8.1 论坛来源

```swift
enum ForumSource: String, Codable, CaseIterable, Sendable {
    case nga
    case v2ex
    case linuxDo
}
```

---

## 8.2 组合身份

所有跨数据源对象必须使用组合身份。

```swift
struct ForumThreadID: Hashable, Codable, Sendable {
    let source: ForumSource
    let nativeID: String
}

struct ForumReplyID: Hashable, Codable, Sendable {
    let threadID: ForumThreadID
    let nativeID: String
}
```

禁止仅使用整数 ID 作为全局身份。

**现状说明**：当前模型仍使用 `Int` 原生 ID，并在收藏、历史、去重和导航等调用点显式组合 `source + id`，符合 ADR-011。引入值类型 ID 的收益主要是编译期防错，不是修复当前已确认的数据冲突。实施前应盘点编码、导航和持久化兼容面，并提供旧数据迁移。

---

## 8.3 列表模型

**提案**：只有在摘要/详情误用仍持续产生缺陷，或新增缓存层需要明确载荷边界时才拆分该类型。

```swift
struct ThreadSummary: Identifiable, Equatable, Sendable {
    let id: ForumThreadID
    let title: String
    let summary: String
    let author: ForumUserSummary
    let createdAt: ForumDateValue?
    let lastReplyAt: ForumDateValue?
    let replyCount: Int
    let viewCount: Int
    let channel: ForumChannelSummary?
}
```

`ThreadSummary` 不包含：

- 完整正文；
- 完整回复列表；
- HTML/BBCode 原文；
- 图片解码结果；
- 详情分页状态。

---

## 8.4 详情模型

**提案**：详情分页结果与聚合后的可展示详情应保持概念区分；不要默认把所有页的回复永久塞入一个可持久化实体。

```swift
struct ThreadDetail: Identifiable, Equatable, Sendable {
    let id: ForumThreadID
    let title: String
    let author: ForumUserSummary
    let createdAt: ForumDateValue?
    let content: ForumPostDocument
    let replies: [ForumReply]
    let metadata: ThreadMetadata
}
```

---

## 8.5 回复模型

```swift
struct ForumReply: Identifiable, Equatable, Sendable {
    let id: ForumReplyID
    let sourcePostID: String?
    let floorNumber: Int?
    let author: ForumUserSummary
    let createdAt: ForumDateValue?
    let content: ForumPostDocument
}
```

目标态不再独立存储 `body`。迁移期允许保留只读兼容投影；删除存储字段前必须覆盖分享、截图、回复引用、收藏和历史恢复路径。

```swift
extension ForumReply {
    var body: String {
        content.normalizedText
    }
}
```

---

## 8.6 正文模型

```swift
struct ForumPostDocument: Equatable, Sendable {
    let sources: [ForumPostSourceDocument]
    let blocks: [ForumContentNode]
    let normalizedText: String
    let revision: ContentRevision
}
```

```swift
struct ForumPostSourceDocument: Equatable, Sendable {
    let sourceType: SourceDocumentType
    let rawMarkup: String
    let markupFormat: MarkupFormat
    let sourceURL: URL?
}
```

```swift
enum SourceDocumentType: Equatable, Sendable {
    case api
    case web
    case cache
    case userGenerated
}
```

```swift
enum MarkupFormat: Equatable, Sendable {
    case plainText
    case ngaBBCode
    case html
    case markdown
}
```

---

## 8.7 内容节点

```swift
enum ForumContentNode: Identifiable, Equatable, Sendable {
    case paragraph(ContentNodeID, AttributedString)
    case image(ContentNodeID, ForumImageReference)
    case animatedImage(ContentNodeID, ForumImageReference)
    case emoji(ContentNodeID, ForumEmoji)
    case quote(ContentNodeID, ForumQuote)
    case code(ContentNodeID, ForumCodeBlock)
    case list(ContentNodeID, [ForumContentNode])
    case table(ContentNodeID, ForumTable)
    case link(ContentNodeID, ForumLink)
    case divider(ContentNodeID)
}
```

View 只渲染节点，不再解析原始字符串。

---

## 9. Repository 设计

本章是下一代接口提案，不代表当前 `ThreadRepository` 合约。当前接口使用 `Int` 帖子 ID 和数字页码，并包含各数据源不一定支持的操作；Capabilities 已承担运行时能力表达。

## 9.1 基础协议

```swift
protocol ForumRepository: Sendable {
    var source: ForumSource { get }
    var capabilities: ForumCapabilities { get }

    func fetchFeed(
        channel: ForumChannelID,
        cursor: FeedCursor?
    ) async throws -> FeedPage

    func fetchThread(
        id: ForumThreadID,
        page: ThreadPageRequest
    ) async throws -> ThreadPage

    func search(
        query: String,
        cursor: SearchCursor?
    ) async throws -> SearchPage
}
```

采用该协议前必须先解决：

- `ForumChannelID` 如何表达 NGA 数字版块与 LINUX DO slug/ID；
- cursor 与数字页码的可恢复、可比较语义；
- 热榜、收藏列表是否属于统一 feed request，而不是继续扩充基础协议；
- 旧 `ThreadRepository` 到新协议的单向适配，避免所有数据源同时重写。

---

## 9.2 可选能力协议

不要让基础协议塞满所有数据源都不支持的方法。

```swift
protocol ForumAuthenticationRepository {
    func restoreSession() async throws -> ForumSession
    func logout() async throws
}

protocol ForumReplyRepository {
    func reply(
        to target: ThreadReplyTarget,
        content: ReplyDraft
    ) async throws -> ReplyResult
}

protocol ForumFavoriteRepository {
    func addFavorite(threadID: ForumThreadID) async throws
    func removeFavorite(threadID: ForumThreadID) async throws
}
```

---

## 9.3 Capabilities

```swift
struct ForumCapabilities: Equatable, Sendable {
    let supportsSearch: Bool
    let supportsFavorites: Bool
    let supportsReply: Bool
    let supportsReplyTargeting: Bool
    let supportsAuthentication: Bool
    let supportsFeedPagination: Bool
    let supportsImageUpload: Bool
    let supportsWebFallback: Bool
    let threadPaginationStyle: ThreadPaginationStyle
}
```

View 根据能力决定是否显示入口，不根据 `source` 分支。

---

## 10. 状态管理设计

**现状**：`ThreadDetailViewModel` 已拥有内容加载、分页、回复和收藏任务；`ThreadDetailContentState`、`ThreadDetailPaginationState` 与 `ThreadDetailActionState` 已存在。以下 reducer 风格 `Action` 入口是提案，不应为了形式统一重写已经稳定的直接方法调用。

## 10.1 Feature State

每个 Feature 有一个主状态对象。

例如帖子详情：

```swift
struct ThreadDetailState: Equatable {
    var phase: LoadPhase<ThreadDetail>
    var pagination: ThreadPaginationState
    var filter: ThreadFilterState
    var actions: ThreadActionState
    var scroll: ThreadScrollSnapshot
    var media: ThreadMediaSnapshot
}
```

---

## 10.2 Action

```swift
enum ThreadDetailAction {
    case appeared
    case refresh
    case loadNextPage
    case selectPage(Int)
    case toggleOnlyAuthor
    case toggleReverse
    case scrollToTop
    case retry
    case favorite
    case reply(ThreadReplyTarget)
}
```

View 只发送 Action。

---

## 10.3 ViewModel

```swift
@MainActor
@Observable
final class ThreadDetailViewModel {
    private(set) var state: ThreadDetailState

    private let loadThreadDetail: LoadThreadDetailUseCase
    private let loadNextPage: LoadNextThreadPageUseCase
    private let generation = RequestGeneration()

    func send(_ action: ThreadDetailAction) {
        // 统一处理事件
    }
}
```

---

## 10.4 派生状态

以下状态不允许多个入口手动修改：

```text
visiblePage
showsScrollToTopButton
canLoadMore
isLoadingMore
activeGIFIDs
```

它们必须由单一输入推导。

---

## 11. 帖子详情模块设计

```text
ThreadDetail
├── ThreadDetailView
├── ThreadDetailViewModel
├── ThreadDetailState
├── ThreadDetailAction
├── ThreadDetailScrollCoordinator
├── ThreadDetailPaginationCoordinator
├── InlineMediaCoordinator
├── ThreadDetailRenderer
└── ThreadDetailSnapshotService
```

### 11.1 ViewModel 负责

- 首次加载；
- 刷新；
- 页码跳转；
- 连续分页；
- 请求取消；
- 只看楼主；
- 正倒序；
- 收藏；
- 回复；
- 错误恢复。

### 11.2 Scroll Coordinator 负责

- 当前滚动偏移；
- 顶部锚点；
- 当前可见页；
- 返回顶部按钮；
- 保持阅读位置。

### 11.3 Pagination Coordinator 负责

- 已加载页；
- 当前页；
- 是否还有下一页；
- 页面合并；
- 自动加载策略。

### 11.4 Inline Media Coordinator 负责

- GIF 候选节点；
- 同时播放数量；
- 离屏停止；
- 高速滚动暂停；
- 后台停止；
- 低电量模式。

---

## 12. 内容处理管线

```text
Raw Response
→ Source DTO
→ Source Document
→ Parser
→ Content Node Tree
→ Normalizer
→ Merge
→ Render Model
→ SwiftUI
```

---

## 12.1 NGA

```text
API JSON
→ NGAThreadDTO
→ NGA BBCode Document
→ NGAContentParser
```

```text
Web HTML
→ NGAWebDocument
→ HTML DOM Parser
→ HTMLContentParser
```

合并优先级：

```text
1. API 提供身份、PID、作者、楼层、顺序
2. Web 提供正文补全
3. 回复优先按 PID 匹配
4. PID 缺失时按楼层
5. 不可靠时不合并
```

---

## 12.2 V2EX

```text
V2 API / HTML
→ V2EX DTO
→ HTML/Markdown Document
→ Content Parser
```

---

## 12.3 LINUX DO

```text
JSON / HTML
→ LinuxDo DTO
→ HTML Document
→ Content Parser
```

---

## 12.4 内容合并

禁止：

```text
rawMarkup = Web
normalizedText = API + Web
markupFormat = HTML
```

推荐：

```swift
struct MergedForumPostDocument {
    let primary: ForumPostSourceDocument
    let supplements: [ForumPostSourceDocument]
    let blocks: [ForumContentNode]
}
```

合并后直接生成节点树，而不是伪造新的单一原文。

---

## 13. 网络设计

## 13.1 HTTP Client

```swift
protocol HTTPClient: Sendable {
    func send<Response: Decodable>(
        _ request: HTTPRequest<Response>
    ) async throws -> Response
}
```

---

## 13.2 Request Decorator

```swift
protocol RequestDecorator: Sendable {
    func decorate(_ request: URLRequest) async throws -> URLRequest
}
```

实现：

```text
NGARequestDecorator
V2EXRequestDecorator
LinuxDoRequestDecorator
GenericRequestDecorator
```

---

## 13.3 Cookie 与 Token

```text
NGA
→ Cookie Session

V2EX
→ API Token + Optional Web Cookie

LINUX DO
→ Web Cookie / Session
```

会话存储由专属 Session Store 管理，不能由 View 直接访问。

---

## 13.4 错误映射

所有底层错误统一转为：

```swift
enum ForumError: Error, Equatable {
    case offline
    case timeout
    case authenticationExpired
    case rateLimited
    case forbidden
    case notFound
    case malformedResponse
    case unsupportedContent
    case serverUnavailable
    case unknown
}
```

View 不显示底层 URLSession 或 Parser 错误。

---

## 13.5 重试策略

自动重试：

```text
timeout
connection lost
temporary DNS
5xx
```

不自动重试：

```text
401
403
404
invalid request
unsupported format
```

重试必须由统一 `RetryPolicy` 管理。

---

## 14. 图片与媒体设计

## 14.1 通用图片加载器

```text
ForumImageLoader
├── RequestBuilder
├── Cache
├── Decoder
├── AnimatedImageDecoder
└── DomainDecorator
```

NGA 特殊 Header 只由 `NGAImageRequestDecorator` 添加。

---

## 14.2 图片引用

```swift
struct ForumImageReference: Equatable, Sendable {
    let url: URL
    let source: ForumSource
    let kind: ForumImageKind
    let expectedSize: CGSize?
}
```

---

## 14.3 GIF 策略

支持：

```text
始终播放
仅 Wi-Fi
点击播放
从不自动播放
```

播放约束：

- 同时播放数量；
- 离屏停止；
- 高速滚动暂停；
- 后台停止；
- 低电量限制；
- 超大 GIF 首帧模式；
- 内存警告释放帧缓存。

---

## 15. 持久化设计

## 15.1 存储边界

```text
FavoritesStore
HistoryStore
BlockedUsersStore
ChannelSubscriptionStore
ReadingPositionStore
SettingsStore
SessionStore
```

不要让多个模块直接读写 `UserDefaults.standard`。

---

## 15.2 数据版本

```swift
struct PersistedSchemaVersion: Codable {
    let version: Int
}
```

每个 Store 必须支持：

- schema version；
- migration；
- 数据损坏降级；
- source + nativeID 组合身份。

---

## 15.3 阅读位置

```swift
struct ThreadReadingPosition: Codable {
    let threadID: ForumThreadID
    let page: Int?
    let anchorID: String?
    let offset: Double?
    let filter: ThreadFilterSnapshot
}
```

---

## 16. 导航设计

导航参数只使用轻量身份，不传完整模型。

```swift
enum AppRoute: Hashable {
    case thread(ForumThreadID)
    case search(String)
    case account(ForumSource)
    case community(ForumSource)
}
```

禁止通过导航长期持有完整 `ForumThread`。

---

## 17. 测试策略

## 17.1 单元测试

覆盖：

- Parser；
- Mapper；
- 内容节点；
- 分页合并；
- Identity；
- Error；
- RetryPolicy；
- 持久化；
- GIF 调度策略。

---

## 17.2 ViewModel 测试

覆盖：

- generation；
- 任务取消；
- 旧响应丢弃；
- 搜索连续提交；
- 数据源快速切换；
- 详情刷新与分页竞争；
- 页面退出取消任务。

---

## 17.3 Repository Stub 测试

使用 `URLProtocol` Stub 控制：

- URL；
- Header；
- Cookie；
- 状态码；
- 响应体；
- 延迟；
- 超时；
- 响应顺序。

---

## 17.4 Mock UI Test

默认 UI Test 必须使用固定场景：

```swift
enum UITestScenario {
    case defaultFeed
    case search
    case sourceSwitch
    case pagedThread
    case scrollToTop
    case mediaHeavyThread
    case loadingError
}
```

不依赖：

- 真实网络；
- 真实 Cookie；
- 真实 Token；
- 服务端当前数据。

---

## 17.5 真实接口测试

手动运行，只读为主：

- 首页；
- 详情；
- 图片；
- GIF；
- 登录恢复；
- 搜索；
- 分页。

不自动：

- 回复；
- 登出；
- 删除收藏；
- 修改订阅。

---

## 17.6 性能测试

固定设备、帖子和操作路径，记录：

- CPU；
- 内存；
- 帧率；
- 启动耗时；
- 首屏详情耗时；
- GIF 能耗；
- 长图生成耗时。

---

## 18. 日志与诊断

## 18.1 结构化日志分类

```text
network
session
feed
search
thread-detail
pagination
scroll
media
persistence
```

---

## 18.2 请求日志

记录：

- request ID；
- generation；
- source；
- endpoint；
- start/end；
- canceled；
- discarded；
- retry count。

不记录：

- Token；
- Cookie；
- 用户密码；
- 完整敏感正文。

---

## 18.3 内容诊断

Debug 模式记录：

```text
API 正文长度
Web 正文长度
内容节点数量
图片数量
合并来源
PID 匹配数
楼层降级匹配数
无法匹配数
```

---

## 19. 依赖注入

这是目标边界。当前依赖主要在 `ForumViewModel` 等入口组装；只有当测试替换、生命周期或跨 Feature 共享依赖持续受阻时，才引入容器。容器不得演变为 Service Locator，也不得让 Feature 隐式获取任意依赖。

```swift
@MainActor
final class AppDependencyContainer {
    let repositoryRegistry: ForumRepositoryRegistry
    let sessionRegistry: ForumSessionRegistry
    let imageLoader: ForumImageLoader
    let persistence: ForumPersistenceContainer
    let logger: ForumLogger
}
```

View 不直接创建 Repository。

---

## 20. 推荐目录结构（参考，不作为迁移任务）

目录应跟随稳定边界演进，而不是先移动文件再寻找职责。短期继续保留现有 `Data`、`Domain`、`Features`、`Session`、`DesignSystem` 与 `Sync` 顶层结构；新增目录需有真实消费者和独立测试价值。

```text
ForumHub/
├── App/
├── Domain/
│   ├── Identity/
│   ├── Thread/
│   ├── Content/
│   ├── Account/
│   ├── Repository/
│   ├── Capability/
│   └── Error/
├── Application/
│   ├── UseCases/
│   ├── ViewModels/
│   ├── States/
│   ├── Coordinators/
│   └── Policies/
├── Data/
│   ├── NGA/
│   │   ├── API/
│   │   ├── Web/
│   │   ├── DTO/
│   │   ├── Parser/
│   │   ├── Mapper/
│   │   └── Repository/
│   ├── V2EX/
│   ├── LinuxDo/
│   ├── Mock/
│   ├── Cache/
│   └── Persistence/
├── Infrastructure/
│   ├── Networking/
│   ├── Authentication/
│   ├── Image/
│   ├── Web/
│   ├── Logging/
│   └── TestingSupport/
└── Features/
    ├── Feed/
    ├── Search/
    ├── ThreadDetail/
    ├── Community/
    ├── Account/
    ├── History/
    └── Settings/
```

---

## 21. 迁移计划

迁移不再按“先重写基础层、再迁移所有 Feature”的固定瀑布顺序执行，而采用垂直切片：每次选择一个已确认缺陷或明确扩展需求，从模型、适配、状态到测试完成一个最小闭环。以下阶段表示依赖关系，不表示必须全部实施。

### 阶段 0：补齐剩余护栏（进行中）

先完成：

- 完成 `T-008` 的固定 UI Test 场景治理；
- 为当前高风险 NGA API/Web 合并、分页和媒体链路补齐 Fixture；
- 建立可重复的 GIF 密集帖性能基线；
- 保持真机构建、相关测试和回归记录。

---

### 阶段 1：身份值类型可行性验证（条件触发）

完成：

- 先证明现有显式 `source + id` 身份键仍存在遗漏或维护成本；
- 设计 `ForumThreadID`、`ForumReplyID` 的 Codable 兼容与旧数据迁移；
- 选择收藏或历史作为单一试点，不同时迁移全部调用点；
- 验证跨数据源同 ID 不冲突、旧数据不丢失后再扩大范围。

---

### 阶段 2：收敛正文兼容投影（进行中）

完成：

- 保持 ADR-010：`ForumPostDocument` 原始标记为权威；
- 搜索 `body`、`summary` 的读取点并区分兼容投影与错误使用；
- 先让分享、截图、回复引用和渲染从文档派生，再考虑删除 `body` 存储；
- `ThreadSummary` 与 `ThreadDetail` 拆分单独决策，不与删除 `body` 捆绑；
- 继续补充 API/Web 合并和内容一致性测试。

---

### 阶段 3：完成帖子详情剩余状态治理（进行中）

完成：

- 保留已经完成的 `ThreadDetailViewModel`、分页 capability、请求代次和返回顶部回归；
- 评估是否需要独立 `ThreadDetailScrollState`，以真实缺陷和测试收益为准；
- 收敛 GIF 播放所有权和状态传播范围；
- 不引入与现有 `ThreadDetailPaginationState` 职责重复的 Coordinator。

---

### 阶段 4：按真实内容缺口扩展节点

完成：

- 以真实 Fixture 证明缺失格式；
- 优先扩展现有 `ForumContentBlock`/Parser，不先替换整棵节点模型；
- 表格、代码块、链接逐类增加解析、降级和渲染测试；
- 未识别标记必须保留在原始文档中，并提供可理解的文本降级。

---

### 阶段 5：网络与会话共享接缝（条件触发）

完成：

- 先复用已存在的 Session Registry、错误映射与 NGA 图片 Header 隔离；
- 只有两个以上数据源出现相同请求生命周期或重试逻辑时，抽取 `HTTPClient`/`RetryPolicy`；
- 401/403 不做无条件自动重试，WebKit challenge 等来源特例由适配层显式处理；
- 新接缝必须保持 Cookie、Token 和敏感日志隔离。

---

### 阶段 6：图片与 GIF（高优先级性能切片）

完成：

- 先建立固定真机、固定帖子和固定操作路径的性能基线；
- 保留已经存在的共享图片管线和 NGA 请求隔离；
- 实现活动 GIF 上限、离屏/后台停止、内存警告释放和首帧降级；
- 只有对比数据更优时才替换 GIF 解码或播放方案。

---

### 阶段 7：其他 Feature 按缺陷迁移

不预设全局迁移顺序。Search、Feed、Account、Persistence、Community、History、Settings 仅在出现已确认缺陷、共享能力需求或测试阻塞时迁移；每次只处理一个垂直切片。

---

## 22. 每次迁移的执行规则

每个迁移项必须：

1. 固定当前行为；
2. 补充测试；
3. 新增新实现；
4. 新旧实现短期并行；
5. 通过回归；
6. 删除旧实现；
7. 更新文档；
8. 单独提交。

禁止：

- 同时修改多个核心模块；
- Bug 修复与大重构混合；
- 未验证就删除旧实现；
- 新旧模型长期双写。

---

## 23. 风险与回滚

每个核心迁移必须：

- 独立 commit；
- 可单独回退；
- 保留旧路径直到新路径验证完成；
- 高风险或需要新旧路径并行时有 Feature Flag 或启动参数；
- 有 Mock 场景；
- 有真机回归记录。

低风险的内部重命名或纯文档调整不强制引入 Feature Flag。禁止为满足形式要求而长期保留两套生产路径。

---

## 24. Definition of Done

一个功能或重构只有满足以下条件才能完成：

```text
代码修改完成
+ 与风险匹配的单元测试通过
+ 涉及状态时 ViewModel 测试通过
+ 涉及交互时相关 UI Test 或人工回归通过
+ 涉及真机差异时真机关键路径验证
+ 无新增警告
+ git diff 无无关修改
+ Todo 已更新
+ 文档已同步
```

无法验证时：

```text
状态：已修改，等待验证
```

不得勾选完成。

---

## 25. 当前优先级

### P0

- 完成 NGA API/Web 内容合并的真实帖子验证与剩余 Fixture；
- 修复任何仍会把 `summary` 当主楼或丢失原始 `ForumPostDocument` 的路径；
- 保持已完成的请求代次、返回顶部和分页回归测试不退化。

### P1

- 完成 `T-008` Mock UI Test 场景治理；
- 建立 GIF 性能基线并治理播放生命周期；
- 完成 NGA 图片 Header/Cookie 与非 NGA 请求的剩余隔离验证；
- 收敛详情滚动与媒体状态所有权。

### P2

- 按真实 Fixture 扩展 HTML/BBCode 内容节点；
- 为持久化增加版本、损坏降级和迁移测试；
- 评估 `ThreadSummary`/`ThreadDetail` 分离和组合 ID 值类型，未证明收益前不实施。

### P3

- 仅在出现真实复用需求时抽取通用 `HTTPClient`、Use Case 和依赖容器；
- Feed、Search、Account 等模块按具体缺陷演进；
- 目录重排和命名统一。

---

## 26. 最终架构目标

最终 ForumHub 应满足：

```text
View 不解析数据
View 不直接请求网络
View 不判断具体数据源
正文只有一个权威来源
每个状态只有一个主要所有者
所有跨数据源身份都包含 source
所有默认 UI Test 使用固定 Mock
所有真实网络测试独立运行
每个已出现 Bug 都有回归保护
```

这套设计的目标不是让代码“看起来更复杂”，而是让后续开发具备以下能力：

- 修改影响范围可预测；
- Bug 可复现；
- 修复可验证；
- 数据源可扩展；
- 新旧功能不会互相破坏；
- AI 和人工开发都能遵循相同边界。
