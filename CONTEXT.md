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
- **Authoritative Child Forum Directory**: The last fully validated direct-child snapshot for one Forum Source and parent Forum Channel. Shared consumers use source-and-parent scope plus kind-preserving stable keys; source response fields remain inside the provider adapter.
- **Forum Subscription**: A locally persisted choice that controls which returned Forum Channels appear in the top navigation.
- **Topic**: A forum thread summary shown in a Forum Feed.
- **Thread Detail**: The first post and replies for a Topic, with local presentation options such as only-author filtering, reverse order, floor labels, image preview, and pagination.
- **Thread Reply Target**: The destination for a reply submission inside Thread Detail. It can be the thread itself or a specific reply floor when the source supports targeted replies.
- **Login Session**: Source-specific credentials. NGA and LINUX DO use WebKit cookies plus shared HTTP cookie storage. V2EX keeps its API v2 Personal Access Token separate from a WebKit cookie session used for source-native favorites and original-page browsing.
- **Auth Session Descriptor**: A shared account-screen summary for one Forum Source. It describes how a source session should be presented in upper-layer UI without exposing raw cookie or token details.
- **Source Session State**: A presentation-safe `checking`, `signedOut`, `authenticated`, or `expired` state. Only explicit authentication-expired evidence may select `expired`.
- **Forum Provider**: The module behind the `ThreadRepository` seam. NGA, V2EX, and Discourse-based adapters map native data into shared domain models.
- **Favorite Thread**: A source-native bookmark entry. NGA and V2EX treat the source account as authoritative and keep only a lightweight local UI cache; sources without remote bookmark capability do not expose a favorite action.
- **Blocked User**: A per-source suppression rule synchronized through iCloud KVS. It hides content by username without mutating remote forum data.

## Invariants

- A valid Login Session requires a non-empty `ngaPassportCid`, or a non-guest `ngaPassportUid`.
- Public forum browsing does not require a Login Session; sign-in is entered from the Account feature when needed.
- Views consume domain models and do not parse NGA responses.
- Source-specific field names, identifiers, encoding, and fallback rules stay inside their provider adapter.
- Thread post content keeps immutable source representations, but ordered semantic blocks are the sole reading authority for rendering, sharing, accessibility, snapshots, media enumeration, and signatures.
- NGA thread detail is API-first. Valid or degraded API content performs no Web request; only unusable API content may select a whole same-floor Web semantic document while retaining API identity, metadata, membership, and order.
- Cross-source content must never be reconciled through normalized strings, line splitting, global deduplication, or end-appending heuristics.
- `ForumThread` content equality includes rendered content and metadata; source plus native topic ID is the explicit identity key for deduplication, persistence, and navigation.
- NGA, V2EX, LINUX DO, and mock adapters satisfy the `ThreadRepository` interface.
- Reply composition should keep one shared entry flow while letting each source adapter decide whether it supports thread-level reply only or reply-to-floor targeting.
- Persisted member identities are scoped by Forum Source so same-name users do not collide.
- The first launch subscribes to 网事杂谈 (`-7`), 大时代 (`706`), and 晴风村 (`-7955747`); at least one Forum Subscription remains active.
- Public forum usernames in the blocked-user list sync through iCloud KVS; credentials sync separately through iCloud Keychain and never enter the KVS payload.
- NGA thread detail pagination should preserve source fetch order, accumulate continuation pages into one reading flow, and must not reintroduce the main post as a reply row.
- Feed time ordering and display use structured dates created at adapter boundaries; legacy time strings are compatibility-only and unparseable values never discard a topic.
- Feed sort mode crosses the repository boundary for refresh, aggregation, and pagination. NGA latest-topic mode requests server-side `postdatedesc` instead of merely reordering a last-reply page locally.
- Feed sort and pinned preferences are source-scoped, while child-channel selections are source-and-parent-channel scoped and sanitized against the latest confirmed authoritative directory.
- Channel navigation, list identity, subscriptions, and ordering use canonical source-scoped keys. Legacy NGA numeric channels normalize to `nga:fid:<id>`, authoritative topic targets remain `nga:stid:<id>`, and a bare integer never reconciles different browsing kinds.
- An authoritative child forum may be subscribed as an independent Home channel that loads only that child. Home subscriptions and Wangshi main-plus-children aggregation selections are separate preferences and never implicitly update each other.
- NGA Wangshi child filtering uses only fully validated parent metadata. Shared stable keys preserve the distinction between `fid:` and `stid:` browsing identities, while NGA filtering IDs, attributes, and positional response fields remain inside the NGA adapter.
- Authoritative directory refreshes fail closed: request, decoding, or structural failure retains the last confirmed snapshot and selection. Only a complete snapshot may add, rename, or cancel children; cancelling an active selection invalidates the old Feed generation before one reload with the remaining stable keys.

## Current Focus Areas

- Smooth multi-source reading experience
- Reliable thread detail pagination and image handling
- Local-first account features with future sync hooks
