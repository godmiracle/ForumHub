# LINUX DO Module

## Scope

LINUX DO is currently backed by a Discourse-style adapter and a web login flow.

It supports:

- Feed browsing
- Topic detail loading
- Web login with cookie reuse
- Account surface integration
- Browser-context fallback when Cloudflare blocks direct JSON requests

## Key Files

- `ForumHub/Data/Discourse`
- `ForumHub/Session/LinuxDoAuthStore.swift`
- `ForumHub/Session/LinuxDoLoginView.swift`

## Notes

- Direct API access can be blocked by site protections. The adapter first attempts the normal `URLSession` request and uses a shared WebKit context only after a `403` response.
- If WebKit is also challenged, the feed exposes an "打开浏览器验证" action. Completing or closing that sheet retries the current feed.
- Login is intentionally browser-assisted rather than fully native.
