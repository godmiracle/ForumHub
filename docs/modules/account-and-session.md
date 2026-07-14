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

- Blocked users persist locally for offline use and merge through iCloud KVS.
- NGA and V2EX favorites use the source account as authority and keep a lightweight local UI cache; sources without remote bookmark integration do not expose favorite actions.
- Token and login-cookie Keychain items opt into iCloud Keychain synchronization and remain separate from user-content KVS data.
- Synchronizable Keychain items are updated atomically; failed updates preserve the previous credential and surface a sync error where the source has an observable account store.
- Session restore runs at launch and is retried with a 30-second throttle when the app returns to the foreground, covering credentials that arrive after initial startup.
- App logout clears the current device and deletes the synchronized backup request, but does not claim to revoke website sessions that already exist on another device.
- Auth flows differ sharply by source and should remain isolated.

## Current Sources

### NGA

- Uses a WebKit login flow
- Syncs login cookies from `WKHTTPCookieStore` into `HTTPCookieStorage.shared`
- Persists key login cookies in Keychain
- Treats `ngaPassportUid` and `ngaPassportCid` as the primary session signals

### V2EX

- Uses a user-provided Personal Access Token
- Validates the token against the V2EX API before treating the source as connected
- Persists the token in Keychain
- Keeps a separate WebKit cookie session for V2EX website actions
- Persists only `v2ex.com` cookies in a dedicated Keychain item and restores them into WebKit plus shared HTTP cookie storage
- Loads `/my/topics` to validate the web session and provide the remote favorite list
- Parses the current topic page for the same-origin `favorite` or `unfavorite` action carrying V2EX's current `once` value; the API token is never attached to webpage requests

### LINUX DO

- Uses a WebKit login flow plus cookie reuse
- Persists `linux.do` cookies in Keychain
- Reads `/session/current.json` to resolve the current account
- Keeps a local account summary cache for user-facing status

## Problem Statement

The current source-specific auth stores work, but the upper layer still needs to know too much about each source:

- The account screen manually branches on each source to render status text
- Credential type and persistence strategy are implicit instead of modeled explicitly
- Session restore behavior is source-aware but not exposed through one shared shape
- Adding another source would grow more UI and coordination branches

The main issue is not missing functionality. The issue is that login and session state are not yet described through one shared presentation model.

## Proposed Direction

Keep source-specific authentication behavior where it already belongs, but add a thin unified layer above it for:

- Session status description
- Upper-layer account UI
- Aggregated session restore
- Future diagnostics

This means:

- Shared display model
- Shared read-only auth protocol
- Shared auth registry
- No attempt to merge all credential storage into one universal store

## Non-Goals

- Do not replace the current source-level auth stores with one global `SessionStore`
- Do not force Web-login and token-login flows into the same action API
- Do not move source-specific cookie or token details out of `ForumHub/Session`
- Do not treat sync as part of the auth redesign
- Do not add QR-code login or new auth methods in this phase

## Proposed Model Additions

### `AuthCredentialKind`

Use a small enum to describe the credential shape:

- `cookie`
- `token`

This gives the UI and future diagnostics one stable vocabulary without exposing raw credentials.

### `AuthPersistenceKind`

Use a small enum to describe how the credential is kept locally:

- `keychainCookie`
- `keychainToken`
- `keychainCookiePlusAccountCache`

This keeps storage semantics explicit without leaking implementation details into views.

### `AuthSessionDescriptor`

Add a shared display-oriented descriptor for each source session.

Suggested fields:

- `source: ForumSource`
- `isAuthenticated: Bool`
- `credentialKind: AuthCredentialKind`
- `persistenceKind: AuthPersistenceKind`
- `displayTitle: String`
- `displaySubtitle: String`
- `username: String?`
- `diagnosticSummary: String?`

Rules:

- It is a presentation model, not a credential container
- It should not carry raw token values or full cookie values
- It may include short safe summaries for the account screen or future troubleshooting

## Proposed Protocol

Add a lightweight source auth protocol for upper layers.

Suggested responsibilities:

- expose `source`
- expose `descriptor`
- implement `restoreSession()`
- implement `logout()`

This protocol should not try to standardize `login()` because the entry flows differ too much across sources.

## Proposed Aggregation

Add an auth registry that owns the existing auth stores and exposes:

- one `restoreAll()` entry point
- one `[AuthSessionDescriptor]` collection for upper-layer UI

The registry should aggregate state, not replace source-specific behavior.

## Source Mapping Rules

### NGA

- `credentialKind = .cookie`
- `persistenceKind = .keychainCookie`
- `displayTitle = "NGA"`
- Signed-out status should read as `游客`
- Signed-in status should read as `已登录 · Cookie`

### V2EX

- `credentialKind = .token`
- `persistenceKind = .keychainToken`
- `displayTitle = "V2EX"`
- Signed-out status should read as `公开浏览`
- Connected status should read as `已连接 · Token`

`V2EX` is better described as a connected API account than a browser-style signed-in session.

### LINUX DO

- `credentialKind = .cookie`
- `persistenceKind = .keychainCookiePlusAccountCache`
- `displayTitle = "LINUX DO"`
- Signed-out status should read as `网页登录`
- Connected status should read as `已连接 · Cookie`

This source combines browser-session cookies with a local cached account summary, so the descriptor should preserve that reality.

## UI Guidance

### Account Screen

Keep the existing richer NGA-specific account card.

Refactor the `社区连接` section to consume shared descriptors for:

- title
- subtitle
- connected state
- lightweight diagnostics

Keep source-specific taps and sheets:

- NGA opens the NGA login flow
- V2EX opens token entry
- LINUX DO opens the web login sheet

This keeps the display unified without flattening the auth flows themselves.

## Implementation Plan

### Step 1

Add the new shared enums and descriptor model.

Then extend the current source auth stores with:

- `source`
- `descriptor`

No UI changes yet.

### Step 2

Add the shared protocol and auth registry.

Move upper-layer session restore orchestration into `restoreAll()`.

No changes to the concrete login flows yet.

### Step 3

Update the account screen's `社区连接` section to render from descriptors instead of reaching directly into each source store's internal status shape.

Keep source-specific connect actions unchanged.

## Risks

- Over-abstracting the login flows would make the auth layer harder to reason about, not easier
- `AuthSessionDescriptor` must stay presentation-safe and should never become a raw credential payload
- `V2EX` should not be mislabeled as the same kind of browser session as `NGA` or `LINUX DO`
- `LINUX DO` needs its mixed cookie-plus-account-cache reality to stay visible in the design

## Expected Benefits

- The account layer gets one stable vocabulary for auth state
- Session restore orchestration becomes easier to evolve
- Adding another source will require fewer UI branches
- Future auth diagnostics can build on a shared descriptor instead of per-view conditionals
