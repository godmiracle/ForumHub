# ForumHub Test Fixtures

本目录保存可重复、无账号凭证的响应样本。Fixture 只保留解析所需结构；用户名、帖子 ID、正文和资源地址均已替换为测试值，不得加入 Cookie、Token、Auth 字段或可识别个人信息。

| 文件 | 类型 | 结构来源 | 覆盖目的 |
| --- | --- | --- | --- |
| `post-list.json` | NGA API | 脱敏真实响应形状 | 主楼、回复、用户目录和头像映射 |
| `nga-thread-api-incomplete.json` | NGA API | 基于脱敏真实响应形状裁剪 | API 正文不完整、已有图片和已有回复 |
| `nga-thread-web-enrichment.html` | NGA Web | 基于脱敏真实 DOM 结构裁剪 | 网页正文补全、图片补全和楼层合并 |
| `nga-thread-page2-media.json` | NGA API | 人工组合边界，字段形状来自真实续页响应 | 第二页 GIF、转义 URL、引用图片原文和重复主楼 |
| `v2ex-topics.json` | V2EX API | 脱敏响应形状 | V2EX 主题、正文图片和来源映射 |

维护规则：

- 新 Fixture 必须说明是“脱敏真实形状”还是“人工组合边界”；
- 优先保留最小可复现字段，不整包提交生产响应；
- 正常、降级和失败路径分别命名，避免一个巨大 Fixture 覆盖所有场景；
- 修改 Parser 时先补 Fixture 和失败测试，再修改实现；
- Fixture 进入测试 Bundle 后必须在真机运行相关测试。
