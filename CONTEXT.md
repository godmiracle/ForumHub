# ForumHub Domain Context

## Purpose

ForumHub is a personal iOS client for multiple community sources. It started as an NGA prototype and has evolved into a multi-source reader with lightweight account actions and source-specific adapters.

Current sources:

- NGA
- V2EX
- LINUX DO

## Domain Language

- **Forum Source**: A remote community that provides channels, topics, and thread details.
- **Forum Channel**: A selectable board within a Forum Source. NGA uses a numeric `fid`; V2EX uses a node name; LINUX DO uses a category slug and ID pair.
- **Community Screen**: The channel-management surface. Source switching now happens from the Home top-left menu instead of treating Community as the primary source switcher.
- **Browsing History**: A local, source-aware list of the 50 most recently opened topics, keyed by source plus native topic ID.
- **Forum Feed**: A paginated list of pinned and regular topics for a Forum Channel, or the hot feed.
- **Forum Subscription**: A locally persisted choice that controls which returned Forum Channels appear in the top navigation.
- **Topic**: A forum thread summary shown in a Forum Feed.
- **Thread Detail**: The first post and replies for a Topic, with local presentation options such as only-author filtering, reverse order, floor labels, image preview, and pagination.
- **Login Session**: Source-specific credentials. NGA and LINUX DO use WebKit cookies plus shared HTTP cookie storage; V2EX uses a Personal Access Token with API v2.
- **Forum Provider**: The module behind the `ThreadRepository` seam. NGA, V2EX, and Discourse-based adapters map native data into shared domain models.
- **Favorite Thread**: A locally persisted thread bookmark, optionally backed by a source-native favorite API when available.
- **Blocked User**: A local per-source suppression rule that hides content by username without mutating remote data.

## Invariants

- A valid Login Session requires a non-empty `ngaPassportCid`, or a non-guest `ngaPassportUid`.
- Public forum browsing does not require a Login Session; sign-in is entered from the Account feature when needed.
- Views consume domain models and do not parse NGA responses.
- Source-specific field names, identifiers, encoding, and fallback rules stay inside their provider adapter.
- NGA, V2EX, LINUX DO, and mock adapters satisfy the `ThreadRepository` interface.
- Persisted member identities are scoped by Forum Source so same-name users do not collide.
- The first launch subscribes to 网事杂谈 (`-7`), 大时代 (`706`), and 晴风村 (`-7955747`); at least one Forum Subscription remains active.
- iCloud-backed sync is currently disabled and should not be treated as an active feature.
- Thread detail pagination should append new replies without reintroducing the main post as a reply row.

## Current Focus Areas

- Smooth multi-source reading experience
- Reliable thread detail pagination and image handling
- Local-first account features with future sync hooks
