# Todo

## Thread Detail

- Verify NGA continuous detail pagination against more real-world threads, especially mixed main-post plus continuation-page edge cases.
- Verify the non-lazy geometry-based NGA auto-pagination and page-anchor visible-page tracking against long real threads to confirm the top anchor and footer sentinel stay stable across repeated downward loading.
- Verify the continuous NGA reading flow stays visually seamless on device: no mid-stream load-next-page card, only a final end-of-thread state once no more replies remain.
- Consider whether V2EX and LINUX DO need source-native reply pagination controls once their detail APIs expose stable page contracts.
- Decide whether the page picker should remember the last manually selected page per thread during the same app session.
- Decide how the floating page control should behave when only-author mode or reverse order hides some page anchors.

## Community And Sources

- Continue refining source switching and channel management polish.
- Evaluate whether community management needs clearer distinction between subscribed channels and source-provided defaults.

## Sync And Persistence

- Keep blocked users and favorites local-first until a real cross-device sync strategy is viable.
- Define migration rules before re-enabling any cloud-backed sync path.
