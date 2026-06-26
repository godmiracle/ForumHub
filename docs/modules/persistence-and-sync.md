# Persistence And Sync Module

## Scope

This module covers local persistence, session storage, and future sync boundaries.

It includes:

- UserDefaults-backed feature state
- Keychain-backed credentials
- Shared cookie storage
- Local favorites, history, blocked users, and channel ordering
- Sync-related constraints and future directions

## Key Areas

- `ForumHub/Features/Account`
- `ForumHub/Features/BlockedUsers`
- `ForumHub/Features/History`
- `ForumHub/Features/ForumManagement`
- `ForumHub/Session`
- `ForumHub/Sync`

## Notes

- Local persistence is currently the source of truth for favorites, blocked users, browsing history, and subscribed channel order.
- Session-like credentials should stay in Keychain or cookie stores rather than plain defaults.
- Persistence is source-aware so different communities do not collide on the same IDs or usernames.
- Sync hooks exist conceptually, but iCloud-backed sync is currently disabled.

## Current Persisted Concerns

- Active source selection
- Channel subscriptions
- Channel display order
- Favorite threads
- Blocked users
- Browsing history
- NGA login state
- V2EX token
- LINUX DO cookie-backed account state

## Sync Boundary

- Do not treat iCloud sync as active product behavior.
- Any future sync work should preserve source scoping and ordering semantics.
- Remote sync should not weaken the current local-first behavior for core reading flows.

## Current Risks

- Local-only state can be lost on uninstall or device change.
- If sync is added later, migration rules must be explicit for favorites, blocked users, and subscriptions.
- Auth/session state and user-content state should not be merged into one generic sync mechanism.

