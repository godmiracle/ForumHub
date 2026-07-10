# Prompt Log

记录和 AI 沟通中值得长期保留的关键提示词、任务描述和结论摘要。

## 常用启动提示

```txt
请先阅读 README.md、AGENTS.md、docs/context.md、CONTEXT.md、docs/architecture.md、docs/decisions.md、docs/todo.md，
理解项目后再开始修改代码。完成后请更新 docs/decisions.md、docs/todo.md，如有必要新增 docs/sessions/YYYY-MM-DD.md。所有说明和总结默认使用简体中文。
```


## 项目 Review 提示

```txt
请先阅读 README.md、AGENTS.md、docs/context.md、CONTEXT.md、docs/architecture.md、docs/decisions.md、docs/todo.md 和 docs/review.md。
按 docs/review.md 对当前改动进行 Review。所有分析、问题、待办和总结使用简体中文。
每个问题必须包含唯一编号、优先级、可信度、涉及文件、证据、影响、建议和验收标准。
将可执行问题同步到 docs/todo.md；只有代码已修改、验收标准满足并完成必要验证后，才能将对应待办自动勾选。
无法验证时保持未完成，并标记“已修改，等待验证”或“等待人工验证”。
```

## Session Summary Template

```md
## YYYY-MM-DD

### User Request

用户想做什么？

### AI Plan

AI 准备怎么做？

### Important Discussion

关键沟通细节。

### Final Result

最终完成什么？

### Follow-up

后续要做什么？
```
