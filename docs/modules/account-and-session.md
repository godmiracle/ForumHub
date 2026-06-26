# Account And Session Module

## Scope

This module covers login, source-specific credential persistence, and user-facing account utilities.

It includes:

- NGA login and cookie sync
- V2EX token-based auth
- LINUX DO web login and cookie sync
- Favorites
- Blocked users
- Browsing history

## Key Files

- `ForumHub/Session`
- `ForumHub/Features/Account`
- `ForumHub/Features/BlockedUsers`
- `ForumHub/Features/History`

## Notes

- Favorites and blocked users are currently local-first.
- Sync hooks exist conceptually, but iCloud sync is disabled.
- Auth flows differ sharply by source and should remain isolated.

