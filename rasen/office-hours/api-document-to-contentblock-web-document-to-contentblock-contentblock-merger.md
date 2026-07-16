## Office Hours: API Document → ContentBlock、Web Document → ContentBlock、ContentBlock Merger

**Product:** Design
**Date:** 2026-07-16

### Executive Summary

建议把 NGA 帖子内容链路从“两个有损字符串的启发式并集”改为“两个来源文档分别解析为同一规范节点模型，再按序列与节点语义合并”。最终链路是：

```text
API BBCode Document ──> NGA BBCode Block Parser ──┐
                                                  ├─> NGA ContentBlock Merger ─> ForumPostDocument.blocks
Web HTML Document ───> NGA HTML Block Parser ────┘                              ├─> 原生渲染
                                                                                 └─> normalizedText（兼容投影）
```

核心不是把“按行去重”换成“按 Block 去重”这么简单，而是建立三条不变量：

1. Parser 负责理解单一来源的语法，Merger 不理解 BBCode 或 HTML。
2. Merger 只依据规范节点的精确语义、相对顺序和来源优先级，不解析字符串、不维护站点格式特例。
3. 原始 API/Web 文档都保留；最终 `blocks` 是原生阅读权威，`normalizedText` 仅由 `blocks` 计算得到。

推荐先覆盖现有四类节点（text、image、smile、quote），建立真实 Fixture 和差分测试，再逐类扩展 link、code、list、table。不要在第一阶段重做完整富文本引擎。

### Problem Statement

当前 `NGAThreadDetailMerger.mergedDocument` 对 `apiDocument.normalizedText` 和 `webDocument.normalizedText` 做以下处理：

- 去首尾空白并进行全文包含判断；
- 按换行拆成 content unit；
- 对图片 URL 做特例归一化；
- 其余内容删除空白、转小写后作为文本 key；
- 把 Web 中判断为缺失的行追加到 API 文本尾部。

这条链路的问题已经由当前代码直接证明：

- 结构在 merge 前已经由 `structuredForumText` 压平成字符串，无法可靠区分段落、引用、图片、表情和嵌套结构。
- “行”不是内容领域实体；来源增加换行、包装标签或排版差异就会改变合并结果。
- Set 式去重忽略顺序和重复语义，合法的重复段落或重复图片可能被删除。
- Web 补充内容统一追加到末尾，无法恢复它在原文中的位置。
- 合并结果使用 Web `rawMarkup`，但 `normalizedText` 可能同时包含 API 独有内容，两个字段不再描述同一份文档。
- 新情况只能继续进入 `normalized`、`contentUnits` 或 `contentUnitKey`，规则增长不可避免。

### Key Findings / Design Decisions

#### 1. 选择规范 Block IR，不选择 AST 直接合并

比较三条路线：

| 路线 | 优点 | 主要问题 | 结论 |
| --- | --- | --- | --- |
| 继续增强字符串规则 | 改动最小 | 结构持续丢失，规则无上限 | 不采用 |
| 合并 BBCode AST 与 HTML DOM | 信息最完整 | 两棵异构语法树难以比较，Merger 会耦合两种语法 | 不采用 |
| 两种语法各自降到规范 Block IR 后合并 | 语法差异止于 Parser，渲染和合并共享语义 | 需要定义节点粒度和冲突策略 | 推荐 |

Block IR 是面向阅读器的规范中间表示，不是原始文档的替代品。无法识别的内容仍留在来源文档中，并以 `.unsupported` 或安全文本降级进入 Block IR。

#### 2. 调整 `ForumPostDocument` 的权威关系

目标模型建议表达为：

```swift
struct ForumPostDocument: Equatable {
    let representations: [ForumMarkupRepresentation]
    let blocks: [ForumContentBlock]

    var normalizedText: String {
        ForumContentPlainTextProjector.project(blocks)
    }
}

struct ForumMarkupRepresentation: Equatable {
    let origin: ContentOrigin       // api / web / native
    let rawMarkup: String
    let markupFormat: MarkupFormat
    let sourceURL: URL?
}
```

关键约束：

- `representations` 保存 API BBCode 与 Web HTML 两份事实，不再制造“单一 merged rawMarkup”。
- `blocks` 是原生阅读器的唯一权威投影。
- `body` 继续由 `normalizedText` 计算，兼容现有调用点。
- `normalizedText` 不允许作为 merger 输入，也不允许反向覆盖 `blocks` 或原始文档。

若一次迁移该模型影响过大，可以先在 NGA 适配层引入内部 `NGAParsedPostDocument { representation, blocks }`，稳定后再把多 representation 提升到共享领域模型。

#### 3. Block 身份与合并等价必须分开

现有 `ForumContentBlock.id: Int` 是数组位置，只适合当前一次渲染，不适合作为跨来源合并键。建议拆成两个概念：

- `id`：SwiftUI 展示身份，由最终文档在 merge 后稳定生成；相同内容重复出现时也必须不同。
- `mergeFingerprint`：Merger 内部的语义指纹，不进入 UI 身份，也不作为领域相等性的替代。

第一阶段节点粒度：

```swift
enum ForumContent {
    case text(ForumTextBlock)       // 至少按段落，而不是按任意换行
    case image(ForumImageBlock)     // canonical URL + 可选属性
    case smile(ForumSmileBlock)     // 规范资源身份
    case quote(ForumQuoteBlock)     // author/time/body blocks
    case unsupported(ForumUnsupportedBlock)
}
```

建议的精确指纹：

- text：Unicode/HTML entity 归一化、统一换行与首尾空白；不删除所有内部空白，不做模糊相似删除。
- image：经 `ForumImageURLResolver` 得到的 canonical URL；保留 alt、尺寸等展示属性，但它们不必参与第一层身份。
- smile：规范后的资源 URL 或 NGA smile key。
- quote：结构化 author、time 与 quote body 的递归指纹。
- unsupported：不跨来源去重，避免误删未知内容。

重复节点不能用全局 `Set` 消除。相同图片或文本在同一帖子出现两次可能是作者真实意图。

#### 4. Merger 使用“序列对齐 + 缝隙插入”，不是集合并集

输入：API blocks、Web blocks、来源策略。输出：最终 blocks、合并报告。

推荐算法：

1. 对两侧 Block 计算精确 `mergeFingerprint`。
2. 用 LCS 或 patience-diff 风格算法寻找保持相对顺序的共同锚点。
3. 逐个处理锚点之间的 gap：
   - 仅 API 存在：保留 API 节点；
   - 仅 Web 存在：在相邻锚点之间插入 Web 节点；
   - 两侧完全相同：只保留一次，并合并 provenance/展示属性；
   - 两侧都存在且无法精确对应：按明确冲突策略处理，不做模糊删除。
4. 重新生成稳定 display ID，输出 merge diagnostics。

默认来源策略建议为：

- API 仍是楼层身份、作者、顺序、分页的权威。
- Web 是内容保真与补全来源。
- 可精确证明重复时去重。
- 无法证明重复时宁可保留，不能静默丢内容。
- 一个 gap 内两侧出现明显互斥的大段文本时，标记 conflict；第一阶段可优先展示 Web gap、同时通过 diagnostics 和测试保留可观测性，而不是永久把两段拼在一起。

这里仍存在“策略”，但策略数量是有限的领域决策；以后新增 link/code/table 只需 Parser 产出规范节点和节点自身指纹，不应修改 Merger 主流程。

#### 5. Parser 的职责和边界

建议新增两个 NGA 专用 Parser：

- `NGABBCodeContentBlockParser`
- `NGAHTMLContentBlockParser`

它们都实现类似接口：

```swift
protocol ForumContentBlockParsing {
    func parse(_ representation: ForumMarkupRepresentation) -> ContentParseResult
}

struct ContentParseResult {
    let blocks: [ForumContentBlock]
    let warnings: [ContentParseWarning]
}
```

Parser 需要保证：

- 输入仅是一份来源文档；
- 输出节点顺序与来源一致；
- 不跨 API/Web 猜测缺失内容；
- 未识别标记不会从 raw representation 消失；
- warning 可测试、可统计，但不向用户暴露原始响应。

Web 的 `HTMLPostContentExtractor` 继续负责精确定位 `postcontent<floor>`；定位后的 `innerHTML` 再交给 HTML Block Parser。API 的 `rawContent` 直接交给 BBCode Block Parser。楼层配对仍使用 `floorNumber`，不改为正文相似度匹配。

#### 6. 合并报告必须可观测

建议 merger 返回：

```swift
struct ContentMergeResult {
    let blocks: [ForumContentBlock]
    let diagnostics: ContentMergeDiagnostics
}
```

Diagnostics 至少包含 matched、apiOnly、webOnly、conflicts、unsupported 数量。Debug/Test 可记录结构化结果；Release 不记录正文、Cookie 或原始标记。这样新 Fixture 失败时能判断是 Parser 缺口还是 Merger 冲突，而不是继续在一个字符串函数里追加规则。

### Recommended Next Steps

#### 阶段 0：冻结当前行为并建立样本矩阵

- 把当前已知异常全部固化为脱敏 API JSON + Web HTML 成对 Fixture。
- 每对 Fixture 明确期望 Block 序列，不只断言 `body.contains`。
- 覆盖：纯文本、段落换行、绝对/相对图片、重复图片、引用、表情、嵌套 HTML、API-only、Web-only、两侧冲突、未知标签。
- 记录当前 merger 的失败类型，作为迁移验收基线。

退出条件：每种现有规则至少有一个能解释其存在的 Fixture。

#### 阶段 1：让 Document 原生携带 blocks，但暂不替换 merger

- 为 `ForumPostDocument` 增加 `blocks`（或先增加 NGA 内部 parsed document）。
- `ForumRichContentView`、长图和图片扫描优先消费 `document.blocks`。
- `normalizedText` 改由 Block projector 生成；保留旧构造器作为迁移适配器。
- 不改变 API/Web 内容选择行为。

退出条件：现有三数据源渲染与测试不回归，且详情渲染不再调用 `ForumContentParser.parse(document.normalizedText)`。

#### 阶段 2：实现双 Parser

- 先产出现有 text/image/smile/quote 四类 Block。
- API 与 Web 同一语义必须产生相同 canonical block payload。
- Parser 测试分别验证，不通过 merger 掩盖 Parser 错误。

退出条件：样本矩阵中所有已支持内容都能从两种来源得到确定 Block 序列。

#### 阶段 3：实现并影子运行 Block Merger

- 新增 `NGAContentBlockMerger`，限定在 `Data/NGA`。
- 先在测试或 Debug 中同时计算旧、新结果，不改变 Release 展示。
- 对 diagnostics 中的 conflict 逐个回到 Fixture 判断：是 Parser 粒度错误、canonicalization 错误，还是确实存在来源冲突。

退出条件：所有已知 Fixture 的节点顺序、重复保留和补全位置均符合预期，且没有依赖正文模糊相似度。

#### 阶段 4：切换权威并删除旧启发式链路

- `NGAThreadDetailMerger` 只负责楼层/元数据配对，并调用 Block Merger 合并同楼层内容。
- 删除 `contentUnits`、字符串 `normalized` 和按行 `contentUnitKey`。
- 合并文档保留两份 representation；`blocks` 成为最终权威。
- 更新 ADR-010、`docs/context.md`、`CONTEXT.md`、模块文档与 changelog。

退出条件：相关单测、完整测试、真机构建和人工长帖/图片/GIF/引用验证通过；`git diff` 无临时 diagnostics 或敏感正文。

#### 阶段 5：按真实缺口扩展节点

- 与 `docs/todo.md` 的 SD-4.1/SD-4.2 对齐。
- link、code、list、table 每次只增加一种；同步 Parser、指纹、原生渲染、长图和文本降级测试。
- Merger 主算法原则上不随节点种类增加而改变。

### Success Criteria

- 新内容格式通常只修改对应 Parser、节点定义和 Renderer，不修改 Merger 流程。
- 同一张绝对/相对 NGA 图片可精确合并；合法重复图片保持重复。
- Web-only Block 能插入原始相对位置，而不是统一追加到正文末尾。
- 未知节点不会导致已知内容丢失，原始 API/Web markup 均可追溯。
- `normalizedText`、`body`、截图与原生阅读器都来自同一最终 Block 数组。
- 合并冲突可由 diagnostics 与 Fixture 重现，不依赖线上遇到后临时追加字符串规则。
- NGA 的楼层身份、分页和回复顺序仍由 API/现有 Repository 语义控制，共享 View 不感知 API/Web 双来源。

### Open Questions

1. 当同一锚点 gap 中 API 与 Web 都有不相同的大段文本时，产品更偏向“Web 优先且记录冲突”，还是“两个版本都展示以绝不丢内容”？推荐前者，但需要用真实 Fixture 验证 Web 的可靠性。
2. `ForumPostDocument` 是否现在就升级为多 `representations`，还是先把它作为 NGA 适配层内部类型？推荐分两步，先内部验证，再做共享模型迁移。
3. 第一阶段 text Block 的最小粒度是段落还是 inline run？推荐段落；inline 富文本 run 等 link/code 的真实 Fixture 证明需求后再引入。
4. HTML Block Parser 是否允许引入成熟 HTML parser 依赖？若不允许，需要评估现有手写 extractor 扩展为内容 parser 的维护成本；这个决定会显著影响实现风险。
5. merged Block 是否需要保存每个节点的 provenance 供调试/网页保真切换使用？推荐至少在内部 merge result 中保留，是否进入领域模型可后置。
