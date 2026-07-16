## Office Hours: 重新评估当前 NGAThreadDetailMerger 的长期维护架构

**Product:** Design
**Date:** 2026-07-16

### Executive Summary

`NGAThreadDetailMerger` 最大的问题不是去重算法不够聪明，而是它被迫修复上游已经丢失的信息。API BBCode 和 Web HTML 在进入合并层之前都被压平为 `normalizedText`；语法结构、节点边界、来源、位置和解析置信度消失后，Merger 只能通过全文包含、按行拆分、空白归一化和图片特例猜测两段文本的关系。

因此，新异常不断增加规则不是实现水平问题，而是架构的必然结果：**有损字符串被错误地当成跨来源内容协议。**

如果项目需要维护 3～5 年，建议废弃“文本归一化 → 文本合并 → 再解析为 Block”的中心链路，改为以下架构：

```text
Acquisition Strategy
    ↓
Raw Source Snapshot
    ↓
Source Parser Pipeline
    ├─ Tokenizer / Syntax AST
    ├─ Semantic Lowering
    └─ Validation + Diagnostics
    ↓
Semantic ContentDocument
    ↓
Optional Source Reconciler
    ↓
Renderer / PlainText Projector / Snapshot Projector
```

推荐的产品策略不是默认双来源：

- 如果真实 Fixture 证明 API 完整可靠，正常路径只使用 API，根本不运行 Web parser 和 reconciler。
- Web 只作为 API 失败或可结构化证明不完整时的降级 observation。
- 即使保留双来源，也不再 merge 文本；两个来源先独立生成语义文档，再由显式 Reconciler 处理。

Pipeline、Strategy、Plugin 和 AST 都有适用位置，但不能让任何一个概念吞掉整个系统：

- Strategy：来源选择和降级政策；
- Pipeline：阶段编排和可观测性；
- AST：BBCode/HTML parser 内部语法结构；
- Semantic Content Model：跨来源稳定领域协议；
- Plugin/Registry：扩展标签、节点投影和渲染能力；
- Reconciler：仅在确实需要双来源时工作。

### Idea Overview

本次评估不以修复某个异常为目标，也不要求兼容现有 `ForumPostDocument` 或 `normalizedText`。目标是定义一个能承受 NGA 标记变化、内容节点扩展、API/Web 来源变化和多个渲染消费者的长期边界。

判断架构是否成功的标准是：未来遇到一种新正文格式时，改动应落在对应来源 parser 或新节点 handler 中，而不是同时修改字符串清洗、Merger、图片扫描、详情 View 和长图渲染。

### Key Findings / Design Decisions

#### 1. 当前设计最大的维护问题：有损中间态承担了过多职责

当前核心链路近似为：

```text
API rawContent ─┐
                ├─ structuredForumText ─> normalizedText ─> 文本 Merger ─> ForumContentParser ─> UI
Web innerHTML ──┘
```

`normalizedText` 同时承担了至少六种不兼容职责：

1. 用户可读纯文本；
2. 富内容的临时标记载体；
3. API/Web 跨来源比较协议；
4. 图片、表情和引用的解析输入；
5. 分页重复判断和正文完整度判断输入；
6. `body`、预览、截图等兼容投影。

一个字符串无法同时忠实表达语法树、语义节点、来源差异和用户显示文本。任何为了一个消费者加入的转换，都可能破坏另一个消费者的假设。

更严重的是，`ForumPostDocument.rawMarkup` 只能表示一个来源，而合并后的 `normalizedText` 可能来自 API 和 Web 两边。此时 raw 与 projection 不再对应同一事实，文档的“权威来源”语义是自相矛盾的。

#### 2. 耦合最高的模块

##### 2.1 `structuredForumText`：隐形的系统总线

它同时理解 HTML、BBCode、引用、图片、实体、换行和未知标签清理。API Parser、Web Parser 和 `ForumPostDocument` 都依赖它。任何规则修改都会影响两种来源和所有下游消费者，是当前最高风险的变化点。

##### 2.2 `normalizedText`：跨层共享状态

Domain、NGA Repository、Merger、详情渲染、长图、图片扫描、分页去重和预览都消费它。它名义上是阅读投影，实际上已经成为系统内部协议。

##### 2.3 `NGAThreadDetailMerger`：内容、来源和领域组装混合

它同时负责：

- API/Web 可用性选择；
- Thread 元数据回退；
- 按楼层配对回复；
- 正文内容比较与去重；
- 原始文档格式选择；
- 最终 `ForumThread` 重建。

这些职责有不同变化原因，却被放在一个类型里。来源策略、领域组装和内容 reconciliation 无法独立测试或替换。

##### 2.4 `ForumContentParser` 与 UI：重复解析耦合

`ForumPostDocument` 已经存在，但 UI、长图和图片扫描仍要从 `normalizedText` 再解析成 `ForumContentBlock`。这意味着 Domain 保存的不是最终语义，而是另一份需要二次解释的中间文本。

##### 2.5 共享 Domain 对 NGA 细节的反向依赖

`ForumContentBlock.Content.smile` 直接持有 `NGAForumSmile`。共享内容模型因此知道 NGA 资源规则，使其他数据源复用和独立演进变困难。

##### 2.6 测试对字符串结果的耦合

大量测试以 `body.contains`、拼接后的整段字符串或图片数量验证结果。它们能保护当前输出，却不能证明结构、顺序、重复节点和来源 provenance 正确，也会迫使未来实现继续模拟旧字符串行为。

#### 3. 为什么新正文异常必然继续增加规则

原因不是 NGA 格式“特别脏”这么简单，而是当前流程存在五类不可逆损失：

1. **语法丢失**：`[quote]`、`[img]`、HTML element 和普通文字被压到同一字符串空间。
2. **边界丢失**：换行既可能是段落、布局、标签转换结果，也可能只是来源格式差异。
3. **顺序语义丢失**：集合式去重无法区分“重复出现”和“重复来源”。
4. **来源丢失**：无法回答某个片段来自 API、Web，还是两者一致。
5. **置信度丢失**：parser 无法把“明确解析”“未知标签降级”“疑似截断”传给策略层。

于是每个新异常都会表现为新的字符串表象：多一个换行、另一种图片地址、嵌套标签、尺寸参数、引用包装、实体差异或相似但不相同的段落。Merger 只能继续扩充 normalization 和特例。

只要 merger 输入仍是有损字符串，这个趋势不会停止；换成更复杂的正则、相似度或机器学习只会让错误更难解释。

#### 4. 更好的数据模型：Observation、Syntax 与 Semantic 分离

建议完全重建内容模型，分为三层。

##### 4.1 Raw Source Observation

表示一次来源事实，不参与 UI：

```text
PostObservation
├─ source: ngaAPI | ngaWeb
├─ postIdentity / floorIdentity
├─ rawPayload
├─ mediaType / markupDialect
├─ fetchedAt
├─ transportMetadata
└─ schemaVersion
```

API 和 Web 是两个 observation，不需要伪装成一份 merged raw document。

##### 4.2 Source Syntax Document

Parser 内部表示，不进入共享 Feature：

```text
BBCodeSyntaxTree
├─ tag(name, attributes, children)
├─ text
└─ malformed(raw, recovery)

HTMLSyntaxTree / DOM Subtree
├─ element(name, attributes, children)
├─ text
└─ malformed(raw, recovery)
```

AST 的价值是正确处理嵌套、属性、转义和错误恢复；不应该直接拿 BBCode AST 和 HTML AST 做合并，因为它们描述的是不同语法。

##### 4.3 Semantic Content Document

这是 Domain 与 Feature 的稳定协议：

```text
ContentDocument
├─ blocks
│  ├─ paragraph(inlines)
│  ├─ quote(metadata, blocks)
│  ├─ image(resource, attributes)
│  ├─ list(items)
│  ├─ code(language, text)
│  ├─ table(rows)
│  ├─ divider
│  └─ unsupported(sourceFragment, fallback)
├─ provenance
├─ diagnostics
└─ contentSchemaVersion
```

Inline 层独立表达 text、link、emphasis、emoji、mention 等。NGA smile 在这里是通用 `emoji(resource:)`，NGA 文件名映射只存在于 NGA parser/plugin。

`plainText`、分享文本和辅助功能文本是 projector 输出，不再存为领域权威。图片列表、截图和 SwiftUI 渲染直接遍历同一语义文档。

#### 5. 多种可选架构方案

##### 方案 A：API-only Semantic Pipeline

```text
NGA API → DTO → BBCode AST → Semantic ContentDocument → Renderer
```

网页只通过系统浏览器/WebView提供“查看原文”，不进入原生内容链路。

优点：

- 架构最简单，没有跨来源一致性问题；
- 网络请求、Cookie、失败模式和测试矩阵最少；
- API 的楼层身份、元数据和正文天然同源；
- 长期维护成本最低。

缺点：

- API 真实截断或缺字段时无法原生补全；
- API 协议变化会成为单点风险；
- 必须先以真实样本证明 API 内容完整性。

适用条件：API 在目标帖子类型中的完整率足够高，缺失可接受或可通过“查看原文”降级。

长期评价：**若数据证明可行，这是首选，不应为了理论完美保留双来源。**

##### 方案 B：API Primary + Conditional Web Fallback

```text
API Pipeline → Content Validator
                   ├─ valid → return
                   └─ structurally incomplete → Web Pipeline → choose/fallback
```

注意这里默认是“选择一份语义文档”，而不是合并两份正文。只有 API 明确失败或结构化不完整时才使用 Web。

优点：

- 正常路径接近方案 A；
- 保留对 API 缺失的恢复能力；
- 不需要普遍解决双来源节点对齐问题；
- 来源选择可以通过 Strategy 独立测试。

缺点：

- 需要可靠、保守的完整度信号；
- Web parser 仍需维护；
- API 与 Web 内容略有差异时可能出现整份切换。

适用条件：API 缺失客观存在，但通常可以判断，而且 Web 能提供完整替代文档。

长期评价：**风险和维护成本最均衡，是当前证据不足时的默认推荐。**

##### 方案 C：Dual Observation + Semantic Reconciliation

```text
API Observation → API Pipeline ─┐
                                ├─ Semantic Reconciler → Resolved ContentDocument
Web Observation → Web Pipeline ─┘
```

Reconciler 基于节点类型、稳定身份、序列锚点、provenance 和显式冲突政策工作。无法证明相同的节点不静默去重；冲突可保留 alternative 或按策略选取，并产生 diagnostics。

优点：

- 能表达两个来源互相补充的真实情况；
- 不丢来源，可审计、可重放；
- 新语法变化主要局限在各自 parser；
- 适合未来增加缓存、离线重解析和质量统计。

缺点：

- 状态空间和测试矩阵最大；
- “相同语义节点”的定义仍是领域策略，不可能完全消除；
- 重复段落、内容编辑和来源时序差异需要明确冲突模型；
- 如果 API 实际已足够完整，这是昂贵的过度设计。

适用条件：真实数据证明 API 和 Web 经常各自持有不可替代内容，而且整份 fallback 不能满足需求。

长期评价：**能力最强，但必须由数据触发，不能仅因为当前已有 Merger 就继续投资。**

##### 方案 D：Web Document Authoritative + Native Metadata

```text
API → identity / author / paging metadata
Web → authoritative content document → HTML semantic parser or constrained Web renderer
```

优点：

- 避免正文双来源 reconciliation；
- 网页通常更接近用户看到的最终内容；
- 对复杂 HTML 可选择成熟 DOM parser 或受控 WebView。

缺点：

- Web 结构、登录态、反爬和页面改版通常比 API 更不稳定；
- 每页双请求或 Web-only 请求增加延迟；
- HTML 安全、资源加载、Cookie 和隐私边界更复杂；
- 原生排版与网页保真之间仍需选择。

适用条件：API 正文明显不可信，而 Web 页面长期稳定且可合法可靠获取。

长期评价：**不建议作为默认方案，可作为特定内容类型的策略。**

##### 方案 E：可插拔 Content Engine

把 tokenizer、tag handler、semantic lowering、validator、projector 和 renderer 都注册为 Plugin：

```text
ContentEngine
├─ DialectPlugin: ngaBBCode / ngaHTML / markdown
├─ NodePlugin: image / quote / emoji / code / table
├─ ValidationPlugin
└─ ProjectionPlugin: SwiftUI / plainText / snapshot
```

优点：

- 扩展边界清晰，适合多个复杂内容方言；
- 新节点可以独立注册与测试；
- ContentCore 可与 NGA adapter 解耦。

缺点：

- Swift 静态类型下过度动态注册会削弱穷尽性检查；
- 调试调用链变长；
- 当前只有少数来源时，完整插件平台成本过高；
- Plugin 不能解决错误的数据模型，只会把错误拆散。

适用条件：多个数据源都需要持续扩展富内容方言，且节点扩展频率已经证明固定 switch 难以维护。

长期评价：**应采用“有限 Registry/Handler 扩展点”，不建议一开始建设通用插件平台。**

#### 6. 方案比较

| 方案 | 正常路径复杂度 | 内容完整性 | 维护成本 | 可解释性 | 推荐条件 |
| --- | ---: | ---: | ---: | ---: | --- |
| A API-only Pipeline | 最低 | 取决于 API | 最低 | 高 | API 完整率已证明 |
| B API + 条件式 Web fallback | 低 | 高 | 中低 | 高 | 偶发、可检测缺失 |
| C 双 Observation 语义协调 | 高 | 最高潜力 | 高 | 高 | 两源经常互补且不可替代 |
| D Web 正文权威 | 中 | 取决于 Web | 中高 | 中 | API 正文长期不可信 |
| E 全插件 Content Engine | 很高 | 与 parser 有关 | 初期最高 | 中 | 多方言、高频扩展已出现 |

当前推荐顺序：**A 经数据验证后优先；否则 B；只有证据证明“必须拼两份内容”时才进入 C。D 是特殊策略，E 只取有限扩展机制。**

#### 7. Pipeline、Strategy、AST、Plugin 的正确组合

推荐组合不是某个设计模式主导，而是明确变化轴：

##### Acquisition Strategy

负责来源政策，不接触正文语法：

- `APIOnlyStrategy`
- `APIPrimaryFallbackStrategy`
- `WebAuthoritativeStrategy`
- `DualObservationStrategy`

选择 Strategy 应由配置、内容类型或经过验证的质量信号决定，不由 View 决定。

##### Parse Pipeline

每个来源固定阶段：

```text
Decode → Tokenize → Build Syntax Tree → Lower to Semantic Nodes → Validate
```

每阶段返回 typed result 与 diagnostics，不通过全局字符串 extension 隐式串联。

##### Syntax AST

AST 用于正确处理嵌套和错误恢复。BBCode AST 与 HTML DOM 都只存在于 Data/NGA 或 ContentParsing 层，不能泄漏给共享 UI。

##### Semantic Model

Semantic `ContentDocument` 是唯一跨层协议。Renderer 不知道来源是 API、Web、BBCode 还是 HTML。

##### Limited Plugin Registry

允许 parser 为 tag 注册 handler、renderer 为 semantic node 注册受控能力，但核心节点仍优先使用 Swift enum 保留穷尽性检查。未知标签统一成为 `.unsupported`，保留 raw fragment 和安全 fallback。

##### Optional Reconciler

Reconciler 是独立能力，不属于 Parser，也不属于 Thread Repository。它只接受两个已验证的 semantic document，并返回 resolved document、provenance 和 conflicts。

#### 8. 3～5 年目标架构

建议按以下模块边界重建：

```text
ForumHub/Domain/Content
├─ ContentDocument
├─ BlockNode / InlineNode
├─ ContentResource
├─ ContentProvenance
└─ Projectors

ForumHub/Data/NGA/Transport
├─ NGAAPIClient
├─ NGAWebClient
└─ Raw DTO / Observation

ForumHub/Data/NGA/Acquisition
├─ ThreadAcquisitionStrategy
├─ ContentQualityValidator
└─ ThreadAssembler

ForumHub/Data/NGA/Parsing
├─ BBCodeTokenizer / AST / Lowering
├─ HTMLExtractor / DOM Lowering
├─ TagHandlers
└─ ParserDiagnostics

ForumHub/Data/NGA/Reconciliation
├─ ContentReconciler
├─ NodeMatcher
└─ ConflictPolicy

ForumHub/Features/ThreadDetail/Rendering
├─ SemanticContentView
├─ PlainTextProjector
└─ SnapshotProjector
```

关键依赖方向：

```text
NGA Transport → NGA Parsing → Domain Content ← Feature Rendering
                         ↓
              NGA Acquisition / Reconciliation
```

Domain Content 不依赖 NGA；Feature 不依赖 NGA parser；Parser 不构造完整 `ForumThread`；Repository/Assembler 不解析标记；Renderer 不二次解析字符串。

#### 9. 长期演进约束

1. 原始 observation 不可变，并带 parser/schema 版本，支持离线重解析。
2. Semantic model 版本化；缓存保存 observation 还是 semantic document 必须明确，不混存未标版本的数据。
3. 每个 parser 输出 diagnostics：未知标签、错误恢复、丢弃属性、疑似截断。
4. 完整度判断只使用结构化证据，不使用正文相似度。
5. 所有 projector 消费同一 semantic document，避免详情、分享、长图结果漂移。
6. Unknown-first：遇到未知内容保留 raw fragment 与安全 fallback，不静默删除。
7. Parser 测试、semantic contract 测试、acquisition policy 测试、renderer 测试分层，不用端到端字符串断言覆盖所有责任。
8. Reconciler 必须是可选模块；API-only 模式不应为它付运行时和认知成本。

### Recommended Next Steps

本轮不立即优化或实现。建议先做三个决策实验，再选择 A/B/C，而不是直接开工重构。

#### 决策实验 1：证明是否真的需要 Web

- 从已知异常、普通文本、长帖、图片帖、引用帖、表格/代码帖中建立脱敏样本集。
- 对 API 原始 BBCode 与网页最终正文进行人工标注：完整、截断、格式不同、内容不同。
- 统计 API 完整率、缺失是否可结构化检测、Web 是否稳定可取。

决策门：

- API 足够完整 → 方案 A；
- API 偶发缺失且能可靠检测 → 方案 B；
- 两源经常各有独有内容 → 才考虑方案 C。

#### 决策实验 2：验证 Semantic Model

- 不改生产链路，只用 10～20 个代表性 Fixture 手工定义期望 `ContentDocument`。
- 验证 paragraph/inline、quote、image、emoji、link、unsupported 是否足以表达真实内容。
- 确认 plain text、SwiftUI、长图、图片列表可从同一模型派生。

决策门：模型能表达现有内容，且未知格式可无损降级。

#### 决策实验 3：验证 Parser 技术路线

- 比较手写 BBCode tokenizer、现有 regex 链、成熟 HTML DOM parser 的正确性和错误恢复。
- 使用嵌套、畸形闭合、属性变体、实体和超长内容做压力样本。
- 记录解析时间、内存、diagnostics 和失败模式，不只比较代码行数。

决策门：选择能保留结构并可诊断的 parser，不以“零依赖”作为唯一目标。

#### 正式设计顺序

1. 先形成“是否需要 Web”的产品/数据结论。
2. 再冻结 Semantic Content schema 和 Unknown fallback 规则。
3. 然后选择 Acquisition Strategy。
4. 最后才设计迁移或全量替换任务。

如果进入正式变更，建议用 `/rasen:propose 重新评估当前 NGAThreadDetailMerger 长期维护架构` 生成 proposal、design、specs 和 tasks；若样本结论仍不清楚，继续用 `/rasen:explore` 做数据审计。

### Open Questions

1. 已知 API“不完整”是原始响应确实缺内容，还是当前 `structuredForumText` 在转换中丢内容？这是决定 A 与 B/C 的首要问题。
2. 用户体验上，正文偶发缺失时能否接受“查看网页原文”，还是必须保证原生阅读完整？
3. Web 与 API 内容冲突时，哪个来源具有产品意义上的权威性，而不只是当前代码注释中的权威性？
4. 是否计划增加离线详情缓存？如果会，保存 raw observation 以支持新 parser 重放的价值会显著提高。
5. 富文本目标是“覆盖 NGA 常见内容”还是“接近网页保真”？这决定 Semantic Model 的复杂度上限。
6. 是否允许引入成熟 HTML parser？若禁止外部依赖，需要明确接受自研 DOM/容错解析器的长期成本。
7. V2EX、LINUX DO 是否预计复用同一 Semantic Content Model？如果只是 NGA，有限 enum 足够；如果多来源会持续扩展，应提前设计 dialect adapter，但仍不必建设全动态插件平台。
