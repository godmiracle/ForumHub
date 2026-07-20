## Why

当前 NGA 回复编辑器以嵌套 Sheet 展示表情，输入区、工具栏和表情选择之间的层级割裂，视觉上也没有充分复用 ForumHub 的纸张主题与玻璃控件语言。表情目录同时只暴露 NG娘、AC娘 v1、AC娘 v2 三组，且目录生成、编辑器恢复和阅读解析分散，无法完整承载已确认的潘斯特、外域和企鹅资源。

## What Changes

- 将回复编辑器重设计为一个稳定的回复面板，在同一上下文内切换键盘输入与表情浏览，避免回复 Sheet 上再次叠加表情 Sheet。
- 保持回复目标、正文、附件、工具栏、字数和发布动作的清晰层级，并复用 `PaperTheme` 与 `ForumGlass` 视觉原语。
- 用可横向浏览的分类导航承载六组 NGA 表情：NG娘、AC娘 v1、AC娘 v2、潘斯特、外域、企鹅。
- 将用户确认的资源区间纳入目录：`pt00...pt64`、`dt01...dt33`、`pg01...pg15`，保留各组真实的起始编号与两位补零格式。
- 统一回复选择、富文本插入、文档恢复和提交序列化所依赖的表情目录，确保新增三组不会在编辑过程中退化或丢失。
- 移除开发阶段说明文案，使连续选择行为与界面反馈一致，并为加载失败、空正文、提交中和附件上限保留明确状态。
- 增加目录边界、插入位置、序列化往返和主要回复面板状态的聚焦测试。

## Capabilities

### New Capabilities

- `reply-composer-experience`: 定义与 ForumHub 现有视觉语言一致的单面板回复编辑、工具模式切换、附件和发布状态行为。
- `nga-reply-emoji-catalog`: 定义六组 NGA 回复表情的目录范围、分类导航、富文本插入与可逆提交序列化行为。

### Modified Capabilities

无。

## Impact

- 主要影响 `ForumHub/Features/ThreadDetail/ThreadDetailReplyComposer.swift` 及其回复状态、富文本编辑器和测试。
- NGA 表情目录可能需要从 Feature 文件迁移到可被回复编辑与 NGA 内容解析共同复用的来源适配边界，但不改变其他数据源的回复能力声明。
- 不新增第三方依赖，不改变 NGA 图片上传与回复提交端点，不为 V2EX 或 LINUX DO 宣称新的原生回复能力。
- 用户可见行为发生变化，实施并验证后需要同步 `docs/modules/thread-detail.md`、`docs/modules/nga.md`、`docs/changelog.md` 与受影响待办。
