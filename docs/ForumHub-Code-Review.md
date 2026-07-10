# ForumHub 整体 Code Review

> 仓库：`godmiracle/ForumHub`  
> 技术栈：SwiftUI / iOS  
> 评审范围：项目结构、架构设计、帖子详情、异步任务、分页、性能、设计系统、持久化、安全、测试与工程配置

## 一、整体结论

ForumHub 的整体方向是正确的，目前已经形成：

```text
Data Adapter
    ↓
Domain Model
    ↓
Feature
    ↓
SwiftUI View
```

项目已经具备以下较好的基础：

- 多论坛源统一接入；
- Data、Domain、Feature、Session、DesignSystem 分层；
- Repository Adapter 模式；
- 登录凭证与普通业务数据分离存储；
- 已建立 Unit Test 与 UI Test Target；
- 已具备较完整的产品和架构文档。

相比普通个人 SwiftUI 项目，ForumHub 并不是一个将所有逻辑堆在页面中的简单原型，而是已经具备继续长期维护和扩展的基础。

当前最明显的问题是：

> 文档中的架构比部分实际代码更加干净，复杂业务逻辑正在重新回流到 SwiftUI View。

其中最突出的模块是：

```text
ForumHub/Features/ThreadDetail/ThreadDetailView.swift
```

该文件已经达到约 1700 行，同时承担：

- 页面渲染；
- 帖子加载；
- 分页状态；
- 自动预加载；
- 手动跳页；
- GIF 播放调度；
- 收藏；
- 回复；
- 长图生成；
- 楼层计算；
- 滚动跟踪；
- 错误提示。

这已经成为当前项目中最高优先级的维护风险。

### 综合评价

| 项目 | 评价 |
| --- | --- |
| 架构方向 | 8/10 |
| 功能完整度 | 7.5/10 |
| 可维护性 | 5.5/10 |
| 测试保障 | 4/10 |
| 上架前成熟度 | 6/10 |

本次 Review 主要基于仓库结构、工程配置、架构文档以及帖子详情核心实现。尚未进行完整的本地 Xcode 编译、真机运行与 Instruments 性能测试，因此涉及实际内存峰值、帧率和编译警告的问题，仍应以真机结果为准。

---

## 二、最高优先级问题

## P0：`ThreadDetailView` 职责严重超载

当前页面顶部存在超过 30 个 `@State`，包含：

- 加载状态；
- 分页状态；
- 长图生成状态；
- 回复状态；
- 滚动状态；
- GIF 播放状态；
- 收藏状态；
- 错误信息；
- 页面选择状态。

这会产生以下实际问题：

1. 任意状态变化都可能触发整个 View 的重新计算；
2. 很难判断哪些状态必须同步变化；
3. 容易出现部分状态已经更新、部分状态仍然是旧值；
4. 刷新、自动翻页和手动跳页之间容易产生竞争；
5. 页面消失后，已启动的异步任务仍可能回写状态；
6. 分页状态机难以进行独立单元测试。

### 建议方案

将业务状态迁移到 ViewModel：

```swift
@MainActor
@Observable
final class ThreadDetailViewModel {
    var contentState: LoadableState<ThreadDetailContent>
    var pagination: ThreadPaginationState
    var replyComposer: ReplyComposerState
    var snapshot: SnapshotState

    private let repository: any ThreadRepository
    private var loadingTask: Task<Void, Never>?
}
```

推荐拆分结构：

```text
ThreadDetailView
├── ThreadMainPostSection
├── ThreadReplyList
├── ThreadDetailToolbar
├── ThreadPageControls
├── ThreadDetailViewModel
├── ThreadPaginationController
├── InlineGIFPlaybackCoordinator
└── ThreadSnapshotCoordinator
```

注意：不要只是把 1700 行切分成多个 View 文件，却仍让所有状态保留在父 View 中。真正需要迁移的是业务状态、异步任务和状态机。

---

## P0：分页存在竞态和旧请求覆盖新请求风险

当前页面同时存在：

- `refreshDetail()`；
- `loadNextPage()`；
- 自动预加载；
- 手动跳页；
- 下拉刷新；
- 回复成功后的刷新。

自动加载通过多个独立 `Task` 启动，取消和覆盖策略不统一。

### 潜在问题

- 第 2 页仍在请求时，用户下拉刷新第 1 页；
- 用户快速从第 2 页跳转至第 5 页；
- 页面已经退出，请求仍返回并更新状态；
- 自动加载失败后，相同行重新出现并再次触发；
- 回复成功后刷新，新旧分页请求结果互相覆盖；
- 旧帖请求返回到新打开的帖子页面。

### 建议方案

引入任务所有权和请求代次：

```swift
@MainActor
final class ThreadPaginationController {
    private var task: Task<Void, Never>?
    private var generation = 0

    func refresh() {
        generation += 1
        let currentGeneration = generation

        task?.cancel()
        task = Task {
            let result = try await repository.fetchThread(...)
            try Task.checkCancellation()

            guard currentGeneration == generation else { return }
            apply(result)
        }
    }
}
```

至少保证：

- 新刷新取消旧翻页任务；
- 页面退出时取消任务；
- 响应落地前检查 `Task.isCancelled`；
- 响应只能更新对应 thread ID 和请求代次；
- 同一页只允许一个进行中的请求；
- 已成功加载页面使用 `Set<Int>` 记录；
- 不要只依赖 `lastAutoLoadedPage`。

---

## P0：长帖子使用普通 `VStack`，存在明显性能风险

当前帖子详情使用：

```swift
ScrollView {
    VStack {
        ForEach(replyEntries) {
            ...
        }
    }
}
```

同时页面还支持：

- 连续累积分页；
- 富文本；
- 网络图片；
- GIF；
- 图片预览；
- 长图生成。

这意味着加载十几页后，所有回帖 View、富文本内容、图片容器都可能同时存在。

即使限制最多同时播放 3 个 GIF，也无法解决：

- View 树持续增长；
- 布局计算变重；
- 图片解码缓存增长；
- 内存无法及时回落；
- 状态变化导致大范围 View 重算。

### 建议测试场景

使用真机和 Instruments 验证：

- 200 条纯文本回复；
- 500 条纯文本回复；
- 100 条带图片回复；
- 20 个 GIF；
- 正序和倒序切换；
- 只看楼主来回切换；
- 页面退出后的内存释放。

重点观察：

- SwiftUI body update 次数；
- CPU Layout 峰值；
- 内存增长和回落；
- 图片解码峰值；
- 页面关闭后对象是否释放。

### 推荐改造

优先尝试：

```text
ScrollView
└── LazyVStack
    ├── PageSection 1
    ├── PageSection 2
    └── PageSection N
```

建议：

- 每页作为一个 Section；
- 每页保留一个页面锚点；
- 每页内部使用 Lazy 容器；
- GIF 可见性在容器级追踪；
- 避免为每条回复添加独立 GeometryReader；
- 对远离视口的历史页减少渲染成本。

---

## 三、架构层问题

## P1：Feature 层直接判断 `.nga`，破坏 capability 抽象

项目已经存在：

```swift
repository.capabilities
```

这是正确方向。

但帖子详情仍然直接判断：

```swift
private var supportsDirectPagination: Bool {
    repository.source == .nga
}
```

这会导致未来增加另一个数字分页论坛时，必须修改 Feature 层代码。

### 推荐模型

```swift
struct ThreadRepositoryCapabilities: Sendable {
    let paginationStyle: ThreadPaginationStyle
    let supportsReply: Bool
    let supportsRemoteFavorites: Bool
    let supportsFloorReply: Bool
    let supportsImageUpload: Bool
}

enum ThreadPaginationStyle: Sendable {
    case appendCursor
    case numberedPages(pageSize: Int)
    case none
}
```

Feature 层只读取：

```swift
switch repository.capabilities.paginationStyle {
case .numberedPages(let pageSize):
    ...
case .appendCursor:
    ...
case .none:
    ...
}
```

以下内容也不应硬编码在 View 中：

```swift
private let detailPageSize = 20
```

应由 Adapter 或 Capability 提供。

---

## P1：Repository 直接注入 SwiftUI View，生命周期边界不清晰

当前 View 直接持有：

```swift
let repository: any ThreadRepository
```

随着业务继续增长，会产生：

- View 直接了解 Data 层接口；
- Preview 构造复杂；
- Repository 生命周期不明确；
- 线程安全和取消策略分散；
- 很难统一管理重试、超时和状态恢复。

### 推荐结构

```swift
struct ThreadDetailView: View {
    @State private var viewModel: ThreadDetailViewModel
}
```

由 ViewModel 持有 Repository：

```swift
@MainActor
@Observable
final class ThreadDetailViewModel {
    private let repository: any ThreadRepository
}
```

同时建议给协议增加并发约束：

```swift
protocol ThreadRepository: Sendable {
    var source: ForumSource { get }
    var capabilities: ThreadRepositoryCapabilities { get }

    func fetchThread(...) async throws -> ThreadPage
}
```

如果 Repository 内部包含可变 Cookie、缓存或请求状态，建议使用 `actor` 或明确的隔离策略。

---

## P1：Domain 数据、分页状态和展示状态耦合较深

当前页面同时维护：

- `detailThread`；
- `canonicalThread`；
- `threadReplyTotalCount`；
- `loadedPageStartReplyIndices`；
- `currentPage`；
- `visiblePage`；
- `hasMoreReplies`。

这些变量分别描述不同层级的“真实状态”，容易产生不一致。

### 推荐聚合模型

```swift
struct ThreadDetailContent: Equatable {
    var canonical: ForumThread
    var pages: OrderedDictionary<Int, ThreadPage>
    var totalReplyCount: Int
    var hasMore: Bool
}
```

展示内容由纯函数生成：

```swift
func makeDisplayedReplies(
    from content: ThreadDetailContent,
    filter: ThreadFilter,
    blockedUsers: Set<BlockedUserKey>
) -> [DisplayedReply]
```

推荐职责：

```text
Repository
    ↓ 返回规范化页面数据
Pagination State
    ↓ 管理已加载页和请求状态
Selector
    ↓ 过滤、排序、屏蔽和楼层计算
View
    ↓ 渲染最终结果
```

---

## 四、SwiftUI 性能与状态更新

## P1：多个计算属性会在每次 View 更新时重复遍历回复

当前存在：

```swift
private var displayedReplies: [Reply]
private var displayedReplyEntries: [ThreadDetailDisplayedReplyEntry]
private var displayedAnchorPages: Set<Int>
```

其中 `displayedReplyEntries` 每次可能执行：

- 对分页起点排序；
- 枚举全部 replies 创建字典；
- 再枚举 displayedReplies；
- 计算每条回复所属页面；
- 构造新的 Entry 数组。

滚动 offset、GIF frame、按钮显示状态变化时，SwiftUI 可能频繁重新求值 body，以上 O(n) 操作也可能重复执行。

### 建议

1. 在 ViewModel 中缓存展示结果；
2. 仅在 replies、过滤条件或屏蔽列表变化时重建；
3. 分页归属直接存入 Page 模型；
4. 避免每次执行 `Array(reversed())`；
5. 使用稳定的 `DisplayedReply.ID`；
6. 屏蔽用户使用预构建 Set，而不是每一行查询 Store。

---

## P1：PreferenceKey 高频回调直接更新页面状态

帖子详情同时监听：

- 整体滚动 offset；
- 页面 anchor offset；
- GIF frame candidates。

这可能在滚动过程中产生高频计算和状态更新。

### 建议

- 只在跨越阈值时更新；
- 页码只有发生变化时才写入状态；
- 对 GIF frame 结果进行稳定排序和去重；
- 不保存无意义的原始几何值；
- 优先使用新版 SwiftUI 滚动 API；
- 能使用时考虑 `scrollPosition`、`scrollTargetLayout` 和可见性 API；
- 删除未实际使用的 `lastObservedScrollOffset`。

---

## P1：异步 Task 创建过于分散

当前按钮、生命周期和 `onAppear` 中存在大量：

```swift
Task { await refreshDetail() }
Task { await loadNextPage() }
Task { await submitReply() }
Task { await toggleFavorite() }
Task { await prepareSnapshot(...) }
```

这会导致：

- 取消策略分散；
- 错误处理分散；
- loading 状态分散；
- 同类操作可能重复启动；
- 页面退出后任务不易统一终止。

### 推荐模式

View 只发送用户意图：

```swift
Button("刷新") {
    viewModel.send(.refreshTapped)
}
```

由 ViewModel 统一管理：

- Task 创建；
- Task 取消；
- 去重；
- 超时；
- 重试；
- 页面销毁；
- loading 状态。

---

## 五、用户体验与 iOS 26 设计

## P1：当前玻璃效果偏手工模拟，缺少统一设计系统

帖子底部操作栏目前通过以下元素模拟玻璃：

- `.ultraThinMaterial.opacity(...)`；
- 白色渐变；
- 白色描边；
- 阴影；
- 多层 RoundedRectangle。

视觉效果可以接近玻璃，但如果每个页面各自实现，会出现：

- 圆角不一致；
- 描边透明度不一致；
- 深色模式效果不同；
- 按压反馈不同；
- 动画不同；
- iOS 26 与旧系统 fallback 混乱。

### 建议在 DesignSystem 中统一提供

```swift
struct ForumGlassContainer<Content: View>: View
struct ForumGlassButtonStyle: ButtonStyle
struct ForumFloatingBar<Content: View>: View
struct ForumGlassNavigationBackground: ViewModifier
```

统一尺寸：

```swift
enum ForumRadius {
    static let card: CGFloat = 18
    static let floatingBar: CGFloat = 24
}

enum ForumSpacing {
    static let page: CGFloat = 16
    static let section: CGFloat = 14
}
```

### NGA 暖黄色应拆成语义色

```text
backgroundPrimary
backgroundSecondary
surface
surfaceElevated
glassTint
textPrimary
textSecondary
accent
separator
warning
```

不要让页面直接依赖具体的棕黄色值。

---

## P1：Serif 字体不一定适合论坛长阅读

当前部分标题使用：

```swift
.font(.system(size: ..., weight: ..., design: .serif))
```

可能存在：

- 中文字体回退效果不可控；
- 不同系统版本表现不一致；
- 长时间阅读不一定舒适；
- 与 NGA 高信息密度论坛风格不一致。

建议：

- 正文和标题优先使用系统字体；
- 通过 weight、size、width 和 tracking 建立层级；
- 若保留纸张感，应明确中文字体 fallback；
- 测试动态字体和辅助功能粗体。

---

## P1：底部操作栏在小屏和大字体下可能拥挤

当前底部可能同时包含：

- 回复；
- 收藏；
- 只看楼主；
- 更多。

所有按钮同时显示图标和文字，在以下环境中容易拥挤：

- iPhone mini；
- 横屏；
- Accessibility 大字体；
- 本地化长文本。

### 建议

- 回复保留为主按钮；
- 收藏可以仅显示图标；
- 只看楼主和排序放入过滤菜单；
- iPad 使用扩展横向布局；
- 大字体下切换 compact layout；
- 不要强行限制动态字体。

---

## 六、错误处理

## P1：不应直接将 `error.localizedDescription` 展示给用户

底层错误可能包含：

- URLSession 系统错误；
- JSON Decoding 错误；
- HTML 解析错误；
- 服务端原始英文错误；
- 技术字段名称。

### 推荐领域错误模型

```swift
enum ForumError: LocalizedError {
    case offline
    case timeout
    case authenticationExpired
    case accessDenied
    case rateLimited
    case malformedResponse
    case sourceUnavailable
    case unknown

    var userMessage: String {
        ...
    }

    var recoverySuggestion: String? {
        ...
    }
}
```

建议：

- UI 展示用户可理解的信息；
- Debug Log 保留原始错误；
- 错误卡片提供重试按钮。

推荐错误样式：

```text
加载失败
网络连接似乎有问题

[重新加载]
```

---

## 七、数据与安全

## 当前做得较好的地方

项目文档已经明确区分：

- UserDefaults 普通业务状态；
- Keychain 登录凭证；
- Cookie Store 会话；
- 本地收藏；
- 浏览历史；
- 屏蔽用户；
- 频道订阅和排序。

这个边界是正确的。

---

## P1：Cookie 生命周期和隔离需要专项检查

需要确认：

- NGA 和 LINUX DO Cookie 是否按域隔离；
- 登出是否同时清理 Cookie 和持久化状态；
- Cookie 是否会意外共享到无关 WebView；
- 账号切换是否残留旧账号 Cookie；
- Web 登录只接受允许域名；
- 登录回调是否验证 URL；
- 是否防止任意页面伪造登录完成状态。

---

## P1：V2EX Token 需要检查

建议确认：

- Token 只存储于 Keychain；
- 日志不打印完整 Token；
- 网络日志不包含 Authorization Header；
- Keychain accessibility 使用合理级别；
- 登出后彻底删除；
- 诊断导出和截图不包含 Token。

推荐：

```swift
kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
```

---

## P1：NGA 图片上传需要检查隐私和资源控制

建议检查：

- 上传前压缩；
- 最大像素尺寸；
- 最大文件大小；
- 清理 EXIF GPS；
- MIME Type 校验；
- 多图并发限制；
- 上传取消；
- 临时文件清理；
- 后台切换；
- 返回 URL 的 Scheme 和 Host 校验。

---

## P2：浏览历史隐私功能

建议增加：

- 一键清空历史；
- 关闭历史记录；
- 按社区清空；
- 隐私模式；
- Face ID 或 App Lock 可作为后续功能。

---

## 八、测试问题

项目已经有 Unit Test 和 UI Test Target，但部分核心行为仍依赖人工验证。

其中最容易反复出现回归的是分页。

## P0：必须补充的单元测试

### NGA 分页合并

至少覆盖：

```text
第一页包含主楼和回复
第二页重复主楼
第二页重复最后一条回复
空白中间页
服务端总数不准确
楼层号缺失
回复 ID 重复但内容更新
倒序排列
只看楼主
屏蔽用户后页锚点变化
```

### 请求竞态

```text
刷新期间触发自动加载
自动加载期间手动跳页
连续点击下一页
页面退出后响应返回
旧线程请求返回到新线程页面
```

### Capability Gating

```text
V2EX 不显示远程回复
本地收藏和远端收藏行为不同
不支持楼层回复时不显示菜单
不支持上传时不显示附件按钮
```

### Persistence

```text
不同 Source 下相同 ID 不冲突
屏蔽用户名大小写策略
旧版本数据迁移
损坏 JSON 恢复
收藏去重
收藏顺序
UserDefaults 数据过大时行为
```

---

## P1：建议保留的 UI 测试主链路

1. 首页切换社区；
2. 打开帖子并加载下一页；
3. 只看楼主和倒序切换；
4. 收藏后在收藏页出现；
5. 登录失效后重新登录。

---

## 九、工程与文档问题

## P1：Xcode 工程格式过新

当前工程使用较新的 Project Object Version 和 Xcode Tool Version。

这会导致：

- Xcode Cloud 无法识别；
- 稳定版 Xcode 无法打开；
- 其他开发机兼容性差；
- CI 构建失败。

这与之前遇到的：

```text
future Xcode project file format
```

属于同类问题。

### 建议

- Project Format 使用 CI 支持的稳定版本；
- 不要因为本机使用 Xcode Beta，就保存为最新工程格式；
- README 标明最低 Xcode 版本；
- CI 固定 Xcode 版本；
- iOS 26 新 API 使用 `if #available` 隔离。

---

## P1：README 中存在本机绝对路径

当前文档中存在类似：

```markdown
[ForumHub.xcodeproj](/Users/v/XBP/ForumHub/ForumHub.xcodeproj)
```

这些链接在 GitHub 上无法访问。

应改为：

```markdown
[ForumHub.xcodeproj](./ForumHub.xcodeproj)
[CONTEXT.md](./CONTEXT.md)
[architecture.md](./docs/architecture.md)
```

---

## P2：第三方依赖与自研维护成本

如果项目主要依赖系统框架，这是一个优点。

但以下模块如果全部自研，需要有足够测试保障：

- GIF 解码；
- HTML 富文本解析；
- 图片缓存；
- Cookie Web 登录；
- 长图渲染；
- HTML fallback 解析。

并不一定需要引入第三方库，但需要评估：

- 性能；
- 边缘兼容；
- 安全；
- 后续维护成本。

---

## 十、推荐重构顺序

## 第一阶段：稳定核心逻辑，不修改 UI

1. 创建 `ThreadDetailViewModel`；
2. 将刷新、翻页、跳页、回复、收藏移出 View；
3. 建立统一 Task 取消机制；
4. 增加请求 generation；
5. 将 NGA 判断改为 pagination capability；
6. 为分页合并增加单元测试；
7. 建立统一 `ForumError`。

目标：

```text
ThreadDetailView.swift 控制在 300～500 行
```

---

## 第二阶段：优化性能

1. 回帖列表改为 Lazy 容器或分页 Section；
2. 缓存 displayed replies；
3. 缓存 displayed entries；
4. 避免滚动时反复创建数组和字典；
5. 图片缓存增加内存和磁盘预算；
6. GIF 播放与页面生命周期解耦；
7. 使用 Instruments 验证 200～500 楼帖子。

---

## 第三阶段：统一 DesignSystem

1. 建立 NGA 暖黄色语义色；
2. 建立统一玻璃容器；
3. 建立统一浮动操作栏；
4. 删除页面中重复的渐变、描边和阴影；
5. 支持深色模式；
6. 支持降低透明度；
7. 支持增强对比度；
8. 测试动态字体；
9. 测试横屏；
10. 测试 iPad。

---

## 第四阶段：发布质量

1. 修复 README 绝对路径；
2. 降低工程格式版本；
3. 固定 CI Xcode 版本；
4. 增加隐私开关；
5. 增加历史记录清理；
6. 审计 Cookie；
7. 审计 Token；
8. 清理图片 EXIF；
9. 增加核心 UI Test；
10. 增加崩溃日志和诊断方案。

---

## 十一、最值得立即修改的 10 项

| 优先级 | 修改项 | 收益 |
| --- | --- | --- |
| P0 | 拆分 `ThreadDetailView` | 降低最大维护风险 |
| P0 | 增加异步任务取消与 generation | 防止旧响应覆盖 |
| P0 | 增加 NGA 分页回归测试 | 防止核心功能回归 |
| P0 | 验证长帖子非 Lazy 渲染性能 | 避免卡顿和内存问题 |
| P1 | pagination capability 取代 `.nga` 判断 | 保持多源架构扩展性 |
| P1 | 缓存 displayed replies 和 entries | 降低滚动重算 |
| P1 | 建立统一错误模型 | 改善用户体验和调试 |
| P1 | 统一 Liquid Glass 组件 | 避免页面视觉漂移 |
| P1 | 修复 Xcode 工程格式兼容性 | 解决 CI 和云构建问题 |
| P1 | 修复 README 绝对路径 | 提升仓库可用性 |

---

## 十二、最终建议

ForumHub 当前不需要推倒重写。

项目已有的以下结构值得保留：

```text
Data
Domain
Features
Session
DesignSystem
Sync
```

当前真正需要解决的问题是：

> 帖子详情功能增长过快，逐渐绕过了原本设计好的分层。

建议优先将帖子详情改造为：

```text
ViewModel 驱动
+ 分页状态机独立
+ 异步任务可取消
+ Capability 驱动
+ Lazy 渲染
+ Fixture 回归测试
```

在核心业务稳定后，再继续推进：

- iOS 26 Liquid Glass；
- NGA 暖黄色主题；
- 页面视觉统一；
- 动态字体和无障碍适配。

这样可以避免在 UI 尚未稳定时继续堆叠复杂逻辑，也能让后续添加更多论坛源时，不需要反复修改现有页面。
