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
- 最近确认的网事杂谈权威目录同时服务 Feed 聚合筛选与栏目发现，但两类用户偏好保持独立。权威子版可用 `nga:fid:<id>` 或 `nga:stid:<id>` 作为首页独立栏目订阅；独立打开只加载该浏览目标。
- 普通 NGA 裸数字栏目在导航和订阅边界规范化为 `nga:fid:<id>`。同一 fid 在全站目录和权威目录中只展示一次，`fid:N` 与 `stid:N` 不得合并。
- `stid` 独立栏目的网页列表按 `tr.topicrow` 一行一主题解析：标题取 `a.topic`，作者取 `a.author`，回复数取 `a.replies`。不得把排在标题前面的“打开新窗口”辅助链接当成主题，也不得用“来自网页兜底解析”替代可确认的行元数据。
- 完整快照确认改名时保留首页订阅，确认取消时分别清理首页订阅与父版筛选；请求或结构失败继续保留最近确认目录和两类偏好。
- `NGABBCodeContentParser` and `NGAHTMLContentParser` share one tolerant embedded-HTML normalizer before lowering source markup into ordered semantic blocks. The normalizer is tag-semantic rather than class-specific: it preserves readable descendants and block boundaries, extracts safe links/images, lowers both direct `video src` and nested `video/source` markup into one video block carrying source and optional poster URLs, and drops scripts, styles, event attributes and non-HTTP(S) destinations.
- Only unusable API content enters Web fallback. The fallback replaces a whole same-floor document while preserving API identity, metadata, membership, and order; Web-only floors are ignored and diagnosed.
- Complete API transport failure is a typed error; users can still choose the existing original-page action.
- NGA emoji tables, relative attachment resolution, BBCode, HTML and DOM rules stay inside the NGA adapter.
- `NGAReplyEmojiCatalog` 是回复表情的来源专属事实入口，按 `NG娘、AC娘 v1、AC娘 v2、潘斯特、外域、企鹅` 提供六组条目；新增资源边界为 `pt00...pt64`、`dt01...dt33`、`pg01...pg15`。回复继续序列化为 `[img]https://img4.nga.cn/ngabbs/post/smile/<filename>[/img]`，读取旧帖时会把旧的 `img4.nga.178.com` smile 地址归一化到当前域名，编辑器也兼容旧地址；标准 smile PNG 随 App 分发作为首选本地兜底，运行时缓存使用文件名保存在 `Library/Caches/ForumEmoji`，只有可信 NGA smile 域名且属于合法文件名的资源才进入该路径。
- A future dual-source reconciler requires two independent real paired Fixtures proving complementary semantic loss; current evidence does not meet that gate.
- Reply pagination needs careful duplicate filtering because later pages may reintroduce the main post.
- NGA may change the private response shape; a future mismatch must fail closed and retain the last confirmed directory rather than introduce position or attributes heuristics.
- Rich content and images are a major source of UX complexity.
- 自动签到使用已恢复的 NGA Cookie 会话访问 `nuke.php`，先读 `get_stat`，只有真实 Fixture 明确确认未签到状态且生产证据门禁解除后才允许 POST `check_in`。当前门禁未解除，因此已签到语义可安全展示，未知或合成未签到结构均不可触发写请求。
- NGA 服务端日界线尚未由真实响应确认，本地日期不作为跳过服务端检查的权威依据。
- 2026-07-27 真机按本地文档调用 `app_api.php` 的 `get_stat → check_in → get_stat`，三次均为相同 `code=2` 且没有状态变化；这只证明端点可达，不证明请求合约或签到成功。当前 production 继续使用不可写门禁，也不得在未确认额外请求头、method 或客户端参数前切换端点。
