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

    @Test func feedPreferencesAreScopedAndDiscardUnknownChildIDs() throws {
        let suiteName = "ForumFeedPresentationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FeedPreferencesStore(defaults: defaults)
        store.save(
            source: .nga,
            channelID: -7,
            sortMode: .latestPost,
            filter: FeedFilterState(selectedChildChannelIDs: [1, 2], showsPinnedThreads: false)
        )

        let restored = store.preference(source: .nga, channelID: -7, validChildChannelIDs: [2, 3])
        let otherForum = store.preference(source: .nga, channelID: 706, validChildChannelIDs: [1, 2])
        let otherSource = store.preference(source: .v2ex, channelID: -20_002, validChildChannelIDs: [])

        #expect(restored.sortMode == .latestPost)
        #expect(restored.filter.selectedChildChannelIDs == [2])
        #expect(restored.filter.showsPinnedThreads == false)
        #expect(restored.filter.activeCount == 2)
        #expect(otherForum.sortMode == .latestPost)
        #expect(otherForum.filter == FeedFilterState(selectedChildChannelIDs: [], showsPinnedThreads: false))
        #expect(otherSource.sortMode == .lastReply)
        #expect(otherSource.filter == FeedFilterState())
    }

    @Test func applyingMultipleChildFiltersTriggersOnlyOneFeedReload() async {
        let repository = CountingFeedRepository()
        let viewModel = ForumViewModel(repository: repository)
        await viewModel.loadChannels()

        await viewModel.setSelectedChildChannels([2, 3])

        #expect(repository.requestedChannelIDs == [1, 2, 3])
        #expect(viewModel.selectedChildChannelIDs == [2, 3])
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
    let defaultChannel = ForumChannel(id: 1, title: "主版")
    private(set) var requestedChannelIDs: [Int] = []

    func fetchChannels() async throws -> [ForumChannel] {
        [defaultChannel, ForumChannel(id: 2, title: "子版 A"), ForumChannel(id: 3, title: "子版 B")]
    }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        requestedChannelIDs.append(channel.id)
        return result(channel: channel)
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
