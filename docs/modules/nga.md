# NGA Module

## Scope

NGA is the most complex source adapter in ForumHub.

It currently supports:

- Forum channel loading
- Feed loading
- Thread detail loading
- Favorites
- Reply posting
- Web login and cookie reuse

## Key Files

- `ForumHub/Data/NGA`
- `ForumHub/Session/NGAAuthStore.swift`
- `ForumHub/Session/NGALoginView.swift`

## Notes

- Detail loading is API-first: valid/degraded API semantic documents return immediately without a Web request.
- `NGABBCodeContentParser` and `NGAHTMLContentParser` lower source markup into the same ordered semantic blocks with parse quality and safe diagnostics.
- Only unusable API content enters Web fallback. The fallback replaces a whole same-floor document while preserving API identity, metadata, membership, and order; Web-only floors are ignored and diagnosed.
- Complete API transport failure is a typed error; users can still choose the existing original-page action.
- NGA emoji tables, relative attachment resolution, BBCode, HTML and DOM rules stay inside the NGA adapter.
- `NGAReplyEmojiCatalog` 是回复表情的来源专属事实入口，按 `NG娘、AC娘 v1、AC娘 v2、潘斯特、外域、企鹅` 提供六组条目；新增资源边界为 `pt00...pt64`、`dt01...dt33`、`pg01...pg15`。回复继续序列化为 `[img]https://img4.nga.178.com/ngabbs/post/smile/<filename>[/img]`，只有可信 NGA smile 域名且属于目录的文件名才能恢复为富文本表情。
- A future dual-source reconciler requires two independent real paired Fixtures proving complementary semantic loss; current evidence does not meet that gate.
- Reply pagination needs careful duplicate filtering because later pages may reintroduce the main post.
- Rich content and images are a major source of UX complexity.
