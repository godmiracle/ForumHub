# V2EX Module

## Scope

V2EX currently focuses on read-heavy access with lightweight account integration.

It supports:

- Latest and node feeds
- Thread detail
- Optional token-backed account connection

## Key Files

- `ForumHub/Data/V2EX`
- `ForumHub/Session/V2EXAuthStore.swift`

## Notes

- Feature parity is intentionally narrower than NGA.
- Some actions exposed by the shared UI are capability-gated because V2EX public APIs do not support them.

