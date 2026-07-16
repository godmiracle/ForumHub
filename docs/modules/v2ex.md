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
