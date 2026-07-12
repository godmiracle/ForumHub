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

## 4. 当前主要问题

### 4.1 领域模型职责过多

当前 `ForumThread` 同时承担：

- 信息流摘要；
- 详情正文；
- 分页结果；
- SwiftUI 列表身份；
- 导航参数；
- 收藏持久化；
- 浏览历史；
- API/Web 合并结果。

这使得一个对象在不同场景中不断被补全、替换和变形。

### 4.2 正文存在多份权威来源

当前可能同时存在：

```text
summary
body
contentDocument.rawMarkup
contentDocument.normalizedText
```

如果不同模块读取不同字段，就会出现：

- 某个页面已修复，另一个页面仍然错误；
- 分享内容和详情页不同；
- 缓存恢复后正文变化；
- 第一次打开不完整，第二次打开正常。

### 4.3 状态所有权不清晰

部分功能同时由以下对象写状态：

- SwiftUI View；
- ViewModel；
- Repository；
- 任务回调；
- 滚动监听；
- 图片和 GIF 组件。

这会导致状态时序冲突和难以复现的回归。

### 4.4 多数据源差异向上泄露

当 View 中出现大量：

```swift
if source == .nga
```

说明数据源差异已越过 Repository 边界。

### 4.5 内容处理是有损字符串管线

当前很多正文仍然经过：

```text
Raw Markup
→ structuredForumText
→ String
→ Parser
→ SwiftUI
```

复杂格式可能在进入 View 前已经丢失。

### 4.6 默认 UI Test 依赖真实网络

这会导致：

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

`body` 不再独立存储，只作为计算属性。

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

## 6. 推荐分层架构

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

---

## 8.3 列表模型

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

不再独立存储 `body`。

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

## 20. 推荐目录结构

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

## 阶段 0：建立护栏

先完成：

- `docs/testing.md`；
- `docs/regression-checklist.md`；
- `docs/debugging.md`；
- Mock UI Test 模式；
- URLProtocol Stub；
- Definition of Done。

---

## 阶段 1：统一身份

完成：

- `ForumThreadID`；
- `ForumReplyID`；
- 收藏、历史、导航、缓存统一使用组合 ID；
- 修复跨数据源相同 ID 冲突。

---

## 阶段 2：统一正文模型

完成：

- `ForumPostDocument` 成为唯一权威；
- 删除独立 `body` 存储；
- `ThreadSummary` 与 `ThreadDetail` 分离；
- API/Web 原始来源分别保留；
- 内容一致性测试。

---

## 阶段 3：重构帖子详情

完成：

- `ThreadDetailViewModel`；
- `ThreadDetailScrollCoordinator`；
- `ThreadDetailPaginationCoordinator`；
- `InlineMediaCoordinator`；
- 返回顶部 UI Test；
- 分页竞态测试。

---

## 阶段 4：内容管线

完成：

- NGA BBCode Parser；
- HTML Parser；
- ContentNode；
- 表格、代码块、链接；
- 真实黄金 Fixture。

---

## 阶段 5：网络与会话

完成：

- `HTTPClient`；
- Request Decorator；
- RetryPolicy；
- Session Registry；
- Header/Cookie 隔离测试。

---

## 阶段 6：图片与 GIF

完成：

- `ForumImageLoader`；
- NGA 图片装饰器；
- GIF 生命周期；
- 低电量策略；
- 性能基线与回归。

---

## 阶段 7：其他 Feature 迁移

顺序：

```text
Search
Feed
Account
Persistence
Community
History
Settings
```

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
- 有 Feature Flag 或启动参数；
- 有 Mock 场景；
- 有真机回归记录。

---

## 24. Definition of Done

一个功能或重构只有满足以下条件才能完成：

```text
代码修改完成
+ 单元测试通过
+ ViewModel 测试通过
+ 相关 UI Test 通过
+ 真机关键路径验证
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

- 组合身份；
- 正文唯一权威来源；
- Mock UI Test；
- 返回顶部回归测试；
- API/Web 合并一致性。

### P1

- ThreadDetail 状态拆分；
- 异步请求 generation；
- 网络 Header/Cookie 隔离；
- GIF 生命周期。

### P2

- 内容节点；
- HTML/BBCode Parser；
- 图片加载器统一；
- 持久化迁移。

### P3

- Feed、Search、Account 等其他模块迁移；
- 性能优化；
- 长期扩展能力。

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
