# Feature Matrix

This document tracks which user-facing capabilities are available for each integrated source.

## Source Capability Matrix

| Capability | NGA | V2EX | LINUX DO |
| --- | --- | --- | --- |
| Home feed | Yes | Yes | Yes |
| Hot feed | Yes | Yes | Yes |
| Channel switching | Yes | Yes | Yes |
| Channel subscription | Yes | Yes | Yes |
| Channel drag reorder | Yes | Yes | Yes |
| Thread detail | Yes | Yes | Yes |
| Detail pagination | Yes | No | No |
| Floor labels | Yes | Yes | Yes |
| Only-author mode | Yes | Yes | Yes |
| Reverse reply order | Yes | Yes | Yes |
| Image preview | Yes | Yes | Yes |
| GIF playback | Yes | Depends on remote asset | Depends on remote asset |
| Save image to Photos | Yes | Yes | Yes |
| Share thread link | Yes | Yes | Yes |
| Share post snapshots | Yes | Yes | Yes |
| Native favorite API | Yes | No | No |
| Local favorites fallback | Yes | Yes | Yes |
| Reply thread | Yes | No | No |
| Reply with images | Yes | No | No |
| Source login | Web + Cookies | Token | Web + Cookies |
| Account surface | Yes | Yes | Yes |
| Search | Yes | Limited | Yes |
| Blocked users | Local only | Local only | Local only |
| Browsing history | Yes | Yes | Yes |

## Notes

- `Native favorite API` means the source adapter can call a source-owned favorite endpoint.
- `Local favorites fallback` means the app can still persist favorite threads locally even when the source has no remote favorite API.
- `Detail pagination` means loading later reply pages from the source, not just scrolling already loaded replies.
- `Only-author mode` and `Reverse reply order` are currently presentation-level features in the shared detail view.
- `Search` for V2EX is limited compared with NGA and LINUX DO and should be treated as lower-confidence UX.

## Maintenance Rules

- Update this file when a capability is added, removed, or changes source parity.
- Update [docs/changelog.md](/Users/v/XBP/ForumHub/docs/changelog.md) alongside this file for user-visible changes.
- If a capability changes because of a deliberate product or architecture choice, also update [docs/decisions.md](/Users/v/XBP/ForumHub/docs/decisions.md).
