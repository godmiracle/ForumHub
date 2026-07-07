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

## Flutter Rebuild

- Port the read-only feed and thread-detail flow first, with NGA manual pagination as the initial high-value detail feature.
- Verify the new Flutter NGA Web 登录 flow on device end to end: login success, cookie sync success, feed request carries account cookies, logout clears both shared and WebKit cookie state.
- Decide whether the NGA session layer should persist login-state snapshots locally for faster account-tab rendering before the next explicit cookie sync.
- Add fixture or integration coverage for the Flutter session epoch path so future account features do not silently stop invalidating feed/detail state after login changes.
- Consider whether the custom Flutter glass tab bar should support source-aware badges or quick account-state indicators once favorites and replies migrate over.
- Add fixture coverage for real-world NGA edge cases such as nested JSON strings, duplicate continuation rows, and missing floor metadata.
- Add the first real Flutter state layer for source selection and subscribed channel loading.
- Replace the current mock-only `Home` state with a repository seam that can swap from mock data to real source adapters without rewriting widgets.
- Define the Flutter feed card component contract so thread rows can be reused by favorites, history, and search later.
- Replace the current mock thread-detail controller with a repository seam that can swap page fetches from mock data to real NGA detail adapters.
- Define the Flutter thread-detail state machine boundary for page jumps, visible page tracking, only-author mode, and reverse-order presentation.
- Define how cookie-backed login state will be bridged between WebView and HTTP clients before migrating NGA and LINUX DO auth flows.
