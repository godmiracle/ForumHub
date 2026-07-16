# ForumHub Test Fixtures

本目录保存可重复、无账号凭证的响应样本。Fixture 只保留解析所需结构；用户名、帖子 ID、正文和资源地址均已替换为测试值，不得加入 Cookie、Token、Auth 字段或可识别个人信息。

| 文件 | 类型 | 结构来源 | 覆盖目的 |
| --- | --- | --- | --- |
| `post-list.json` | NGA API | 脱敏真实响应形状 | 主楼、回复、用户目录和头像映射 |
| `nga-thread-api-incomplete.json` | NGA API | 基于脱敏真实响应形状裁剪 | 与 Web 样本配对；证明 API/Web 表示可不同，但不能单独证明生产 API 会缺正文 |
| `nga-thread-web-enrichment.html` | NGA Web | 基于脱敏真实 DOM 结构裁剪 | 与 API 样本配对；覆盖精确楼层节点、相对图片地址和 Web 表示解析 |
| `nga-thread-page2-media.json` | NGA API | 人工组合边界，字段形状来自真实续页响应 | 第二页 GIF、转义 URL、引用图片原文和重复主楼 |
| `nga-thread-47185513-shape.json` | NGA API | 依据真实字段与楼层形状脱敏重写 | 0–11 楼、root metadata、两张有序图片、三个表情和引用变体 |
| `nga-bbcode-topic-quote.txt` | NGA API BBCode | 依据真机 2 楼原始显示形状脱敏重写 | `[quote][tid]Topic[/tid]`、HTML 粗体、用户标签、换行及引用后正文 |
| `nga-bbcode-reply-to-header.txt` | NGA API BBCode | 依据真机 18 楼原始显示形状脱敏重写 | 无外层 `[quote]` 的粗体 `Reply to` 头、`pid/uid`、当前回复正文及表情 |
| `nga-bbcode-inline-html-formatting.txt` | NGA API 混合标记 | 依据真机 44 楼原始显示形状脱敏重写 | BBCode 正文中的 `<del class='gray'>` 行内 HTML 容器及后续正文 |
| `nga-thread-api-content-unusable.json` | NGA API | 人工组合失败边界 | API 请求成功但正文 unusable |
| `nga-thread-web-valid-fallback.html` | NGA Web | 人工组合边界，DOM 形状来自真实页面 | API 正文 unusable 时的同楼层整文档回退 |
| `nga-thread-api-unusable-reply.json` | NGA API | 人工组合失败边界 | 主楼可读但 API 回复正文 unusable 时仍保留楼层身份 |
| `nga-thread-web-valid-reply-fallback.html` | NGA Web | 人工组合边界，DOM 形状来自真实页面 | unusable API 回复的同楼层整文档回退 |
| `nga-thread-api-failure.json` | NGA API | 人工组合失败边界 | API transport/provider 失败不得伪装为正文 |
| `nga-thread-web-access-denied.html` | NGA Web | 人工组合失败边界 | Web 访问拒绝不得伪装为正文 |
| `nga-thread-web-content-unusable.html` | NGA Web | 人工组合失败边界 | 两来源正文均 unusable 时返回 typed error |
| `v2ex-topics.json` | V2EX API | 脱敏响应形状 | V2EX 主题、正文图片和来源映射 |
| `v2ex-threaded-replies-1227563-shape.json` | V2EX API | 依据主题 `1227563` 回复引用形状脱敏裁剪 | 显式楼层引用、最近同名作者、跨页分支、冲突楼层、多用户歧义和未解析引用 |
| `cross-source-feed-times.json` | NGA/V2EX/Discourse 时间边界 | 人工组合边界 | Unix 秒/毫秒、ISO 8601 和旧快照日期统一解析为 `MM-dd HH:mm` |

## NGA 内容证据覆盖

| 样本或测试 | 分类 | 已证明 | 不能证明 |
| --- | --- | --- | --- |
| `post-list.json` | 脱敏真实响应形状 | API 主楼、回复、用户目录和头像映射 | API/Web 来源选择策略 |
| `nga-thread-api-incomplete.json` + `nga-thread-web-enrichment.html` | 裁剪真实形状的配对样本 | 同一楼层的 API/Web 原始表示、图片地址和格式可能不同 | 生产环境 API 确实缺失用户可见正文；逐行合并是必要的 |
| `nga-thread-page2-media.json` | 人工组合边界 | 续页媒体、转义 URL、重复主楼边界 | 真实 API/Web 差异频率 |
| `ForumHubTests.swift` 中语义解析、解析质量和分页样例 | 人工组合边界 | BBCode/HTML 语义节点、质量与分页回归边界 | 真实双源缺失频率 |
| 帖子 `47185513` 的人工审计记录 | 真实在线观测（不入库原文） | 已观测楼层 0–11、两张有序图片、三个表情和引用在 API 中完整；API/Web 主要是表示差异 | 其他帖子或未来 NGA 响应仍然完整 |

当前证据结论：语义级双源 `Reconciler` 不在本次架构范围内。只有出现至少两个彼此独立、脱敏且可重复的真实配对 Fixture，并且它们都证明“单一来源缺少不同的用户可见语义，而整份来源切换仍不足以恢复内容”时，才重新评估引入 `Reconciler`。在此之前采用 API-first；只有 API 正文质量为 unusable 时，才以同楼层的整份 Web 语义文档回退，禁止逐行拼接和全局去重。

维护规则：

- 新 Fixture 必须说明是“脱敏真实形状”还是“人工组合边界”；
- 优先保留最小可复现字段，不整包提交生产响应；
- 正常、降级和失败路径分别命名，避免一个巨大 Fixture 覆盖所有场景；
- 修改 Parser 时先补 Fixture 和失败测试，再修改实现；
- Fixture 进入测试 Bundle 后必须在真机运行相关测试。
