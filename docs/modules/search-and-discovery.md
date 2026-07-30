# Search And Discovery Module

## Scope

This module covers how users find threads outside the default feed flow.

It includes:

- Cross-source search entry points
- Search result rendering
- Source-specific search behavior
- Navigation from search results into thread detail
- Interaction with browsing history and current source context

## Key Files

- `ForumHub/Features/Search/SearchThreadsView.swift`
- `ForumHub/Features/ForumFeed/ForumViewModel.swift`
- `ForumHub/Data/NGA/NGAForumRepository.swift`
- `ForumHub/Data/V2EX/V2EXThreadRepository.swift`
- `ForumHub/Data/Discourse/DiscourseThreadRepository.swift`

## Notes

- Search is not truly equivalent across sources.
- NGA has the richest search behavior among current adapters.
- V2EX search is narrower and should be treated as a lower-confidence discovery surface.
- LINUX DO search depends on the Discourse-backed adapter and may behave differently from feed browsing.
- Search results should still map into shared `ForumThread` models so downstream detail flows stay uniform.
- Opening a search result is recorded by the shared thread-detail boundary; Search does not own a separate history-writing path.
- NGA server search currently covers subject/title text rather than reply-body full text and requires an authenticated registered account with positive reputation. The result screen must not imply body-text search.
- 2026-07-30 用户已在真实登录环境完成 NGA 主题标题搜索验收，确认当前搜索范围与结果正常。

## Current Risks

- Users can assume all sources support the same search scope, ordering, and completeness even when they do not.
- Search UX can feel inconsistent if unsupported or partial behavior is not surfaced clearly.
- Source-specific pagination and cancellation behavior can cause confusing empty states if not handled carefully.
