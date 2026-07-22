## Verification Report: redesign-nga-channel-management-and-subscribe-authoritative-child-forums-to-home

### Summary

| Dimension | Status |
|---|---|
| Completeness | 29/29 tasks complete; 8/8 requirements mapped |
| Correctness | 8/8 requirements implemented; 30 scenarios assessed; all verification gates pass |
| Coherence | Design decisions and the canonical channel identity contract are reflected in production and UI automation |

VERIFY VERDICT: CLEAN — Blocker:0 Major:0 Minor:0 Trivial:0

### Verification scope and evidence

- Read all change artifacts: `proposal.md`, `design.md`, both delta specs, and `tasks.md`.
- Confirmed the canonical channel identity seam in `ForumHub/Domain/ForumModels.swift:184` and its use in Home navigation, paging, subscriptions, ordering, and Community rows.
- Confirmed ordinary-channel and authoritative-child catalog composition in `ForumHub/Features/Community/ForumChannelCatalog.swift:45`, including canonical deduplication and parent context.
- Confirmed versioned subscription migration, legacy snapshot retention, independent `stid` persistence, cancellation cleanup, and at-least-one fallback in `ForumHub/Features/ForumManagement/ForumSubscriptionStore.swift:30`, `ForumHub/Features/ForumManagement/ForumSubscriptionStore.swift:76`, and `ForumHub/Features/ForumManagement/ForumSubscriptionStore.swift:178`.
- Confirmed Home consumes the unified catalog and independently cleans parent-filter and Home-subscription state after a complete cancellation in `ForumHub/ContentView.swift:381` and `ForumHub/ContentView.swift:459`.
- Confirmed authoritative directory cache/refresh lifecycle is independent of the currently selected NGA Feed while aggregation remains limited to the parent channel in `ForumHub/Features/ForumFeed/ForumViewModel.swift:444`, `ForumHub/Features/ForumFeed/ForumViewModel.swift:459`, and `ForumHub/Features/ForumFeed/ForumViewModel.swift:626`.
- Confirmed Community information hierarchy, local search, empty/unavailable states, separate open/subscribe controls, explicit reorder mode, minimum hit targets, and accessibility labels in `ForumHub/Features/Community/CommunityView.swift:55`, `ForumHub/Features/Community/CommunityView.swift:74`, `ForumHub/Features/Community/CommunityView.swift:102`, and `ForumHub/Features/Community/CommunityView.swift:143`.
- Confirmed the independent `stid` Web list regression fix parses `tr.topicrow` metadata instead of the auxiliary “打开新窗口” link in `ForumHub/Data/NGA/Parsers/WebForumParser.swift:4` and `ForumHub/Data/NGA/Parsers/WebForumParser.swift:77`.
- Confirmed focused coverage in `ForumHubTests/ForumChannelCatalogTests.swift:7`, `ForumHubTests/ForumFeedPresentationTests.swift:117`, `ForumHubTests/ForumFeedPresentationTests.swift:252`, `ForumHubTests/ForumFeedPresentationTests.swift:331`, `ForumHubTests/ForumFeedPresentationTests.swift:356`, `ForumHubTests/NGAAuthoritativeChildForumParserTests.swift:6`, `ForumHubTests/RequestGenerationTests.swift:23`, and `ForumHubTests/ForumHubTests.swift:550`.
- The user completed physical-device functional acceptance and confirmed the repaired `[股市]技术分析` title/author presentation as normal.
- Updated all affected UI channel queries to the production `forum-channel-<canonicalKey>` contract; no raw numeric `forum-channel--<id>` query remains.
- On physical device `哥谭之王` (`00008150-001A4D5E1428401C`), all 192 Swift Testing tests and all 28 UI tests passed; the complete `xcodebuild ... test` command exited successfully.
- `rasen validate "redesign-nga-channel-management-and-subscribe-authoritative-child-forums-to-home" --strict --json` passed with no issues.
- `git diff --check` passed.

### Requirement mapping

1. **栏目目录组合普通栏目与权威子版** — covered by the catalog builder, source isolation, canonical deduplication, authoritative parent context, and catalog tests.
2. **栏目搜索覆盖可发现目录** — covered by catalog searchable text/matching and Community search/empty state; title, numeric ID, `stid:` key, canonical key, and parent context are present.
3. **权威子版可以独立订阅到首页** — covered by canonical subscription persistence, unified Home catalog projection, restoration, removal, and at-least-one protection.
4. **独立子版使用种类保持的浏览目标** — covered by `fid`/`stid` canonical identity, direct `ForumChannel` navigation, Web `stid` loading, and generation guards.
5. **旧订阅无损迁移到规范化身份** — covered by v4/v2 storage, legacy v3/v1 reads, canonical normalization, deduplication, and preservation of legacy keys.
6. **权威目录变化安全更新首页订阅** — covered by complete-snapshot synchronization, fail-closed refresh, independent cancellation consumers, rename-by-stable-key behavior, and one-time notices.
7. **栏目页按管理任务重建信息层级** — covered by the rewritten Community screen and the user's physical-device search/add/restart/order/browse/remove/filter-isolation/Dynamic Type/VoiceOver acceptance.
8. **首页独立子版订阅与聚合筛选互不联动** — covered by separate stores, separate write paths, direct-vs-aggregate request semantics, and state-isolation tests.

### Blocker

- None.

### Major

- None.

#### Resolved V-001: Canonical channel accessibility identifiers synchronized with UI tests

- NGA default queries now use `forum-channel-nga:fid:-7`.
- V2EX source-switch and restored-Hot queries now use `forum-channel-v2ex:hot`.
- The four affected focused UI tests passed on the connected physical device.
- The complete physical-device test command passed with 192 Swift Testing tests and 28 UI tests.

### Minor

- None.

### Trivial

- None.

### Final assessment

No missing task or requirement implementation was found. The user-visible change passed manual physical-device acceptance, the UI automation contract now matches the intentional canonical identifier migration, and the complete physical-device test gate is green.

VERIFY VERDICT: CLEAN — Blocker:0 Major:0 Minor:0 Trivial:0

TEST EVIDENCE
- command: `env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project ForumHub.xcodeproj -scheme ForumHub -configuration Debug -destination 'platform=iOS,id=00008150-001A4D5E1428401C' -derivedDataPath /tmp/ForumHubVerifyDerivedData test`
- result: pass — 192 Swift Testing tests and 28 UI tests; exit code 0; `.xcresult`: `/tmp/ForumHubVerifyDerivedData/Logs/Test/Test-ForumHub-2026.07.22_14-09-53-+0800.xcresult`
- tree: 1be9c24fdea7056c4d7e1b0872bfcf3f0eee62cb
