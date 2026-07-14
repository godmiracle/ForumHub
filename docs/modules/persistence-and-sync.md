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

- Local persistence is the offline cache for blocked users and remains authoritative for browsing history and subscribed channel order. NGA and V2EX favorites treat the source account as authoritative while retaining lightweight local UI metadata.
- Session-like credentials use iCloud-synchronizable Keychain items and cookie stores rather than KVS or plain defaults.
- Persistence is source-aware so different communities do not collide on the same IDs or usernames.
- Favorites, history, and blocked users use a versioned `{ version, payload }` JSON envelope. Legacy raw arrays migrate in place; corrupt or unsupported snapshots degrade to an empty local state.
- Channel subscriptions keep their property-list representation, record an independent schema version, and discard malformed source/native keys while restoring.
- Scalar settings use their existing typed/default fallback and are not forced into the JSON envelope.
- Blocked-user records use one KVS key per identity and merge with per-user timestamps and deletion tombstones. Startup and initial-sync handling never write a whole local snapshot back to iCloud.

## Current Persisted Concerns

- Active source selection
- Channel subscriptions
- Channel display order
- Source-native favorite UI cache for NGA and V2EX
- Blocked users
- Browsing history
- NGA login state
- V2EX token
- V2EX web-login cookies for website favorites and original-page browsing
- LINUX DO cookie-backed account state

## Sync Boundary

- iCloud KVS contains only blocked-user records; it never contains Token, Cookie, password, browsing history, or remote favorite data.
- iCloud Keychain contains account Token/Cookie items when the user enables iCloud Keychain.
- Empty first-launch state is not uploaded until cloud data arrives or the user makes a real change.
- Per-user last-write-wins records preserve independent changes across devices; deletion tombstones prevent stale devices from resurrecting unblocked users.
- KVS notification reasons are handled separately: account changes reset the old local cache, quota failures are visible, and server changes reconcile per-record winners.
- Keychain writes use update-or-add semantics and the app retries session restore after returning to the foreground.
- App logout clears the current device and requests deletion of the synchronized backup; it cannot revoke an already-issued remote website session on every device.

## Current Risks

- Browsing history and channel ordering remain local-only and can be lost on uninstall or device change.
- Device clock skew can affect per-user last-write-wins conflict resolution.
- Tombstones are retained instead of garbage-collected; the sync layer enforces a 900-record safety limit to stay below KVS's 1024-key ceiling.
- Auth/session state and user-content state should not be merged into one generic sync mechanism.
- Schema changes require an explicit migration test; Codable synthesis alone is not a migration policy.
