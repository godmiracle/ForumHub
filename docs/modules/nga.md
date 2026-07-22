# NGA Module

## Scope

NGA is the most complex source adapter in ForumHub.

It currently supports:

- Forum channel loading
- Authoritative child-forum directory loading for supported parent forums
- Feed loading
- Thread detail loading
- Favorites
- Reply posting
- Web login and cookie reuse

## Key Files

- `ForumHub/Data/NGA`
- `ForumHub/Data/NGA/Parsers/NGAAuthoritativeChildForumParser.swift`
- `ForumHub/Session/NGAAuthStore.swift`
- `ForumHub/Session/NGALoginView.swift`

## Notes

- Detail loading is API-first: valid/degraded API semantic documents return immediately without a Web request.
- 网事杂谈子版目录只读取父版 `fid=-7` 主题元数据中的已验证 `__F/sub_forums` 直接子节点。全站分类、收藏和标签栏目继续服务栏目管理，但不参与子版推断或失败回退。
- 2026-07-20 的脱敏真机 Fixture 固定了五项位置数组合约：浏览标识、名称、说明、过滤 ID、attributes。普通记录按 `fid` 浏览，`t<ID>` 记录按 `stid` 浏览；稳定键保留目标种类，过滤 ID 与 attributes 只停留在 NGA 适配层。
- Parser 严格校验父版身份、容器、节点类型、位置数量、容器 ID 与浏览标识及稳定键唯一性。请求或结构失败不会提交权威快照。
- `ThreadRepository.fetchAuthoritativeChildForumDirectory(parent:)` 以可选 capability 暴露共享目录；NGA 提供实现，其他来源沿用无能力的默认结果。本能力不调用 `nuke.php`，不修改 NGA 服务器端屏蔽设置。
- `NGABBCodeContentParser` and `NGAHTMLContentParser` lower source markup into the same ordered semantic blocks with parse quality and safe diagnostics.
- Only unusable API content enters Web fallback. The fallback replaces a whole same-floor document while preserving API identity, metadata, membership, and order; Web-only floors are ignored and diagnosed.
- Complete API transport failure is a typed error; users can still choose the existing original-page action.
- NGA emoji tables, relative attachment resolution, BBCode, HTML and DOM rules stay inside the NGA adapter.
- `NGAReplyEmojiCatalog` 是回复表情的来源专属事实入口，按 `NG娘、AC娘 v1、AC娘 v2、潘斯特、外域、企鹅` 提供六组条目；新增资源边界为 `pt00...pt64`、`dt01...dt33`、`pg01...pg15`。回复继续序列化为 `[img]https://img4.nga.178.com/ngabbs/post/smile/<filename>[/img]`，只有可信 NGA smile 域名且属于目录的文件名才能恢复为富文本表情。
- A future dual-source reconciler requires two independent real paired Fixtures proving complementary semantic loss; current evidence does not meet that gate.
- Reply pagination needs careful duplicate filtering because later pages may reintroduce the main post.
- NGA may change the private response shape; a future mismatch must fail closed and retain the last confirmed directory rather than introduce position or attributes heuristics.
- Rich content and images are a major source of UX complexity.
