## Why

`NGAThreadDetailMerger` 当前把 API BBCode 与 Web HTML 过早压平为 `normalizedText`，再以全文包含、按行拆分和全局去重猜测内容关系，导致结构、顺序、合法重复和来源信息无法可靠维护。Office Hours 评估与真实帖子 `47185513` 的 API/Web 审计进一步表明：普通详情的 API 已可完整承载正文，现有无条件 Web 请求和通用文本合并缺少足够数据依据，应在继续增加规则前重建内容边界与来源策略。

## What Changes

- 引入共享的语义内容文档，直接表达段落、图片、表情、引用、链接及未知内容，并保留来源原始标记和解析诊断。
- 让 NGA API 与 Web 使用各自的来源 Parser，将原始文档转换为同一语义内容模型；AST/DOM 仅作为 Parser 内部表示，不泄漏到 Feature。
- 将 NGA 详情获取改为 API-first：API 内容有效时直接返回，只有 API 正文不可用或满足可验证的结构化降级条件时才请求 Web。
- Web 降级采用同楼层整份语义文档替换，不再对 `normalizedText` 做启发式并集。
- API 继续作为帖子身份、作者、时间、楼层、分页、回复顺序和附件元数据的权威来源；Web 不创建或重排 API 未确认的回复楼层。
- 详情渲染、长图、图片扫描、分享和文本预览统一从语义内容文档派生，避免各消费者重复解析字符串。
- 建立脱敏 API/Web 成对 Fixture、Parser contract、来源选择策略和内容投影测试，并用证据门决定未来是否另行引入双来源 Semantic Reconciler。
- **BREAKING**：移除 `NGAThreadDetailMerger` 的字符串正文合并语义；`normalizedText`/`body` 只保留为语义内容文档的只读文本投影，不再是 Parser 或 Merger 的权威输入。
- **BREAKING**：共享内容节点不再直接依赖 `NGAForumSmile` 等 NGA 专用类型，NGA 资源映射下沉到 NGA Parser。

## Capabilities

### New Capabilities

- `semantic-forum-content`: 定义跨数据源的语义内容文档、来源表示、未知内容降级、解析诊断以及原生/纯文本/截图等统一投影行为。
- `nga-thread-content-source-policy`: 定义 NGA 详情的 API 权威字段、API-first 获取、结构化质量判断、条件式 Web 整份降级和禁止启发式文本合并的行为。

### Modified Capabilities

无。当前 `rasen/specs/` 没有既有 capability spec；本 change 将新增上述两个能力。

## Impact

- 领域层：`ForumPostDocument`、`ForumContentBlock`、正文兼容投影和来源表示。
- NGA 数据层：`NGALiveThreadRepository`、`ThreadDetailParser`、`WebForumParser`、`ParserSupport`、`NGAThreadParseQuality`、`NGAThreadDetailMerger`。
- Feature：详情富内容渲染、长图渲染、图片扫描、分享/引用预览与分页重复识别。
- 测试：NGA API/Web Fixtures、Parser contract、来源策略、重复节点、顺序、未知标记和降级矩阵。
- 文档：ADR-010、领域上下文、NGA/Thread Detail 模块说明、待办与 changelog。
- 不在本 change 中引入通用动态 Plugin 平台或双来源节点 Reconciler；只有新增真实样本证明 API/Web 经常各自持有不可替代内容时，才另建 change 评估。
