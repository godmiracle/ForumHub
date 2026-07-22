import Foundation
import Testing
@testable import ForumHub

@MainActor
struct ForumFeedPresentationTests {
    @Test func restoredV2EXSourceInitializesItsDefaultForumBeforeReload() throws {
        let suiteName = "ForumFeedPresentationTests-source-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(ForumSource.v2ex.rawValue, forKey: "active-forum-source-v1")

        let viewModel = ForumViewModel(sourceDefaults: defaults)

        #expect(viewModel.source == .v2ex)
        #expect(viewModel.repository.defaultChannel == .v2exHot)
        #expect(viewModel.channels.first == .v2exHot)
        #expect(viewModel.forum.id == ForumChannel.v2exHot.id)
        #expect(viewModel.forum.source == .v2ex)
    }

    @Test func parsesUnixSecondsAndMillisecondsAsSameDate() throws {
        let seconds = try #require(ForumTime.parse("1784212545"))
        let milliseconds = try #require(ForumTime.parse("1784212545000"))

        #expect(seconds == milliseconds)
        #expect(ForumTime.parse("未知时间") == nil)
        #expect(ForumTime.parse("server-time-token") == nil)
    }

    @Test func parsesISOAndFormatsFeedTimeInRequestedShape() throws {
        let date = try #require(ForumTime.parse("2026-07-16T14:15:00Z"))
        let text = ForumTime.feedText(date, timeZone: try #require(TimeZone(secondsFromGMT: 8 * 3600)))

        #expect(text == "07-16 22:15")
    }

    @Test func crossSourceFixtureUsesOneTimeSeam() throws {
        let url = try #require(Bundle(for: FixtureBundleToken.self).url(
            forResource: "cross-source-feed-times",
            withExtension: "json"
        ))
        let samples = try JSONDecoder().decode([TimeSample].self, from: Data(contentsOf: url))

        for sample in samples {
            let date = try #require(ForumTime.parse(sample.rawValue))
            #expect(ForumTime.feedText(date, timeZone: try #require(TimeZone(secondsFromGMT: 8 * 3600))) == sample.expectedText)
        }
    }

    @Test func ngaListParserKeepsStructuredTimestampWithoutDisplayingRawValue() throws {
        let json = #"{"result":[{"tid":47185513,"subject":"脱敏主题","author":"tester","postdate":1784212000,"lastpost":1784212545,"replies":9}]}"#
        let data = try #require(json.data(using: .utf8))
        let payload = try #require(ForumPayloadParser.parse(data: data, fallbackText: json, fid: -7))
        let thread = try #require(payload.threads.first)
        let presentation = try #require(FeedThreadTimePresentation.resolve(thread: thread, sortMode: .lastReply))

        #expect(thread.createdAtDate != nil)
        #expect(thread.lastReplyAtDate != nil)
        #expect(presentation.label == "回复")
        #expect(ForumTime.feedText(presentation.date).contains("1784212545") == false)
    }

    @Test func timePresentationLabelsFallbackFieldHonestly() throws {
        let created = try #require(ForumTime.parse("2026-07-16 21:00"))
        let thread = ForumThread(
            id: 1,
            title: "主题",
            summary: "",
            author: "用户",
            createdAt: "2026-07-16 21:00",
            lastReplyAt: "invalid",
            createdAtDate: created,
            lastReplyAtDate: nil,
            replyCount: 0,
            viewCount: 0,
            body: "",
            replies: []
        )

        #expect(FeedThreadTimePresentation.resolve(thread: thread, sortMode: .lastReply)?.label == "发布")
        #expect(FeedThreadTimePresentation.resolve(thread: thread, sortMode: .latestPost)?.label == "发布")
    }

    @Test func ngaGuestCookieIsExpiredButEmptyStateIsSignedOut() {
        let expired = NGALoginState(
            uid: "guest_123",
            cid: nil,
            cookieNames: ["ngaPassportUid"]
        )

        #expect(expired.sourceSessionState == .expired)
        #expect(NGALoginState.empty.sourceSessionState == .signedOut)
        #expect(expired.authSessionDescriptor.sessionState == .expired)
        #expect(expired.authSessionDescriptor.detailText?.contains("guest_123") == false)
    }

    @Test func nonAuthenticationFailuresDoNotClassifyAsExpired() {
        #expect(ForumError.fromHTTPStatus(401) == .authenticationExpired)
        #expect(ForumError.fromHTTPStatus(403) == .accessDenied)
        #expect(ForumError.fromHTTPStatus(500) == .sourceUnavailable)
        #expect(ForumError.resolve(URLError(.timedOut)) == .timeout)
    }

    @Test func pendingComposeOnlyResumesForAuthenticatedMatchingContext() throws {
        let action = PendingComposeAction(source: .nga, channelID: -7)
        let capabilities = CountingFeedRepository().capabilities

        #expect(action.canResume(source: .nga, channelID: -7, sessionState: .authenticated, capabilities: capabilities))
        #expect(!action.canResume(source: .nga, channelID: 706, sessionState: .authenticated, capabilities: capabilities))
        #expect(!action.canResume(source: .v2ex, channelID: -7, sessionState: .authenticated, capabilities: capabilities))
        #expect(!action.canResume(source: .nga, channelID: -7, sessionState: .signedOut, capabilities: capabilities))
        #expect(try #require(action.destinationURL?.absoluteString).contains("action=new"))
        #expect(try #require(action.destinationURL?.absoluteString).contains("fid=-7"))
    }

    @Test func feedPreferencesAreScopedAndDiscardUnknownChildForumKeys() throws {
        let suiteName = "ForumFeedPresentationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FeedPreferencesStore(defaults: defaults)
        let parent = ForumChannel.defaultForum
        let directory = AuthoritativeChildForumDirectory(
            parent: parent,
            children: [
                AuthoritativeChildForum(
                    stableKey: "fid:2",
                    title: "子版 A",
                    channel: ForumChannel(id: 2, title: "子版 A", nativeKey: "fid:2")
                ),
                AuthoritativeChildForum(
                    stableKey: "stid:2",
                    title: "子版 B",
                    channel: ForumChannel(id: 2, title: "子版 B", nativeKey: "stid:2")
                )
            ]
        )
        store.save(
            source: .nga,
            parent: parent,
            sortMode: .latestPost,
            filter: FeedFilterState(selectedChildForumKeys: ["fid:2", "stid:2", "fid:404"], showsPinnedThreads: false)
        )

        let restored = store.preference(source: .nga, parent: parent, directory: directory)
        let otherForum = store.preference(
            source: .nga,
            parent: ForumChannel(id: 706, title: "大时代"),
            directory: nil
        )
        let otherSource = store.preference(
            source: .v2ex,
            parent: .v2exHot,
            directory: nil
        )

        #expect(restored.sortMode == .latestPost)
        #expect(restored.filter.selectedChildForumKeys == ["fid:2", "stid:2"])
        #expect(restored.filter.showsPinnedThreads == false)
        #expect(restored.filter.activeCount == 3)
        #expect(otherForum.sortMode == .latestPost)
        #expect(otherForum.filter == FeedFilterState(selectedChildForumKeys: [], showsPinnedThreads: false))
        #expect(otherSource.sortMode == .lastReply)
        #expect(otherSource.filter == FeedFilterState())
    }

    @Test func childForumFilterPresentationCountsOnlyAuthoritativeChildrenAndSearchesLocally() {
        let children = [
            AuthoritativeChildForum(
                stableKey: "fid:570",
                title: "优惠信息",
                channel: ForumChannel(id: 570, title: "优惠信息", nativeKey: "fid:570")
            ),
            AuthoritativeChildForum(
                stableKey: "stid:47206901",
                title: "技术分析",
                channel: ForumChannel(id: 47_206_901, title: "技术分析", nativeKey: "stid:47206901")
            )
        ] + (0..<10).map { index in
            AuthoritativeChildForum(
                stableKey: "fid:\(600 + index)",
                title: "其他子版 \(index)",
                channel: ForumChannel(id: 600 + index, title: "其他子版 \(index)", nativeKey: "fid:\(600 + index)")
            )
        }
        let presentation = ChildForumFilterPresentation(
            children: children,
            selectedStableKeys: ["fid:570", "fid:999"],
            pendingNewStableKeys: ["stid:47206901", "fid:999"],
            searchText: "47206901"
        )

        #expect(presentation.selectedCount == 1)
        #expect(presentation.pendingNewCount == 1)
        #expect(presentation.needsSearch)
        #expect(presentation.filteredChildren.map(\.stableKey) == ["stid:47206901"])
        #expect(presentation.isNew("stid:47206901"))
        #expect(!presentation.isNew("fid:999"))
    }

    @Test func restoredDirectorySurfacesNewAndCancelledChildrenUntilUserAcknowledgesThem() throws {
        let repository = CountingFeedRepository()
        let viewModel = ForumViewModel(repository: repository)
        let suiteName = "ForumFeedPresentationTests-directory-notices-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AuthoritativeChildForumDirectoryStore(defaults: defaults)
        let cancelled = AuthoritativeChildForum(
            stableKey: "fid:4",
            title: "已取消子版",
            channel: ForumChannel(id: 4, title: "已取消子版", nativeKey: "fid:4")
        )
        _ = try store.synchronize(
            AuthoritativeChildForumDirectory(parent: repository.defaultChannel, children: [cancelled]),
            selectedStableKeys: [cancelled.stableKey]
        )
        let added = AuthoritativeChildForum(
            stableKey: "fid:5",
            title: "新增子版",
            channel: ForumChannel(id: 5, title: "新增子版", nativeKey: "fid:5")
        )
        _ = try store.synchronize(
            AuthoritativeChildForumDirectory(parent: repository.defaultChannel, children: [added]),
            selectedStableKeys: [cancelled.stableKey]
        )

        viewModel.restoreCachedAuthoritativeChildForumDirectory(using: store)

        #expect(viewModel.pendingNewChildForumStableKeys == [added.stableKey])
        #expect(viewModel.cancelledChildForumNotice == "已取消子版已从筛选中移除。")

        viewModel.confirmPendingNewChildForumsSeen(using: store)
        viewModel.dismissCancelledChildForumNotice()

        #expect(viewModel.pendingNewChildForumStableKeys.isEmpty)
        #expect(store.pendingNewStableKeys(for: repository.defaultChannel).isEmpty)
        #expect(viewModel.cancelledChildForumNotice == nil)
    }

    @Test func childForumStatusUsesBriefChineseFallbackMessages() {
        let unavailable = FeedChildForumStatus(isApplicable: true, hasConfirmedDirectory: false)
        let partialFailure = FeedChildForumStatus(
            isApplicable: true,
            hasConfirmedDirectory: true,
            failedChildForumCount: 2
        )

        #expect(unavailable.directoryUnavailableMessage == "子版目录暂不可用，请稍后重试。")
        #expect(partialFailure.partialFailureMessage == "部分子版暂未加载，可重试。")
    }

    @Test func authoritativeDirectoryIsTheOnlyChildSourceAndStableKeySelectionReloadsOnce() async throws {
        let repository = CountingFeedRepository()
        let viewModel = ForumViewModel(repository: repository)
        let suiteName = "ForumFeedPresentationTests-directory-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directoryStore = AuthoritativeChildForumDirectoryStore(defaults: defaults)
        await viewModel.loadChannels()

        #expect(viewModel.availableChildChannels.isEmpty)

        await viewModel.refreshAuthoritativeChildForumDirectory(using: directoryStore)

        #expect(viewModel.availableChildChannels.map(\.stableKey) == ["fid:2", "stid:2"])
        #expect(viewModel.selectedChildForumKeys.isEmpty)

        await viewModel.setSelectedChildForumKeys(["fid:2", "stid:2", "fid:404"])

        #expect(repository.requestedChannelNativeKeys == ["fid:1", "fid:2", "stid:2"])
        #expect(viewModel.selectedChildForumKeys == ["fid:2", "stid:2"])
    }

    @Test func failedChildForumKeepsTheMainForumAndSuccessfulChildrenVisible() async throws {
        let repository = PartialChildFailureRepository(failsMainForum: false)
        let viewModel = ForumViewModel(repository: repository)
        let suiteName = "ForumFeedPresentationTests-partial-child-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directoryStore = AuthoritativeChildForumDirectoryStore(defaults: defaults)

        await viewModel.refreshAuthoritativeChildForumDirectory(using: directoryStore)
        await viewModel.setSelectedChildForumKeys(["fid:2", "stid:3"])

        #expect(viewModel.threads.map(\.title) == ["主版主题", "成功子版主题"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.failedChildForumStableKeys == ["stid:3"])
        #expect(viewModel.canRetryFailedChildForums)
    }

    @Test func failedMainForumKeepsTheExistingAggregateFailureBehavior() async throws {
        let repository = PartialChildFailureRepository(failsMainForum: true)
        let viewModel = ForumViewModel(repository: repository)
        let suiteName = "ForumFeedPresentationTests-main-failure-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directoryStore = AuthoritativeChildForumDirectoryStore(defaults: defaults)

        await viewModel.refreshAuthoritativeChildForumDirectory(using: directoryStore)
        await viewModel.setSelectedChildForumKeys(["fid:2", "stid:3"])

        #expect(viewModel.threads.isEmpty)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.failedChildForumStableKeys.isEmpty)
        #expect(!viewModel.canRetryFailedChildForums)
    }

    @Test func aggregatePaginationDeduplicatesBySourceAndTopicWhileKeepingOtherChildrenAfterAPageFailure() async throws {
        let repository = AggregatePagingRepository()
        let viewModel = ForumViewModel(repository: repository)
        let suiteName = "ForumFeedPresentationTests-aggregate-pages-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directoryStore = AuthoritativeChildForumDirectoryStore(defaults: defaults)

        await viewModel.refreshAuthoritativeChildForumDirectory(using: directoryStore)
        await viewModel.setSelectedChildForumKeys(["fid:2", "stid:3"])

        #expect(viewModel.displayedThreads.map(\.id) == [400, 200, 100])
        #expect(viewModel.threads.filter { $0.id == 100 }.count == 1)
        #expect(viewModel.canLoadMore)

        await viewModel.loadNextPage()

        #expect(viewModel.displayedThreads.map(\.id) == [400, 300, 200, 100])
        #expect(viewModel.threads.filter { $0.id == 100 }.count == 1)
        #expect(viewModel.failedChildForumStableKeys == ["stid:3"])
        #expect(!viewModel.canLoadMore)
    }

    @Test func lateAggregateResultCannotOverwriteNewStableKeySelection() async throws {
        let repository = DelayedAggregateRepository()
        let viewModel = ForumViewModel(repository: repository)
        let suiteName = "ForumFeedPresentationTests-late-aggregate-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directoryStore = AuthoritativeChildForumDirectoryStore(defaults: defaults)

        await viewModel.refreshAuthoritativeChildForumDirectory(using: directoryStore)
        let olderSelection = Task { @MainActor in
            await viewModel.setSelectedChildForumKeys(["fid:2"])
        }
        for _ in 0..<100 where !repository.hasStartedOlderChildLoad {
            await Task.yield()
        }
        #expect(repository.hasStartedOlderChildLoad)

        await viewModel.setSelectedChildForumKeys(["stid:3"])
        await olderSelection.value

        #expect(viewModel.selectedChildForumKeys == ["stid:3"])
        #expect(viewModel.threads.map(\.title) == ["主版主题", "新选择子版主题"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test func directoryRefreshRemovingSelectedChildReloadsOnceAndRejectsOldGeneration() async throws {
        let repository = DirectoryCancellationAggregateRepository()
        let viewModel = ForumViewModel(repository: repository)
        let suiteName = "ForumFeedPresentationTests-directory-cancellation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directoryStore = AuthoritativeChildForumDirectoryStore(defaults: defaults)

        await viewModel.refreshAuthoritativeChildForumDirectory(using: directoryStore)
        let oldGeneration = Task { @MainActor in
            await viewModel.setSelectedChildForumKeys(["fid:2", "stid:3"])
        }
        await repository.waitUntilRemovedChildRequestStarts()

        await viewModel.refreshAuthoritativeChildForumDirectory(
            using: directoryStore,
            reloadsFeedOnSelectionChange: true
        )
        repository.finishRemovedChildRequest()
        await oldGeneration.value

        #expect(viewModel.selectedChildForumKeys == ["stid:3"])
        #expect(repository.requestedChannelNativeKeys == ["fid:1", "fid:2", "fid:1", "stid:3"])
        #expect(viewModel.threads.map(\.title) == ["主版主题", "保留子版主题"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test func virtualV2EXHotPreservesRealNodeOnFirstAndContinuationPages() async {
        let repository = V2EXVirtualHotFeedRepository()
        let viewModel = ForumViewModel(repository: repository)
        let hotTabViewModel = ForumViewModel(repository: repository)

        await viewModel.reload()
        await hotTabViewModel.switchFeed(to: .hot)

        #expect(viewModel.threads.map(\.channelTitle) == ["问与答"])
        #expect(viewModel.threads.map(\.id) == hotTabViewModel.threads.map(\.id))
        #expect(viewModel.threads.map(\.channelTitle) == hotTabViewModel.threads.map(\.channelTitle))
        #expect(viewModel.canLoadMore)

        await viewModel.loadNextPage()

        #expect(viewModel.threads.map(\.channelTitle) == ["问与答", "二手交易"])
        #expect(!viewModel.canLoadMore)
    }

    @Test func feedSortUsesStructuredDatesAndKeepsHonestFallback() throws {
        let repository = CountingFeedRepository()
        let viewModel = ForumViewModel(repository: repository)
        let olderCreated = try #require(ForumTime.parse("2026-07-15T10:00:00Z"))
        let newerCreated = try #require(ForumTime.parse("2026-07-16T10:00:00Z"))
        let newestReply = try #require(ForumTime.parse("2026-07-16T12:00:00Z"))
        viewModel.threads = [
            Self.thread(id: 1, created: olderCreated, replied: newestReply),
            Self.thread(id: 2, created: newerCreated, replied: nil)
        ]

        viewModel.feedSortMode = .latestPost
        #expect(viewModel.displayedThreads.map(\.id) == [2, 1])
        viewModel.feedSortMode = .lastReply
        #expect(viewModel.displayedThreads.map(\.id) == [1, 2])
        #expect(FeedThreadTimePresentation.resolve(thread: viewModel.displayedThreads[1], sortMode: .lastReply)?.label == "发布")
    }

    @Test func latestPostRefreshForwardsRemoteSortMode() async {
        let repository = CountingFeedRepository()
        let viewModel = ForumViewModel(repository: repository)
        viewModel.feedSortMode = .latestPost

        await viewModel.reload()

        #expect(repository.requestedSortModes == [.latestPost])
        #expect(FeedSortMode.latestPost.ngaOrderByValue == "postdatedesc")
    }

    @Test func legacySavedThreadWithoutStructuredDatesStillDecodes() throws {
        let legacy = LegacySavedForumThread(
            source: .nga,
            threadID: 7,
            title: "旧收藏",
            summary: "",
            author: "用户",
            createdAt: "2026-07-16 21:00",
            lastReplyAt: "1784212545",
            replyCount: 1,
            viewCount: 2,
            channelID: -7,
            channelTitle: "网事杂谈",
            savedAt: .now
        )
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(SavedForumThread.self, from: data)
        let thread = decoded.thread

        #expect(thread.title == "旧收藏")
        #expect(thread.createdAtDate != nil)
        #expect(thread.lastReplyAtDate != nil)
    }


    private static func thread(id: Int, created: Date, replied: Date?) -> ForumThread {
        ForumThread(
            id: id,
            title: "主题 \(id)",
            summary: "",
            author: "用户",
            createdAt: ForumTime.storageText(created),
            lastReplyAt: replied.map(ForumTime.storageText) ?? "",
            createdAtDate: created,
            lastReplyAtDate: replied,
            replyCount: 0,
            viewCount: 0,
            body: "",
            replies: []
        )
    }
}

private struct TimeSample: Decodable {
    let rawValue: String
    let expectedText: String
}

private final class FixtureBundleToken {}

@MainActor
private final class CountingFeedRepository: ThreadRepository {
    let source = ForumSource.nga
    let capabilities = ForumCapabilities(
        supportsSearch: true,
        supportsFavorites: false,
        supportsReply: false,
        supportsReplyTargeting: false,
        supportsAuthentication: false,
        supportsFeedPagination: true,
        supportsCreateThread: true
    )
    let defaultChannel = ForumChannel(id: 1, title: "主版", nativeKey: "fid:1")
    private(set) var requestedChannelNativeKeys: [String] = []
    private(set) var requestedSortModes: [FeedSortMode] = []

    func fetchChannels() async throws -> [ForumChannel] {
        [defaultChannel, ForumChannel(id: 404, title: "全站无关栏目", nativeKey: "fid:404")]
    }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        requestedChannelNativeKeys.append(channel.nativeKey)
        return result(channel: channel)
    }

    func fetchForum(
        channel: ForumChannel,
        page: Int,
        sortMode: FeedSortMode
    ) async throws -> ThreadFetchResult {
        requestedSortModes.append(sortMode)
        return try await fetchForum(channel: channel, page: page)
    }

    func fetchAuthoritativeChildForumDirectory(
        parent: ForumChannel
    ) async throws -> AuthoritativeChildForumDirectory? {
        guard parent == defaultChannel else { return nil }
        return AuthoritativeChildForumDirectory(
            parent: parent,
            children: [
                AuthoritativeChildForum(
                    stableKey: "fid:2",
                    title: "普通子版",
                    channel: ForumChannel(id: 2, title: "普通子版", nativeKey: "fid:2")
                ),
                AuthoritativeChildForum(
                    stableKey: "stid:2",
                    title: "主题子版",
                    channel: ForumChannel(id: 2, title: "主题子版", nativeKey: "stid:2")
                )
            ]
        )
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult { result(channel: defaultChannel) }
    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult { result(channel: defaultChannel) }
    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult { result(channel: defaultChannel) }
    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult { fatalError() }
    func addFavoriteThread(tid: Int) async throws {}
    func removeFavoriteThread(tid: Int) async throws {}
    func replyThread(tid: Int, target: ThreadReplyTarget, content: String, attachments: [ReplyAttachmentUpload]) async throws {}

    private func result(channel: ForumChannel) -> ThreadFetchResult {
        ThreadFetchResult(
            payload: ForumPayload(
                forum: ForumSummary(id: channel.id, title: channel.title, subtitle: "", todayPosts: 0, onlineUsers: 0),
                channels: [defaultChannel],
                pinned: [],
                threads: []
            ),
            rawText: "",
            hasMore: false
        )
    }
}

@MainActor
private final class PartialChildFailureRepository: ThreadRepository {
    enum Failure: Error {
        case unavailable
    }

    let source = ForumSource.nga
    let capabilities = ForumCapabilities(
        supportsSearch: true,
        supportsFavorites: false,
        supportsReply: false,
        supportsReplyTargeting: false,
        supportsAuthentication: false,
        supportsFeedPagination: true
    )
    let defaultChannel = ForumChannel(id: 1, title: "主版", nativeKey: "fid:1")
    private let failsMainForum: Bool

    init(failsMainForum: Bool) {
        self.failsMainForum = failsMainForum
    }

    func fetchChannels() async throws -> [ForumChannel] { [defaultChannel] }

    func fetchAuthoritativeChildForumDirectory(
        parent: ForumChannel
    ) async throws -> AuthoritativeChildForumDirectory? {
        guard parent == defaultChannel else { return nil }
        return AuthoritativeChildForumDirectory(
            parent: parent,
            children: [
                AuthoritativeChildForum(
                    stableKey: "fid:2",
                    title: "成功子版",
                    channel: ForumChannel(id: 2, title: "成功子版", nativeKey: "fid:2")
                ),
                AuthoritativeChildForum(
                    stableKey: "stid:3",
                    title: "失败子版",
                    channel: ForumChannel(id: 3, title: "失败子版", nativeKey: "stid:3")
                )
            ]
        )
    }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        if channel.nativeKey == defaultChannel.nativeKey, failsMainForum {
            throw Failure.unavailable
        }
        if channel.nativeKey == "stid:3" {
            throw Failure.unavailable
        }
        let title = channel.nativeKey == defaultChannel.nativeKey ? "主版主题" : "成功子版主题"
        let thread = ForumThread(
            id: channel.id,
            title: title,
            summary: "",
            author: "测试用户",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "",
            replies: []
        )
        return ThreadFetchResult(
            payload: ForumPayload(
                forum: ForumSummary(id: channel.id, title: channel.title, subtitle: "", todayPosts: 0, onlineUsers: 1),
                channels: [defaultChannel],
                pinned: [],
                threads: [thread]
            ),
            rawText: "",
            hasMore: false
        )
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult { try await fetchForum(channel: defaultChannel, page: page) }
    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult { fatalError() }
    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult { fatalError() }
    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult { fatalError() }
    func addFavoriteThread(tid: Int) async throws {}
    func removeFavoriteThread(tid: Int) async throws {}
    func replyThread(tid: Int, target: ThreadReplyTarget, content: String, attachments: [ReplyAttachmentUpload]) async throws {}
}

@MainActor
private final class AggregatePagingRepository: ThreadRepository {
    enum Failure: Error {
        case unavailable
    }

    let source = ForumSource.nga
    let capabilities = ForumCapabilities(
        supportsSearch: true,
        supportsFavorites: false,
        supportsReply: false,
        supportsReplyTargeting: false,
        supportsAuthentication: false,
        supportsFeedPagination: true
    )
    let defaultChannel = ForumChannel(id: 1, title: "主版", nativeKey: "fid:1")

    func fetchChannels() async throws -> [ForumChannel] { [defaultChannel] }

    func fetchAuthoritativeChildForumDirectory(
        parent: ForumChannel
    ) async throws -> AuthoritativeChildForumDirectory? {
        guard parent == defaultChannel else { return nil }
        return AuthoritativeChildForumDirectory(
            parent: parent,
            children: [
                child(stableKey: "fid:2", id: 2, title: "子版 A"),
                child(stableKey: "stid:3", id: 3, title: "子版 B")
            ]
        )
    }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        switch (channel.nativeKey, page) {
        case ("fid:1", 1):
            return result(channel: channel, threads: [thread(id: 100, title: "主版重复主题", time: 1)], hasMore: true)
        case ("fid:2", 1):
            return result(channel: channel, threads: [
                thread(id: 100, title: "子版重复主题", time: 1),
                thread(id: 200, title: "子版 A 主题", time: 2)
            ], hasMore: true)
        case ("stid:3", 1):
            return result(channel: channel, threads: [thread(id: 400, title: "子版 B 主题", time: 4)], hasMore: true)
        case ("fid:1", 2):
            return result(channel: channel, threads: [thread(id: 100, title: "后续页重复主题", time: 1)], hasMore: false)
        case ("fid:2", 2):
            return result(channel: channel, threads: [thread(id: 300, title: "子版 A 后续主题", time: 3)], hasMore: false)
        case ("stid:3", 2):
            throw Failure.unavailable
        default:
            return result(channel: channel, threads: [], hasMore: false)
        }
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult { try await fetchForum(channel: defaultChannel, page: page) }
    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult { fatalError() }
    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult { fatalError() }
    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult { fatalError() }
    func addFavoriteThread(tid: Int) async throws {}
    func removeFavoriteThread(tid: Int) async throws {}
    func replyThread(tid: Int, target: ThreadReplyTarget, content: String, attachments: [ReplyAttachmentUpload]) async throws {}

    private func child(stableKey: String, id: Int, title: String) -> AuthoritativeChildForum {
        AuthoritativeChildForum(
            stableKey: stableKey,
            title: title,
            channel: ForumChannel(id: id, title: title, nativeKey: stableKey)
        )
    }

    private func result(channel: ForumChannel, threads: [ForumThread], hasMore: Bool) -> ThreadFetchResult {
        ThreadFetchResult(
            payload: ForumPayload(
                forum: ForumSummary(id: channel.id, title: channel.title, subtitle: "", todayPosts: 0, onlineUsers: threads.count),
                channels: [defaultChannel],
                pinned: [],
                threads: threads
            ),
            rawText: "",
            hasMore: hasMore
        )
    }

    private func thread(id: Int, title: String, time: TimeInterval) -> ForumThread {
        let date = Date(timeIntervalSince1970: time)
        return ForumThread(
            id: id,
            title: title,
            summary: "",
            author: "测试用户",
            createdAt: ForumTime.storageText(date),
            lastReplyAt: ForumTime.storageText(date),
            createdAtDate: date,
            lastReplyAtDate: date,
            replyCount: 0,
            viewCount: 0,
            body: "",
            replies: []
        )
    }
}

@MainActor
private final class DelayedAggregateRepository: ThreadRepository {
    let source = ForumSource.nga
    let capabilities = ForumCapabilities(
        supportsSearch: true,
        supportsFavorites: false,
        supportsReply: false,
        supportsReplyTargeting: false,
        supportsAuthentication: false,
        supportsFeedPagination: true
    )
    let defaultChannel = ForumChannel(id: 1, title: "主版", nativeKey: "fid:1")
    private(set) var hasStartedOlderChildLoad = false

    func fetchChannels() async throws -> [ForumChannel] { [defaultChannel] }

    func fetchAuthoritativeChildForumDirectory(
        parent: ForumChannel
    ) async throws -> AuthoritativeChildForumDirectory? {
        guard parent == defaultChannel else { return nil }
        return AuthoritativeChildForumDirectory(
            parent: parent,
            children: [
                child(stableKey: "fid:2", id: 2, title: "旧选择子版"),
                child(stableKey: "stid:3", id: 3, title: "新选择子版")
            ]
        )
    }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        if channel.nativeKey == "fid:2" {
            hasStartedOlderChildLoad = true
            await delayIgnoringCancellation()
        }
        let title: String
        switch channel.nativeKey {
        case "fid:1": title = "主版主题"
        case "fid:2": title = "旧选择子版主题"
        default: title = "新选择子版主题"
        }
        let thread = ForumThread(
            id: channel.id,
            title: title,
            summary: "",
            author: "测试用户",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "",
            replies: []
        )
        return ThreadFetchResult(
            payload: ForumPayload(
                forum: ForumSummary(id: channel.id, title: channel.title, subtitle: "", todayPosts: 0, onlineUsers: 1),
                channels: [defaultChannel],
                pinned: [],
                threads: [thread]
            ),
            rawText: "",
            hasMore: false
        )
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult { try await fetchForum(channel: defaultChannel, page: page) }
    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult { fatalError() }
    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult { fatalError() }
    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult { fatalError() }
    func addFavoriteThread(tid: Int) async throws {}
    func removeFavoriteThread(tid: Int) async throws {}
    func replyThread(tid: Int, target: ThreadReplyTarget, content: String, attachments: [ReplyAttachmentUpload]) async throws {}

    private func child(stableKey: String, id: Int, title: String) -> AuthoritativeChildForum {
        AuthoritativeChildForum(
            stableKey: stableKey,
            title: title,
            channel: ForumChannel(id: id, title: title, nativeKey: stableKey)
        )
    }

    private func delayIgnoringCancellation() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                continuation.resume()
            }
        }
    }
}

@MainActor
private final class DirectoryCancellationAggregateRepository: ThreadRepository {
    let source = ForumSource.nga
    let capabilities = ForumCapabilities(
        supportsSearch: true,
        supportsFavorites: false,
        supportsReply: false,
        supportsReplyTargeting: false,
        supportsAuthentication: false,
        supportsFeedPagination: true
    )
    let defaultChannel = ForumChannel(id: 1, title: "主版", nativeKey: "fid:1")
    private(set) var requestedChannelNativeKeys: [String] = []
    private var directoryRequestCount = 0
    private var removedChildRequestStarted = false
    private var removedChildStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var removedChildCompletion: CheckedContinuation<Void, Never>?

    func fetchChannels() async throws -> [ForumChannel] { [defaultChannel] }

    func fetchAuthoritativeChildForumDirectory(
        parent: ForumChannel
    ) async throws -> AuthoritativeChildForumDirectory? {
        guard parent == defaultChannel else { return nil }
        directoryRequestCount += 1
        let children = directoryRequestCount == 1
            ? [
                child(stableKey: "fid:2", id: 2, title: "已取消子版"),
                child(stableKey: "stid:3", id: 3, title: "保留子版")
            ]
            : [child(stableKey: "stid:3", id: 3, title: "保留子版")]
        return AuthoritativeChildForumDirectory(parent: parent, children: children)
    }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        requestedChannelNativeKeys.append(channel.nativeKey)
        if channel.nativeKey == "fid:2" {
            removedChildRequestStarted = true
            removedChildStartWaiters.forEach { $0.resume() }
            removedChildStartWaiters = []
            await withCheckedContinuation { continuation in
                removedChildCompletion = continuation
            }
        }
        let title = channel.nativeKey == defaultChannel.nativeKey ? "主版主题" : "保留子版主题"
        return result(channel: channel, title: title)
    }

    func waitUntilRemovedChildRequestStarts() async {
        guard !removedChildRequestStarted else { return }
        await withCheckedContinuation { continuation in
            removedChildStartWaiters.append(continuation)
        }
    }

    func finishRemovedChildRequest() {
        removedChildCompletion?.resume()
        removedChildCompletion = nil
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult { try await fetchForum(channel: defaultChannel, page: page) }
    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult { fatalError() }
    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult { fatalError() }
    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult { fatalError() }
    func addFavoriteThread(tid: Int) async throws {}
    func removeFavoriteThread(tid: Int) async throws {}
    func replyThread(tid: Int, target: ThreadReplyTarget, content: String, attachments: [ReplyAttachmentUpload]) async throws {}

    private func child(stableKey: String, id: Int, title: String) -> AuthoritativeChildForum {
        AuthoritativeChildForum(
            stableKey: stableKey,
            title: title,
            channel: ForumChannel(id: id, title: title, nativeKey: stableKey)
        )
    }

    private func result(channel: ForumChannel, title: String) -> ThreadFetchResult {
        ThreadFetchResult(
            payload: ForumPayload(
                forum: ForumSummary(id: channel.id, title: channel.title, subtitle: "", todayPosts: 0, onlineUsers: 1),
                channels: [defaultChannel],
                pinned: [],
                threads: [
                    ForumThread(
                        id: channel.id,
                        title: title,
                        summary: "",
                        author: "测试用户",
                        lastReplyAt: "",
                        replyCount: 0,
                        viewCount: 0,
                        body: "",
                        replies: []
                    )
                ]
            ),
            rawText: "",
            hasMore: false
        )
    }
}

private struct V2EXVirtualHotFeedRepository: ThreadRepository {
    let source = ForumSource.v2ex
    let capabilities = ForumCapabilities(
        supportsSearch: false,
        supportsFavorites: false,
        supportsReply: false,
        supportsReplyTargeting: false,
        supportsAuthentication: false,
        supportsFeedPagination: true
    )
    let defaultChannel = ForumChannel.v2exHot

    func fetchChannels() async throws -> [ForumChannel] { [defaultChannel] }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        let realChannel = page == 1
            ? ForumChannel(id: 12, title: "问与答", source: .v2ex, nativeKey: "qna")
            : ForumChannel(id: 65, title: "二手交易", source: .v2ex, nativeKey: "all4all")
        let thread = ForumThread(
            id: page,
            title: "聚合主题 \(page)",
            summary: "",
            author: "tester",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "",
            replies: [],
            source: .v2ex
        ).withChannel(realChannel)
        return ThreadFetchResult(
            payload: ForumPayload(
                forum: ForumSummary(
                    id: channel.id,
                    title: channel.title,
                    subtitle: "虚拟聚合 Feed",
                    todayPosts: 0,
                    onlineUsers: 1,
                    source: .v2ex
                ),
                channels: [channel],
                pinned: [],
                threads: [thread]
            ),
            rawText: "",
            hasMore: page == 1
        )
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult {
        try await fetchForum(channel: defaultChannel, page: page)
    }
    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult { fatalError() }
    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult { fatalError() }
    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult { fatalError() }
    func addFavoriteThread(tid: Int) async throws {}
    func removeFavoriteThread(tid: Int) async throws {}
    func replyThread(tid: Int, target: ThreadReplyTarget, content: String, attachments: [ReplyAttachmentUpload]) async throws {}
}

private struct LegacySavedForumThread: Codable {
    let source: ForumSource
    let threadID: Int
    let title: String
    let summary: String
    let author: String
    let createdAt: String
    let lastReplyAt: String
    let replyCount: Int
    let viewCount: Int
    let channelID: Int?
    let channelTitle: String?
    let savedAt: Date
}
