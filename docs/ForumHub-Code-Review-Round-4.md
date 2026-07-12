# ForumHub Code Review：正文展示不全与隐形问题审查

## 审查范围

本次重点审查：

- 最近提交 `fix：正文内容展示不全`；
- 前一次相关提交 `fix：正文内容缺失`；
- NGA API 与网页正文合并链路；
- `ForumPostDocument`、`ForumThread`、`Reply` 内容模型；
- HTML/BBCode 解析；
- SwiftUI 富文本与图片渲染；
- 可能导致回归、错位、性能下降和状态不一致的隐形问题。

本次为静态 Code Review，未执行 Xcode 构建、自动化测试或真机验证。

---

## 一、为什么“正文展示不全”会反复出现

### 1. 同一个帖子存在多个正文来源

详情页同时依赖 NGA App API 与 NGA 网页 HTML。API 的楼层、PID、作者和分页更稳定，网页正文通常更完整，但结构更脆弱、依赖 Cookie，也可能返回权限页。因此“正文不全”可能出现在网络、Parser、合并、Domain Model、ViewModel 或 SwiftUI 渲染任意一层。

### 2. 原始正文曾过早转换为普通字符串

旧流程大致是：

```text
API / HTML
→ structuredForumText
→ body: String
→ ForumContentParser
→ SwiftUI
```

`structuredForumText` 是有损转换，可能丢失嵌套 BBCode、表格、代码块、列表、图片属性、表情、连续换行和缩进。最新提交新增 `ForumPostDocument` 保存 `rawMarkup` 和 `normalizedText`，方向正确，但当前主要阅读器仍只解析 `normalizedText`，复杂内容仍可能继续丢失。

### 3. HTML 正文提取曾被嵌套标签提前截断

旧实现使用类似 `<div ...>(.*?)</div>` 的正则。正文内部出现嵌套 `<div>` 时，可能在首个内层闭合标签处停止，最终表现为正文后半段消失。新加入的 `HTMLPostContentExtractor` 按标签层级寻找闭合位置，比原实现更可靠。

### 4. 信息流摘要、API 正文和网页正文曾混用

详情页可能同时接触信息流 `summary`、API 正文和网页正文。如果三者通过相近字段流动，就容易互相覆盖。最新代码已经把列表对象转换为空正文占位，这是必要修正。

---

## 二、本次提交做得好的地方

1. 引入 `ForumPostDocument`，区分原始标记、阅读文本、格式和来源。
2. 明确 API 负责身份、楼层和顺序，网页负责正文补全。
3. 主楼排序不再依赖原数组顺序，而是识别 `pid == 0` 或 `floor == 0`。
4. 开始保留原始内容并补充回归测试，比继续堆字符串替换规则更合理。

---

## 三、发现的问题

## R-501：每次详情和分页都串行请求 API 与网页

- 优先级：高
- 可信度：已确认
- 类型：性能、网络、加载体验
- 涉及模块：`NGALiveThreadRepository`

当前流程：

```text
等待 API
→ 请求网页
→ 合并
→ 返回页面
```

### 影响

- 首屏加载时间增加；
- 每页多一次请求；
- 网页慢时 API 已有内容仍需等待；
- 更容易触发限流；
- UI Test 更容易长时间停留在“正在加载内容”。

### 建议

第一页采用渐进更新：

```text
API 返回
→ 立即展示
→ 后台请求网页
→ 网页更完整时补全
```

后续分页不应无条件请求网页，应按正文质量、截断标记、标签闭合和图片数量判断是否补全。

---

## R-502：保存了 `rawMarkup`，但渲染器仍只解析 `normalizedText`

- 优先级：高
- 可信度：已确认
- 类型：内容完整性、架构
- 涉及模块：`ForumRichContentView`

当前仍然是：

```swift
ForumContentParser.parse(document.normalizedText)
```

### 影响

嵌套 BBCode、表格、代码块、列表、折叠区、链接、颜色、未识别表情和嵌套引用仍可能被丢失。

### 建议

按格式选择 Parser：

```swift
switch document.markupFormat {
case .ngaBBCode:
    NGAContentParser.parse(document.rawMarkup)
case .html:
    HTMLContentParser.parse(document.rawMarkup)
case .markdown:
    MarkdownContentParser.parse(document.rawMarkup)
case .plainText:
    PlainTextParser.parse(document.rawMarkup)
}
```

短期至少增加 `document.renderBlocks`，让 View 不再直接处理字符串。

---

## R-503：合并后的文档内部可能自相矛盾

- 优先级：高
- 可信度：已确认
- 类型：数据一致性
- 涉及模块：`NGAThreadDetailMerger`

当前可能构造：

```text
rawMarkup = 网页 HTML
normalizedText = API 文本 + 网页补充
markupFormat = HTML
```

### 风险

`normalizedText` 中可能存在 API 独有内容，而 `rawMarkup` 中不存在。以后若重新从 `rawMarkup` 渲染，API 独有内容会再次消失，缓存、分享和当前页面也可能不一致。

### 建议

不要用一个文档假装成单一来源。可以保留多个来源：

```swift
struct ForumPostDocument {
    let sources: [ForumPostSource]
    let renderedBlocks: [ForumContentBlock]
}
```

或最小改动：

```swift
let primaryRawMarkup: String
let supplementalRawMarkup: String?
let normalizedText: String
```

并新增 `.merged` 格式。

---

## R-504：API 与网页回复只按楼层号匹配不够稳

- 优先级：高
- 可信度：高概率
- 类型：内容错配
- 涉及模块：网页 Parser、`NGAThreadDetailMerger`

### 风险场景

- 主楼楼层 0/1 差异；
- 删除楼层；
- 折叠楼层；
- 权限隐藏楼层；
- 分页偏移；
- API 缺少楼层；
- 网页广告节点。

### 建议

匹配优先级：

```text
1. sourcePostID / pid
2. floorNumber
3. 内容签名与相邻顺序
4. 不确定时不合并
```

网页解析应尽量提取真实 PID，不应只生成 `tid * 100_000 + floor`。

---

## R-505：HTML 提取器仍不是严格 HTML Parser

- 优先级：中高
- 可信度：高概率
- 类型：解析稳定性
- 涉及模块：`HTMLPostContentExtractor`

虽然比正则更可靠，但仍然是字符串扫描，可能被 HTML 注释、`script`、`style`、非法 HTML、未闭合标签、void 标签和页面结构变化影响。

### 建议

优先评估 SwiftSoup、WebKit DOM 提取或后台 `WKWebView` JavaScript 获取 `innerHTML`。现有提取器可保留为降级方案。

必须补充以下 Fixture：

```text
嵌套 div
blockquote
table
pre/code
script
style
未闭合标签
属性中包含 >
HTML 注释
```

---

## R-506：文本块统一 trim 会破坏格式

- 优先级：中
- 可信度：已确认
- 类型：排版、内容完整性
- 涉及模块：`ForumContentParser.appendText`

当前统一执行：

```swift
trimmingCharacters(in: .whitespacesAndNewlines)
```

### 影响

代码缩进、ASCII 图、列表层级、连续换行和文本与表情间距都可能被破坏。

### 建议

只过滤完全为空的块，保留块内缩进和换行；普通段落和代码块使用不同策略。

---

## R-507：所有图片仍通过 `NGAImageLoader`

- 优先级：中高
- 可信度：已确认
- 类型：安全、兼容性、架构
- 涉及模块：图片加载链路

### 风险

非 NGA 图片可能携带 NGA Referer 或 Cookie，V2EX、LINUX DO 图片也可能受到 NGA 特殊逻辑影响。

### 建议

拆成：

```text
ForumImageLoader
├── GenericImageLoader
└── NGARequestDecorator
```

只有可信 NGA 域名添加专属 Header 与 Cookie，并增加 URLProtocol Stub 测试。

---

## R-508：图片失败只有自动重试，没有点击重试

- 优先级：中
- 可信度：已确认
- 类型：错误恢复
- 涉及模块：`InteractiveForumImage`

当前失败后 350ms 自动重试一次。

### 问题

401、403、404 等永久错误也会重复请求；大量图片失败时请求量翻倍；网络恢复后用户不能就地重新加载。

### 建议

只对 timeout、connection lost、临时 DNS 和 5xx 自动重试；401、403、404、非法 URL 和不支持格式不自动重试。失败占位提供“重新加载”和“打开原图”。

---

## R-509：帖子业务身份与 `Identifiable` 身份仍有冲突风险

- 优先级：中高
- 可信度：高概率
- 类型：SwiftUI Diff、缓存、导航
- 涉及模块：`ForumThread`

当前 `id` 只有原生整数，不同论坛可能存在相同 ID。

### 风险

- Cell 复用错误；
- 导航打开错误帖子；
- 不同数据源内容覆盖；
- 缓存和历史串台。

### 建议

使用组合身份：

```swift
struct ForumThreadIdentity: Hashable {
    let source: ForumSource
    let nativeID: Int
}
```

最小改动也应统一使用 `source + nativeID`。

---

## R-510：完整内容参与 `Equatable` 可能放大重绘成本

- 优先级：中
- 可信度：高概率
- 类型：性能
- 涉及模块：`ForumThread`、`Reply`

合成 `Equatable` 可能比较完整正文、原始 HTML/BBCode、全部回复和每条回复内容。

### 影响

分页追加、长帖更新、GIF 活动变化和 SwiftUI 状态刷新都可能产生高成本比较。

### 建议

区分：

```text
identity
contentRevision
fullValueEquality
```

UI 不应为了判断是否为同一帖子而比较完整正文。

---

## 四、最重要的结构性隐患

## `body` 与 `contentDocument.normalizedText` 是双写状态

当前同时保存：

```swift
let body: String
let contentDocument: ForumPostDocument
```

调用方可以传入不一致值：

```text
body = A
contentDocument.normalizedText = B
```

### 后果

- 某些页面显示 A；
- 富文本显示 B；
- 搜索读取 A；
- 长图读取 B；
- 分享和缓存不一致。

### 建议立即整改

只保留一个权威来源：

```swift
struct ForumThread {
    let contentDocument: ForumPostDocument

    var body: String {
        contentDocument.normalizedText
    }
}
```

`Reply` 同样处理。

这是本轮最重要的结构性整改项。

---

## 五、为什么测试没有提前发现

现有测试多数是：

```text
给定 Fixture
→ Parser 输出
```

但真实链路是：

```text
网络响应
→ API Parser
→ 网页 Parser
→ 合并
→ ViewModel
→ SwiftUI
→ 图片和富文本
```

### 应补测试

#### 1. 真实正文黄金文件测试

保存同一帖子的 API JSON、网页 HTML 和预期最终内容，断言标题、主楼最后一句、图片顺序、表情、引用、代码块、回帖数、楼层和 PID。

#### 2. 内容一致性测试

```swift
#expect(thread.body == thread.contentDocument.normalizedText)
#expect(reply.body == reply.contentDocument.normalizedText)
```

#### 3. 端到端 Mock UI Test

固定复杂帖子，直接验证页面最后一句确实出现。

#### 4. Parser 变形测试

覆盖嵌套标签、表格、引用、未闭合标签、数组乱序、字典乱序和楼层缺失。

---

## 六、推荐整改顺序

### P0：消除正文双写

1. 删除 `ForumThread.body` 存储属性；
2. 改为 `contentDocument.normalizedText` 计算属性；
3. `Reply` 同样整改；
4. 增加内容一致性测试；
5. 增加真实复杂帖子黄金 Fixture。

### P1：修正文档合并模型

1. 保留 API 与网页两个原始来源；
2. 不再构造伪装成纯 HTML 的 merged document；
3. 回复优先按 PID 匹配；
4. 不可靠匹配时不自动合并。

### P2：优化加载流程

1. API 先展示；
2. 网页后台补全；
3. 后续分页按质量判断；
4. 缓存网页正文；
5. 测量详情首屏加载时间。

### P3：真正按格式解析

1. NGA BBCode Parser；
2. HTML Parser；
3. Markdown Parser；
4. 代码块、表格和链接节点；
5. 减少通用 `structuredForumText` 的有损转换。

### P4：处理图片与身份隐患

1. 图片 Loader 与 NGA Header 装饰分离；
2. 图片错误按类型决定重试；
3. 帖子 ID 改为 `source + nativeID`；
4. 避免完整正文参与高频相等性比较。

---

## 最终判断

这次提交方向正确，因为它开始承认：

> 论坛正文不是一个字符串，而是一份有来源、有格式、有原始表示和阅读投影的文档。

但项目当前仍处于过渡状态：

```text
旧模型：body String
+
新模型：ForumPostDocument
+
双来源：API + HTML
+
旧渲染：normalizedText Parser
```

当前最应优先解决：

```text
1. body 与 contentDocument 双写
2. merged document 的 rawMarkup 与 normalizedText 来源不一致
```

否则之后仍可能出现：

- 正文不全；
- 内容错位；
- 第一次不显示、第二次正常；
- 分享内容和页面内容不同；
- 缓存恢复后内容变化；
- 某些帖子正常、某些帖子异常。

`REVIEW:v1`
