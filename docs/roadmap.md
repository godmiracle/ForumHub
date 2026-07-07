# Roadmap

## Near Term

- Stand up the Flutter rebuild skeleton and shared domain boundaries in a separate app directory
- Deliver a read-only Flutter MVP covering source switching, feed browsing, thread detail, and NGA manual pagination
- Improve thread detail pagination feel, including scroll anchoring after loading more replies
- Continue stabilizing NGA detail parsing and fallback behavior
- Add retry affordances for image and GIF loading failures
- Refine feed and detail loading-state UX

## Mid Term

- Migrate local product features such as favorites, history, blocked users, and channel subscriptions into Flutter
- Migrate authenticated flows for NGA, V2EX, and LINUX DO into Flutter
- Improve sync strategy for favorites, blocked users, and reading state
- Expand module-level tests around parsers and pagination
- Improve source capability surfacing so unsupported actions are clearer
- Add better diagnostics around request cancellation and pagination behavior

## Later

- Evaluate cutover readiness once Flutter covers the primary reading path and key account flows
- Revisit cloud sync once account and entitlement constraints are resolved
- Explore a cleaner module split for shared account and source settings
- Add versioned release notes and more formal migration documentation
