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

## Current Risks

- Users can assume all sources support the same search scope, ordering, and completeness even when they do not.
- Search UX can feel inconsistent if unsupported or partial behavior is not surfaced clearly.
- Source-specific pagination and cancellation behavior can cause confusing empty states if not handled carefully.

