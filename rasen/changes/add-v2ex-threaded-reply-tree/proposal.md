## Why

V2EX 官方回复数据只提供按时间排列的线性回复，但回复正文通常通过 `@username` 和可选的 `#floor` 表达上下文；ForumHub 当前在标准化正文后丢失这层关系，长对话难以追踪。真实主题 `1227563` 已证明公开 API 的原始回复内容足以在移动端推断稳定的楼中楼结构，无需引入脆弱的 Web 页面解析。

## What Changes

- 在 V2EX 适配层从 API 原始回复正文提取用户名提及和楼层引用，在正文被 HTML 清理或纯文本投影前保留引用证据。
- 引入确定性的 V2EX 回复关系解析：优先采用作者与楼层一致的显式引用；仅有单一用户名提及时，回溯最近的前序同名回复；歧义或无法验证的引用保持为根回复。
- 将父子关系、解析方式和置信信息建模为派生展示数据，不修改原始 `Reply` 正文、不复制回复，也不改变 Repository 返回的线性顺序。
- 在 V2EX 帖子详情提供移动端楼中楼展示，并保留平铺阅读方式；树形展示限制视觉缩进，确保深层对话仍有可读正文宽度。
- 树形模式只在确认引用前缀对应已解析父节点时做视觉省略；分享、无障碍和底层内容文档继续保留完整正文。
- 增加来自真实主题形状的脱敏 Fixture，以及引用提取、关系解析、歧义降级、树构建和详情展示的测试。
- 不增加 V2EX Web fallback，不实现发帖、感谢、隐藏或其他需要网页会话的交互。

## Capabilities

### New Capabilities

- `v2ex-threaded-replies`: 从 V2EX API 原始回复构建可解释、可降级的回复关系，并在帖子详情中以适合手机宽度的楼中楼形式展示。

### Modified Capabilities

无。

## Impact

- 数据适配：`ForumHub/Data/V2EX/V2EXThreadRepository.swift` 及其 DTO/Mapper 接缝。
- 领域与展示派生模型：`ForumHub/Domain` 或帖子详情专用 presentation model；共享 View 不解析 V2EX 原始文本。
- UI：`ForumHub/Features/ThreadDetail` 的回复组织、树形行、模式切换及与只看楼主/倒序的组合行为。
- 测试与文档：`ForumHubTests`、V2EX Fixtures、V2EX/帖子详情模块文档、能力矩阵、ADR 与 changelog。
- 外部依赖和网络契约不变；继续使用现有 V2EX 公开 API，不请求主题 Web HTML。
