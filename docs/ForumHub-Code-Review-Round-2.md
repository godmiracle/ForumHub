# ForumHub 第二轮 Code Review

> 仓库：`godmiracle/ForumHub`  
> 评审范围：最新 `main` 分支  
> 重点问题：
>
> 1. 首页、热门再次点击 Tab 后不回到顶部；
> 2. NGA 帖子详情正文和图片不完整；
> 3. 点击顶部搜索卡顿，键盘弹出后难以隐藏。

---

## 一、整体结论

上一轮修改已经加入了不少正确方向的改进：

- 统一 `ForumError`；
- 分页请求 generation；
- 请求取消；
- 页面消失时停止详情加载；
- 回帖展示缓存；
- 分页重复内容合并；
- Capability 增加楼层回复能力；
- iOS 26 `glassEffect` 与旧系统 fallback；
- NGA 头像 HTTP 自动升级为 HTTPS。

这些修复有效改善了项目的稳定性和视觉一致性。

不过，帖子详情模块的重构仍然只完成了一半。`ThreadDetailView` 依然保留大量 `@State`，同时承担内容加载、分页、回复、收藏、截图、GIF 播放、滚动追踪、页面跳转和错误提示。

| 问题 | 主要根因 | 优先级 |
| --- | --- | --- |
| 首页、热门重复点击不回顶 | Tab 重选监听逻辑错误 | P0 |
| NGA 详情正文和图片不完整 | 图片解析规则过严，API 部分成功后不再网页补全 | P0 |
| 顶部搜索卡顿 | 搜索输入状态位于根 View，引发大范围重算和重复排序 | P1 |
| 键盘无法方便隐藏 | 缺少 `FocusState`、键盘工具栏和滚动收起策略 | P1 |
| 搜索旧结果可能覆盖新结果 | 搜索页缺少 Task 所有权和 generation | P1 |
| 帖子详情仍过度集中 | ViewModel 化未真正完成 | P1 |

---

# 二、问题一：首页、热门再次点击不回顶

## 2.1 当前回顶链路

```text
重复点击 Tab
    ↓
requestScrollToTop
    ↓
tabScrollRequest 更新
    ↓
ForumFeedContent 监听变化
    ↓
ScrollViewReader.scrollTo(topAnchorID)
```

`ForumFeedContent` 内部的监听方向是正确的：

```swift
.onChange(of: scrollRequest) { _, request in
    guard request?.targets(tab) == true else { return }

    withAnimation(.snappy(duration: 0.28)) {
        proxy.scrollTo(topAnchorID, anchor: .top)
    }
}
```

## 2.2 根因：`UITapGestureRecognizer` 状态处理错误

当前逻辑依赖先收到 `.began`，再收到 `.ended`：

```swift
@objc private func tabBarTapped(_ recognizer: UITapGestureRecognizer) {
    switch recognizer.state {
    case .began:
        beganOnSelectedTab = tab == currentTab

    case .ended:
        guard beganOnSelectedTab, tab == currentTab else { return }
        onReselect(tab)

    default:
        break
    }
}
```

普通 `UITapGestureRecognizer` 的 target-action 通常不会按照这个顺序触发，导致：

```swift
beganOnSelectedTab == false
```

最终重复点击事件被拦截。

## 2.3 最小修复方案

删除 `beganOnSelectedTab`，在 `.ended` 时直接判断点击位置对应的 Tab 是否为当前 Tab：

```swift
@objc private func tabBarTapped(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended,
          let tabBar,
          let tappedTab = tab(
            at: recognizer.location(in: tabBar),
            in: tabBar
          ),
          tappedTab == currentTab
    else {
        return
    }

    onReselect(tappedTab)
}
```

同时删除：

```swift
private var beganOnSelectedTab = false
```

以及 `.began`、`.cancelled`、`.failed` 对该状态的处理。

## 2.4 更稳定的方案：监听 Tab Item 的 UIControl

```swift
final class Coordinator: NSObject {
    var currentTab: FeedTab
    var onReselect: (FeedTab) -> Void

    private weak var tabBar: UITabBar?
    private var controls: [UIControl] = []

    init(
        currentTab: FeedTab,
        onReselect: @escaping (FeedTab) -> Void
    ) {
        self.currentTab = currentTab
        self.onReselect = onReselect
    }

    func attach(to tabBar: UITabBar) {
        guard self.tabBar !== tabBar else { return }

        controls.forEach {
            $0.removeTarget(
                self,
                action: #selector(tabItemTapped(_:)),
                for: .touchUpInside
            )
        }

        self.tabBar = tabBar

        controls = tabBar.subviews
            .compactMap { $0 as? UIControl }
            .filter { !$0.isHidden && $0.alpha > 0 }
            .sorted { $0.frame.minX < $1.frame.minX }

        controls.forEach {
            $0.addTarget(
                self,
                action: #selector(tabItemTapped(_:)),
                for: .touchUpInside
            )
        }
    }

    @objc private func tabItemTapped(_ sender: UIControl) {
        guard let index = controls.firstIndex(of: sender),
              FeedTab.allCases.indices.contains(index)
        else {
            return
        }

        let tappedTab = FeedTab.allCases[index]
        guard tappedTab == currentTab else { return }
        onReselect(tappedTab)
    }
}
```

长期更推荐恢复项目中已有的自定义 `ForumBottomBar`，自定义按钮天然能识别重复点击，也不依赖 UIKit 内部层级。

## 2.5 首页和热门使用独立回顶 Token

```swift
@State private var homeScrollToTopToken = 0
@State private var hotScrollToTopToken = 0
```

```swift
ForumFeedContent(
    tab: tab,
    scrollToTopToken: tab == .home
        ? homeScrollToTopToken
        : hotScrollToTopToken
)
```

子页面：

```swift
.onChange(of: scrollToTopToken) {
    withAnimation(.snappy(duration: 0.28)) {
        proxy.scrollTo(topAnchorID, anchor: .top)
    }
}
```

## 2.6 推荐交互

```text
列表不在顶部
→ 点击当前 Tab：只回顶

列表已经在顶部
→ 再次点击当前 Tab：刷新
```

这样比每次重复点击都立即刷新更符合常见移动端行为。

---

# 三、问题二：NGA 帖子详情正文和图片不完整

问题主要发生在以下链路：

```text
NGA API / Web 数据
    ↓
源数据解析与标准化
    ↓
ForumContentParser 分块
    ↓
图片 URL 处理
    ↓
图片加载
```

## 3.1 图片正则过于严格

当前规则只适用于：

```text
[图片] https://example.com/a.jpg
```

容易漏掉：

```text
文字 [图片] https://img.example.com/a.jpg
[img]https://img.example.com/a.jpg[/img]
[图片] //img.nga.178.com/a.jpg
[图片] /attachments/mon_2026/a.jpg
[图片] https://example.com/a.jpg 图片说明
[图片] https://example.com/a.jpg [图片] https://example.com/b.jpg
```

## 3.2 建议使用 Tokenizer

```swift
enum ForumContentToken {
    case text(String)
    case image(URL)
    case quote(ForumQuoteBlock)
    case link(URL, title: String?)
}
```

```swift
enum ForumContentTokenizer {
    static func tokenize(_ rawText: String) -> [ForumContentToken] {
        let normalized = normalize(rawText)
        return scan(normalized)
    }
}
```

## 3.3 低成本修复：放宽图片规则并统一 URL Resolver

```swift
private static let imagePattern =
    #"(?:\[图片\]\s*|\[img\])((?:https?:)?//[^\s\[\]<>\"']+|/[^\s\[\]<>\"']+)(?:\[/img\])?"#
```

```swift
enum ForumImageURLResolver {
    static func resolve(_ rawValue: String) -> URL? {
        var value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)

        value = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")

        if value.hasPrefix("//") {
            value = "https:" + value
        } else if value.hasPrefix("/") {
            value = "https://img.nga.178.com" + value
        }

        guard var components = URLComponents(string: value) else {
            return nil
        }

        if components.scheme == "http",
           components.host?.contains("nga") == true {
            components.scheme = "https"
        }

        return components.url
    }
}
```

解析时不要直接使用 `URL(string:)`：

```swift
let rawURL = String(text[urlRange])

if let url = ForumImageURLResolver.resolve(rawURL) {
    blocks.append(
        ForumContentBlock(
            id: blocks.count,
            content: .image(url)
        )
    )
}
```

## 3.4 API 部分成功后不会网页补全

当前逻辑只要 API Parser 返回 `ForumThread`，就直接返回，即使正文、图片或楼层只解析出一部分。

建议增加完整度评估：

```swift
struct ThreadParseQuality {
    let hasUsefulBody: Bool
    let parsedReplyCount: Int
    let expectedReplyCount: Int
    let detectedRawImageCount: Int
    let parsedImageCount: Int

    var shouldEnrichFromWeb: Bool {
        !hasUsefulBody
            || parsedReplyCount == 0
            || parsedReplyCount + 2 < min(expectedReplyCount, 20)
            || parsedImageCount < detectedRawImageCount
    }
}
```

Repository：

```swift
func fetchThread(
    tid: Int,
    page: Int
) async throws -> ThreadDetailFetchResult {
    let apiResult = try await fetchAPIThread(
        tid: tid,
        page: page
    )

    guard let apiThread = apiResult.thread else {
        return try await fetchWebThread(
            tid: tid,
            page: page,
            apiRawText: apiResult.rawText
        )
    }

    let quality = ThreadParseQualityEvaluator.evaluate(
        thread: apiThread,
        rawText: apiResult.rawText
    )

    guard quality.shouldEnrichFromWeb else {
        return ThreadDetailFetchResult(
            thread: apiThread,
            rawText: apiResult.rawText
        )
    }

    do {
        let webResult = try await fetchWebThread(
            tid: tid,
            page: page,
            apiRawText: apiResult.rawText
        )

        return ThreadDetailFetchResult(
            thread: ThreadDetailEnricher.merge(
                api: apiThread,
                web: webResult.thread
            ),
            rawText: webResult.rawText
        )
    } catch {
        return ThreadDetailFetchResult(
            thread: apiThread,
            rawText: apiResult.rawText
        )
    }
}
```

网页结果应当补全 API 数据，而不是直接覆盖全部字段。

## 3.5 内容模型不应过早退化为 String

推荐：

```swift
struct ForumPostContent: Equatable {
    let rawText: String
    let blocks: [ForumContentBlock]
}
```

或者兼容现有结构：

```swift
struct ForumThread {
    let body: String
    let contentBlocks: [ForumContentBlock]
}
```

推荐链路：

```text
Source-specific Parser
    ↓
直接生成 ForumContentBlock
    ↓
View 直接渲染
```

## 3.6 图片请求可能缺少 NGA Header

```swift
var request = URLRequest(url: url)

request.setValue(
    "https://bbs.nga.cn/",
    forHTTPHeaderField: "Referer"
)

request.setValue(
    NGAUserAgent.value,
    forHTTPHeaderField: "User-Agent"
)

request.httpShouldHandleCookies = true
```

只对可信 NGA 域名添加：

```swift
static let trustedImageHosts: Set<String> = [
    "img.nga.178.com",
    "img4.nga.178.com",
    "bbs.nga.cn",
    "nga.178.com"
]
```

## 3.7 必须增加的 Fixture

```text
纯文本
多段 BBCode
HTML img
[img] 标签
协议相对 URL
相对附件路径
一行多张图片
URL 中带 &amp;
GIF
缩略图与原图
引用中带图片
表格
折叠内容
代码块
表情图片
第二页及后续页面图片
```

---

# 四、问题三：点击顶部搜索卡顿

## 4.1 根因：输入状态放在根 ContentView

当前每输入一个字符都会触发：

```text
searchText 修改
    ↓
ContentView.body 重算
    ↓
TabView 重算
    ↓
首页和热门页面重算
    ↓
displayedThreads 重算
    ↓
threads.sorted 再执行
    ↓
帖子列表重新 Diff
```

## 4.2 搜索草稿状态下沉到 ForumTopBar

```swift
struct ForumTopBar: View {
    @State private var searchDraft = ""
    @FocusState private var isSearchFocused: Bool

    let onSearch: (String) -> Void

    var body: some View {
        TextField(
            searchPlaceholder,
            text: $searchDraft
        )
        .focused($isSearchFocused)
        .submitLabel(.search)
        .onSubmit {
            submitSearch()
        }
    }

    private func submitSearch() {
        let keyword = searchDraft
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !keyword.isEmpty else { return }

        isSearchFocused = false
        onSearch(keyword)
    }
}
```

父层只保留：

```swift
@State private var submittedSearchText = ""
```

## 4.3 首页和热门共享一份顶部搜索栏

```swift
VStack(spacing: 0) {
    if selectedTab == .home
        || selectedTab == .hot {
        ForumTopBar(...)
    }

    TabView(selection: $selectedTab) {
        homeContent
            .tag(FeedTab.home)

        hotContent
            .tag(FeedTab.hot)

        communityContent
            .tag(FeedTab.community)

        historyContent
            .tag(FeedTab.history)

        userContent
            .tag(FeedTab.user)
    }
}
```

## 4.4 缓存排序结果

将排序移入 ViewModel：

```swift
@MainActor
@Observable
final class ForumViewModel {
    private(set) var threads: [ForumThread] = []
    private(set) var displayedThreads: [ForumThread] = []

    var sortMode: FeedSortMode = .lastReply {
        didSet {
            rebuildDisplayedThreads()
        }
    }

    private func applyThreads(
        _ newThreads: [ForumThread]
    ) {
        threads = newThreads
        rebuildDisplayedThreads()
    }

    private func rebuildDisplayedThreads() {
        displayedThreads = threads.sorted {
            sort($0, $1, mode: sortMode)
        }
    }
}
```

---

# 五、键盘弹出后无法方便隐藏

## 5.1 顶部搜索栏增加 FocusState

```swift
TextField(searchPlaceholder, text: $searchDraft)
    .focused($isSearchFocused)
    .submitLabel(.search)
    .onSubmit {
        submitSearch()
    }
    .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()

            Button("完成") {
                isSearchFocused = false
            }
        }
    }
```

## 5.2 清空按钮处理焦点

```swift
Button {
    searchDraft = ""
    isSearchFocused = false
} label: {
    Image(systemName: "xmark.circle.fill")
}
```

## 5.3 滚动时收起键盘

首页和热门：

```swift
.scrollDismissesKeyboard(.interactively)
```

搜索结果：

```swift
.scrollDismissesKeyboard(.immediately)
```

## 5.4 搜索结果提交后收起

```swift
@Environment(\.dismissSearch)
private var dismissSearch
```

```swift
.onSubmit(of: .search) {
    dismissSearch()

    Task {
        await search(reset: true)
    }
}
```

---

# 六、搜索页本身的问题

## 6.1 缺少 Task 所有权和 generation

```swift
@MainActor
@Observable
final class SearchThreadsViewModel {
    var query = ""
    var threads: [ForumThread] = []
    var state: SearchState = .idle

    private let repository: any ThreadRepository
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var generation = 0

    init(repository: any ThreadRepository) {
        self.repository = repository
    }

    func submit() {
        generation += 1

        let requestGeneration = generation
        let keyword = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !keyword.isEmpty else { return }

        searchTask?.cancel()
        loadMoreTask?.cancel()

        searchTask = Task {
            do {
                let result = try await repository.searchThreads(
                    query: keyword,
                    page: 1
                )

                try Task.checkCancellation()
                guard requestGeneration == generation else { return }

                threads = result.payload?.threads ?? []
                state = .loaded
            } catch {
                guard let forumError = ForumError.resolve(error) else {
                    return
                }

                guard requestGeneration == generation else { return }
                state = .failed(forumError)
            }
        }
    }

    func cancel() {
        generation += 1
        searchTask?.cancel()
        loadMoreTask?.cancel()
        searchTask = nil
        loadMoreTask = nil
    }
}
```

## 6.2 新搜索取消旧加载更多

```swift
loadMoreTask?.cancel()
currentPage = 1
canLoadMore = false
threads = []
```

## 6.3 避免同关键词重复请求

```swift
guard keyword != searchedQuery
    || threads.isEmpty
else {
    return
}
```

## 6.4 搜索错误统一使用 ForumError

```swift
errorMessage = ForumError.resolve(error)?.userMessage
```

---

# 七、第二轮整体 Review 发现

## 7.1 已改善部分

- 错误模型；
- 请求取消；
- generation；
- 分页去重；
- 展示数据缓存；
- DesignSystem；
- iOS 26 Liquid Glass；
- NGA 头像 URL；
- Capability 的回复能力。

## 7.2 `ThreadDetailView` 仍未真正 ViewModel 化

当前只是完成了 View 文件拆分，还没有真正完成业务状态和异步任务拆分。

建议建立：

```text
ThreadDetailViewModel
ThreadPaginationController
ThreadDetailPresentationBuilder
ThreadImageCoordinator
```

## 7.3 Capability 仍不完整

建议补充：

```swift
struct ForumCapabilities {
    let supportsSearch: Bool
    let supportsFavorites: Bool
    let supportsReply: Bool
    let supportsReplyTargeting: Bool
    let supportsAuthentication: Bool
    let supportsFeedPagination: Bool

    let threadPaginationStyle: ThreadPaginationStyle
    let supportsImageUpload: Bool
    let supportsWebFallback: Bool
    let requiresImageReferer: Bool
}
```

```swift
enum ThreadPaginationStyle {
    case none
    case numbered(pageSize: Int)
    case cursor
}
```

这样可以删除 View 中硬编码的 `detailPageSize = 20` 和 `repository.source == .nga`。

---

# 八、推荐实施顺序

## 第一批：解决当前三个 Bug

1. 修复 Tab 重选监听；
2. 给顶部搜索增加 `FocusState`；
3. 搜索提交后主动收起键盘；
4. 搜索草稿状态下沉到 `ForumTopBar`；
5. 首页和热门共享一份顶部栏；
6. 缓存帖子排序结果；
7. 放宽 NGA 图片解析；
8. 增加图片 URL Resolver；
9. 增加 API 解析完整度检查；
10. API 内容不足时使用 Web 补全。

## 第二批：稳定搜索和图片链路

1. 创建 `SearchThreadsViewModel`；
2. 增加搜索 generation；
3. 取消旧搜索；
4. 取消旧加载更多；
5. 搜索错误统一使用 `ForumError`；
6. 图片请求增加可信域名 Header；
7. 建立 NGA 富文本 Fixture；
8. 建立图片 URL Resolver 测试；
9. 建立 API/Web 合并测试。

## 第三批：完成帖子详情重构

1. 创建 `ThreadDetailViewModel`；
2. 创建 `ThreadPaginationController`；
3. 创建 `ThreadDetailPresentationBuilder`；
4. 将正文改为结构化 Content Blocks；
5. 将 page size 移入 Capability；
6. 将分页样式移入 Capability；
7. 最后验证长帖子 Lazy 渲染性能。

---

# 九、验收标准

## 9.1 首页和热门回顶

- 首页滚动 20 条后，再点首页，立即回顶；
- 热门滚动 20 条后，再点热门，立即回顶；
- 点击其他 Tab 不触发错误回顶；
- 首页与热门滚动位置互不影响；
- 快速连续点击不会启动多个刷新请求；
- 刷新后仍处于列表顶部；
- 已在顶部时再次点击才执行刷新。

## 9.2 NGA 正文和图片

- 与 NGA 网页逐段对比，正文完整；
- 主楼和回帖图片数量一致；
- 引用中的图片可显示；
- GIF 可显示；
- `//` URL 可显示；
- `/attachments/...` 可显示；
- 带 `&amp;` 的 URL 可显示；
- 第 2 页以后图片不丢失；
- 图片失败后可打开原图；
- API 不完整时 Web 补全生效；
- API 与 Web 内容不会重复。

## 9.3 搜索与键盘

- 点击搜索框无明显掉帧；
- 输入字符时帖子列表不会重复排序；
- 首页和热门只存在一个顶部搜索框；
- 点击搜索后键盘自动收起；
- 滚动结果列表时键盘收起；
- 键盘工具栏有“完成”按钮；
- 切换 Tab 时键盘收起；
- 快速连续搜索不会显示旧结果；
- 旧关键词下一页不会追加到新关键词；
- 搜索失败显示用户可理解的错误信息。

---

# 十、最终建议

当前最应该优先完成的是：

```text
修复 Tab 重选监听
    +
隔离搜索输入状态
    +
补全 NGA 内容解析链路
```

下一阶段再继续：

```text
SearchThreadsViewModel
ThreadDetailViewModel
Capability 分页模型
结构化正文 Content Blocks
```

项目不需要推倒重写，但需要避免继续把新的状态和异步逻辑添加回 `ThreadDetailView` 和 `ContentView`。

推荐最终目标：

```text
View
    只负责 UI

ViewModel
    管理状态和用户操作

Repository
    管理数据源和请求

Parser
    输出结构化内容

Capability
    描述不同论坛的能力差异
```
