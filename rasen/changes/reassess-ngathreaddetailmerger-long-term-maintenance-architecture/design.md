## Context

当前 NGA 详情链路先请求 API，再无条件请求 Web；两个来源分别通过 `structuredForumText` 变成 `normalizedText`，随后由 `NGAThreadDetailMerger` 执行全文包含、按行拆分、图片 URL 特例和全局 Set 去重。最终 View、长图和图片扫描再次从 `normalizedText` 解析 `ForumContentBlock`。

该设计把阅读文本同时当作来源协议、合并协议和渲染输入，造成三类结构性问题：

- Parser 在合并前丢失语法树、节点边界、来源和置信度；
- Merger 无法区分合法重复与跨来源重复，也无法保持 Web 补充内容的原始位置；
- `rawMarkup` 可能来自 Web，而 `normalizedText` 同时包含 API/Web 内容，文档无法追溯。

Office Hours 评估比较了 API-only、条件式 Web fallback、双来源语义协调、Web 权威和完整 Plugin Engine。随后对真实帖子 `47185513` 的 API/Web 响应进行审计：两边均包含 0～11 楼、两张图片、三个表情和引用内容，API 仅在图片绝对/相对 URL、粗体表示和引用后换行上与 Web 不同。该样本不需要正文补全；项目现有成对 Fixture 可以证明当前 Merger 的测试行为，但不能证明线上 API 经常丢失正文。

本 change 因而选择“API-first + 条件式整份 Web fallback”，并建立共享语义内容文档。双来源节点协调只有在未来真实样本证明两边经常各有不可替代内容时才另行设计。

## Goals / Non-Goals

**Goals:**

- 让语义内容文档成为原生阅读、图片扫描、长图、分享和纯文本投影的唯一内容输入。
- 保留每份来源原始标记、格式、来源 URL、Schema 版本和 Parser 诊断，以便追溯和重新解析。
- 把 NGA 的来源获取策略、来源 Parser、领域组装和内容投影拆成独立职责。
- API 内容有效时只请求 API；仅在 API 内容不可用或出现明确 fatal 解析诊断时请求 Web。
- Web fallback 选择同楼层的整份语义文档，不拼接字符串，也不创建 API 未确认的回复楼层。
- 修正 API 根级 `tsubject`、`tauthor`、分页和附件元数据映射，让 Web 不再替 API Parser 补偿字段遗漏。
- 用真实形状 Fixture 和可执行 contract 保护重复节点、顺序、未知标签、引用、媒体和降级行为。

**Non-Goals:**

- 不建设运行时动态 Plugin 平台；核心节点继续使用 Swift 静态类型和穷尽 switch。
- 不在本 change 中实现 API/Web 双来源 Semantic Reconciler。
- 不追求第一阶段覆盖所有 BBCode/HTML 标签；未知内容必须安全保留和降级。
- 不改变 NGA 的远端分页顺序、回复提交、登录或 Cookie 合约。
- 不把 Web DOM、BBCode AST、NGA DTO 或 Parser 诊断暴露给 SwiftUI View。
- 不保留旧字符串 Merger 的输出兼容性；迁移以语义正确性和 Fixture 为准。

## Decisions

### 1. 使用三层内容模型，而不是继续扩展 `normalizedText`

内容分为三层：

```text
Source Representation
    raw markup + origin + format + source URL + schema version
            ↓
Parser-private Syntax Tree
    BBCode AST 或 HTML DOM subtree
            ↓
Semantic Content Document
    blocks + diagnostics + selected representation/provenance
```

目标领域模型概念如下：

```text
ForumPostDocument
├─ representations: [ForumContentRepresentation]
├─ blocks: [ForumContentBlock]
├─ diagnostics: [ForumContentDiagnostic]
└─ schemaVersion

ForumContentBlock
├─ paragraph([ForumInlineContent])
├─ image(ForumContentResource, attributes)
├─ quote(metadata, [ForumContentBlock])
├─ list(items)
├─ code(language, text)
├─ table(rows)
├─ divider
└─ unsupported(rawFragment, fallbackText)

ForumInlineContent
├─ text
├─ link
├─ emphasis
├─ emoji(resource, accessibilityLabel)
└─ unsupported
```

第一实现切片只需交付现有用户路径需要的 paragraph/text、image、quote、emoji 和 unsupported；link、list、code、table 按真实 Fixture 扩展，但 Schema 预留清晰边界。

`body` 与 `normalizedText` 不再存储，也不进入 Parser 或来源策略；它们由 `ForumContentPlainTextProjector` 从 blocks 计算。

**替代方案：**只给现有 `ForumPostDocument` 增加 `blocks`，继续保留单一 raw/normalized 字段。该方案迁移较小，但仍无法表示 API/Web 两份来源或保证 raw 与 projection 一致，因此不采用。

### 2. Syntax AST 仅存在于来源 Parser 内部

NGA API 的 BBCode 使用 tokenizer + 容错 AST；Web 的 `postcontent<floor>` 先由精确 DOM/节点提取器定位，再降为相同语义节点。Parser 输出：

```text
ContentParseResult
├─ document blocks
├─ diagnostics
└─ quality: valid | degraded | unusable
```

诊断至少区分：未知标签、畸形闭合、已安全降级、已丢弃不安全属性和 fatal 内容缺失。未知但可显示的内容为 `degraded`，不能触发 Web；只有无法形成安全正文或已知媒体/结构被确定丢失时才是 `unusable`。

**替代方案：**直接合并 BBCode AST 与 HTML DOM。两棵树表达不同语法，比较规则会重新耦合来源细节，因此不采用。

### 3. API-first Acquisition Strategy 负责来源选择

Repository 调用顺序：

```text
Fetch API
  ↓
Map root metadata + posts
  ↓
Parse API source documents
  ↓
Validate
  ├─ valid/degraded → assemble and return; do not fetch Web
  └─ unusable       → fetch and parse Web
                         ├─ valid/degraded → replace affected content document
                         └─ unusable       → surface API/Web failure
```

当 API 请求完全失败时，可以尝试 Web 作为可读降级，但 Web 不得伪造 `pid`、作者或时间。仅能确认 `tid`、DOM floor 和正文的字段被返回，其余元数据显式缺失或使用领域层已有的安全 placeholder。

API 与 Web 都存在时：

- API 根级与逐帖字段是身份和元数据权威；
- Web 只提供被判定为 unusable 的同楼层 content document；
- Web-only 回复不加入 API 回复集合；
- API 顺序、分页和楼层不被 Web 重排。

**替代方案：**每次并行或串行请求两边再比较。真实样本没有证明收益，且增加延迟、限流、Cookie 和失败状态，不采用。

### 4. 删除启发式合并，fallback 采用整份选择

本 change 删除以下正文语义：

- 全文 `contains` 判断；
- 按换行拆分 content unit；
- 删除全部空白并小写化的文本等价；
- 全局 Set 去重；
- 把 Web 缺失行追加到 API 末尾；
- 用单一 Web `rawMarkup` 表示 API/Web 拼接结果。

同楼层 API content unusable 且 Web content valid 时，选择整份 Web semantic document；API 文档仍作为 representation/provenance 保留，但不和 Web blocks 自动拼接。

如果两份文档都有效但不同，默认继续使用 API 并产生非敏感 conflict diagnostic。未来只有在脱敏真实 Fixture 证明必须保留双方独有内容时，另建 change 设计 sequence-aware Semantic Reconciler。

**替代方案：**把按行 Merger 替换为 LCS Block Merger。它比字符串安全，但当前没有业务证据证明需要双来源合并，因此暂不承担该复杂度。

### 5. Domain 内容节点保持来源中立

共享 Domain 不再持有 `NGAForumSmile`。NGA Parser 把 `[s:...]` 映射为通用 emoji resource；其他来源可以映射自身 emoji，而 Feature 只消费 URL、替代文本和展示属性。

节点 display identity 与内容相等/来源匹配分离：重复的相同文本或图片必须拥有不同 occurrence identity，不能用 payload hash 或 URL 作为全局唯一 ID。

**替代方案：**为每个数据源维护独立 View。它会复制图片、引用、长图和无障碍行为，破坏多数据源架构，因此不采用。

### 6. 所有消费者使用 Projector

- SwiftUI：直接渲染 semantic blocks；
- 图片扫描：遍历 image/emoji resource；
- 长图：使用同一 block renderer；
- 分享与 `body`：使用 plain-text projector；
- 分页重复签名：使用显式内容签名 projector，不复用用户显示文本；
- 无障碍：使用 accessibility projector 或节点替代文本。

Projector 不读取 raw markup，也不执行来源 Parser。

### 7. 使用有限 Handler Registry，不建设完整 Plugin Engine

BBCode/HTML Parser 内部可以为标签使用静态 handler table，使 image、quote、emoji 等语法处理可单测；语义节点仍由 Swift enum 定义。新增节点需要显式更新 Parser、Renderer、PlainText、Snapshot 和测试，编译器应帮助发现遗漏。

动态加载 Plugin、运行时节点类型擦除和第三方扩展不在范围内。

### 8. 证据和隐私作为来源策略的设计约束

Fixture 仅保存脱敏最小响应；不得包含 Cookie、Token、guest token、真实可识别用户名或完整私人正文。Diagnostics 和 Release 日志不得记录 raw markup 或正文，只能记录来源、楼层、Parser 版本和诊断代码。

是否引入 Reconciler 的证据门：至少存在两组脱敏真实成对 Fixture，能够证明同一楼层中 API 与 Web 分别含有不可替代、非解析器缺陷造成的内容，并且整份 fallback 会丢失用户可见信息。

## Risks / Trade-offs

- [语义模型迁移面大，涉及 Domain、三个数据源和多个 Renderer] → 先建立 projector contract，再逐消费者切换；每个阶段保持可构建并运行完整测试。
- [第一阶段 Parser 不能覆盖所有 BBCode/HTML] → Unknown-first；保留 raw fragment 和安全 fallback，禁止静默删除。
- [API 被误判为 valid，真实缺失内容未触发 Web] → 质量状态只基于可证明信号，并持续补充真实成对 Fixture；提供查看网页原文降级。
- [API 被误判为 unusable，造成额外 Web 请求] → `degraded` 不触发 Web；只有 fatal 诊断触发，并用请求计数测试约束。
- [整份 Web fallback 可能放弃 API 中独有内容] → 两份 representation 均保留并产生 conflict diagnostic；真实证据达到门槛后再设计 Reconciler。
- [Web DOM 变化导致 fallback 失效] → API 正常路径不依赖 Web；Web Parser 与权限错误使用独立 Fixture。
- [重复节点 identity 不稳定导致 SwiftUI 重建] → display ID 基于文档内 occurrence path，而不是数组临时下标或 payload 去重键，并增加刷新稳定性测试。
- [新的 Parser 或 HTML 库增加二进制/供应链成本] → 第一阶段优先使用 Foundation 与现有精确节点提取；若真实畸形 HTML 证明不足，再以 ADR 评估依赖。

## Migration Plan

1. **建立证据基线**：补齐真实成对 Fixture、重复段落/图片、顺序、未知标签和来源失败矩阵；记录当前线上样本结论。
2. **引入语义 Content Core**：新增来源中立 blocks、representations、diagnostics 和 projectors，先用现有三数据源数据构造，不切换获取策略。
3. **实现 NGA BBCode/HTML Parser contract**：直接从 raw markup 生成 semantic blocks；Parser 测试与来源选择测试分离。
4. **迁移消费者**：详情、长图、图片扫描、分享和分页签名依次改用 projectors；删除 View 中的 `ForumContentParser.parse(normalizedText)`。
5. **切换 API-first Strategy**：修正根级 API 字段映射，接入 quality result；验证正常详情只请求 API，明确失败才请求 Web。
6. **删除字符串 Merger**：移除 `NGAThreadDetailMerger.mergedDocument`、按行规则和旧字符串 Parser 权威路径。
7. **文档与真机验收**：更新 ADR-010、上下文、模块文档、todo/changelog；在连接真机上构建、运行相关及完整测试，并人工验证普通、图片、GIF、引用、长帖和 Web fallback。

回滚以阶段边界为单位：在第 5 步切换前保留旧获取入口但不扩展其规则；切换后若出现阻断性回归，回退到前一阶段已验证的 API 文档渲染路径，而不是恢复新的启发式规则。原始 representations 使 Parser/Renderer 可以回滚而不丢来源数据。

## Open Questions

- 真实样本审计应以多少帖子、哪些板块作为 API 完整率的发布门槛？建议至少覆盖普通文本、长帖、图片、引用、附件、表格/代码和分页帖子共 20 个样本。
- API 完全失败而 Web 可读时，产品是否接受作者/时间缺失的只读降级，还是应直接展示错误并提供“查看网页原文”？实现前需由产品验收场景确定。
- 离线详情缓存若进入近期路线图，是否保存 raw representations 以支持 Parser 升级后重放？当前 change 保留模型能力，但不新增缓存。
