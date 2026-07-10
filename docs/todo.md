# Todo

## Thread Detail

### ForumHub Code Review Checklist

- [x] Split `ThreadDetailView` presentation into focused UI components.
- [x] Add cancellable content-load tasks and request generations for refresh, page jumps, and continuation loading.
- [x] Cache displayed replies and page-entry presentation data to reduce repeated scroll-time derivation.
- [x] Establish `ForumError` and use it as the first user-facing error model in thread detail.
- [x] Introduce shared `ForumGlass` components and migrate thread-detail floating controls plus the feed refresh banner.
- [x] Replace machine-specific README links with repository-relative documentation links.
- [ ] Replace the thread-detail `.nga` pagination check with an explicit repository pagination capability.
- [ ] Move thread-detail loading, pagination, reply, and favorite state into a dedicated `ThreadDetailViewModel`.
- [ ] Run the implemented NGA pagination-merge regression tests for duplicate replies, main-post removal, and multi-page jumps after restoring the test target.
- [ ] Extend `ForumError` presentation to feed, search, account, and media flows.
- [ ] Fix test-target signing and restore the missing `ThreadDetailDirectPaginationAutoAdvancePolicy` test dependency so the full suite can run on device.
- [ ] Measure long-thread non-lazy rendering and memory usage on a physical device.

### Deferred By Decision

- Xcode project format compatibility: intentionally not planned. The project remains in the Xcode 27 beta format until a stable Xcode toolchain is installed and a separate migration decision is made.

- Verify NGA continuous detail pagination against more real-world threads, especially mixed main-post plus continuation-page edge cases.
- Verify the near-end-reply NGA auto-pagination and page-anchor visible-page tracking against long real threads to confirm repeated downward loading stays smooth and reliable.
- Verify the continuous NGA reading flow stays visually seamless on device: no mid-stream load-next-page card, only a final end-of-thread state once no more replies remain.
- Verify NGA per-floor reply submission on device against real threads to confirm the current `action=quote + pid + prefilled content` flow matches the live site contract across more quote formats.
- Consider whether V2EX and LINUX DO need source-native reply pagination controls once their detail APIs expose stable page contracts.
- Decide whether the page picker should remember the last manually selected page per thread during the same app session.
- Decide how the floating page control should behave when only-author mode or reverse order hides some page anchors.

## Community And Sources

- Continue refining source switching and channel management polish.
- Evaluate whether community management needs clearer distinction between subscribed channels and source-provided defaults.

## Feed

- [x] Add cancellable feed-load tasks and request generations so stale Home/Hot responses cannot overwrite the active tab.
- [x] Route TabView reselection as a target-specific action so Home and Hot return immediately to their own feed top while refreshing.
- Evaluate whether the first forum-feed loading state should stay as a centered spinner or evolve into a lightweight skeleton if real-device startup still feels abrupt.

## Images And Media

- Measure whether viewport-aware inline GIF throttling plus preview downsampling is enough, or whether the remaining active GIFs still need a lighter playback path than `WKWebView`.

## Sync And Persistence

- Keep blocked users and favorites local-first until a real cross-device sync strategy is viable.
- Define migration rules before re-enabling any cloud-backed sync path.

## Account And Session

- Verify the shared `AuthSessionDescriptor` and auth registry cover future session states such as expired tokens, partial cookie sync, and reconnect-required errors without reintroducing source-specific view branching.
- Decide whether the top NGA account card should also migrate onto the shared session-descriptor path, or intentionally remain a source-native detail card.
