# V2EX Module

## Scope

V2EX currently focuses on read-heavy access with lightweight account integration.

It supports:

- Latest and node feeds
- Thread detail
- API-derived threaded reply presentation with a flat fallback
- Optional token-backed account connection

## Key Files

- `ForumHub/Data/V2EX`
- `ForumHub/Session/V2EXAuthStore.swift`

## Notes

- Feature parity is intentionally narrower than NGA.
- “最热”是跨节点聚合入口而非真实节点：首屏使用官方每日 Top 10，滚动到底部后遵循 PC 页“更多新主题”的 `/recent` 入口继续加载；左上角“最热”与底栏“热门”展示相同主题归属，每条主题保留其真实节点标签。`nodes/list.json` 只提供频道目录，不作为帖子数据源。
- Some actions exposed by the shared UI are capability-gated because V2EX public APIs do not support them.
- Thread fetching continues to use `topics/show.json` and `replies/show.json`; reply threading does not request topic HTML.
- The adapter extracts `@username` and optional `#floor` evidence before content normalization. Explicit floor-and-author agreement wins, a single username may resolve to the nearest previous reply by that author, and ambiguous multi-user references remain roots.
- API `content_rendered` is mapped into ordered semantic text and image blocks for both topics and replies; raw `content` remains the relationship-evidence source.
- Resolved parent links are optional, explainable metadata. The canonical API reply array and complete `ForumPostDocument` remain authoritative.
- Tree mode is the normal V2EX detail presentation and can be switched to flat mode from the detail More menu. Only-author mode stays flat; reverse mode reverses root groups while preserving branch direction.
- 每日奖励只使用独立的 V2EX Web Cookie Session；Personal Access Token 不会附加到 `/mission/daily` 请求。真实领取控件必须是唯一 `input[type=button]`，文案匹配“领取 … 铜币”，且 `onclick` 只允许 `location.href = '<URL>';` 这一有限语法；不会执行任意 JavaScript。
- 从 onclick 提取的动作必须使用 HTTPS、严格 `www.v2ex.com`、精确 `/mission/daily/redeem`，且 query 只有一个非空动态 `once`。动作至多执行一次，随后独立再次加载 `/mission/daily` 并精确确认“每日登录奖励已领取”。
- 每日奖励状态只从最终 URL 为 HTTPS `www.v2ex.com/mission/daily` 且 Content-Type 为 HTML/XHTML 的响应解析；跨域、HTTP、同域错误路径和非 HTML 响应统一视为 unknown，不能签发领取动作。
- 2026-07-23 已在授权 Chrome Web Session 中完成真实可领取、一次动作、成功结果和再次访问确认并固化脱敏 Fixture，因此 V2EX production 子门禁已解除。真实失效会话跳转与完整 3xx 链仍待采样；未知页面继续 fail closed，整项 NGA/V2EX 验收仍未完成。
