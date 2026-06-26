# LINUX DO Module

## Scope

LINUX DO is currently backed by a Discourse-style adapter and a web login flow.

It supports:

- Feed browsing
- Topic detail loading
- Web login with cookie reuse
- Account surface integration

## Key Files

- `ForumHub/Data/Discourse`
- `ForumHub/Session/LinuxDoAuthStore.swift`
- `ForumHub/Session/LinuxDoLoginView.swift`

## Notes

- Direct API access can be blocked by site protections.
- Login is intentionally browser-assisted rather than fully native.

