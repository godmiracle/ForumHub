# Todo

## Thread Detail

- Verify NGA explicit pagination against more real-world threads, especially mixed main-post plus continuation-page edge cases.
- Verify the non-lazy geometry-based NGA auto-pagination against long real threads to confirm the top anchor and footer sentinel stay stable across repeated downward paging.
- Consider whether V2EX and LINUX DO need source-native reply pagination controls once their detail APIs expose stable page contracts.
- Decide whether the page picker should remember the last manually selected page per thread during the same app session.

## Community And Sources

- Continue refining source switching and channel management polish.
- Evaluate whether community management needs clearer distinction between subscribed channels and source-provided defaults.

## Sync And Persistence

- Keep blocked users and favorites local-first until a real cross-device sync strategy is viable.
- Define migration rules before re-enabling any cloud-backed sync path.
