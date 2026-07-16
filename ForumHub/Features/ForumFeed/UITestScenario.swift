import Foundation

enum UITestScenario: String, CaseIterable {
    case defaultFeed = "UITEST_DEFAULT_FEED"
    case sourceSwitch = "UITEST_SOURCE_SWITCH"
    case pagedThread = "UITEST_PAGED_THREAD"
    case authenticatedFeed = "UITEST_AUTHENTICATED_FEED"
    case expiredFeed = "UITEST_EXPIRED_FEED"
    case v2exRestoredHot = "UITEST_V2EX_RESTORED_HOT"

    static var current: UITestScenario? {
        let arguments = ProcessInfo.processInfo.arguments
        return allCases.first { arguments.contains($0.rawValue) }
    }

    @MainActor
    func makeViewModel() -> ForumViewModel {
        switch self {
        case .pagedThread:
            return .pagedPreview()
        case .v2exRestoredHot:
            let repository = UITestRefreshTrackingRepository(source: .v2ex)
            let viewModel = ForumViewModel(
                repositories: [.v2ex: repository],
                initialSource: .v2ex
            )
            viewModel.sessionState = .signedOut
            viewModel.forum = ForumSummary(
                id: repository.defaultChannel.id,
                title: repository.defaultChannel.title,
                subtitle: "固定 UI Test V2EX 最热短列表",
                todayPosts: 0,
                onlineUsers: 1,
                source: .v2ex
            )
            viewModel.channels = [repository.defaultChannel]
            let realChannel = ForumChannel(
                id: 12,
                title: "问与答",
                source: .v2ex,
                nativeKey: "qna"
            )
            viewModel.threads = (0..<10).map { offset in
                markerThread(
                    id: 991_100 + offset,
                    title: "V2EX 聚合初始主题 \(offset + 1)",
                    source: .v2ex
                ).withChannel(realChannel)
            }
            viewModel.canLoadMore = true
            viewModel.hasLoadedInitialFeed = true
            return viewModel
        case .defaultFeed, .sourceSwitch, .authenticatedFeed, .expiredFeed:
            let repositories: [ForumSource: any ThreadRepository] = [
                .nga: UITestRefreshTrackingRepository(source: .nga),
                .v2ex: MockThreadRepository(source: .v2ex),
                .linuxDo: MockThreadRepository(source: .linuxDo)
            ]
            let viewModel = ForumViewModel(repositories: repositories, initialSource: .nga)
            switch self {
            case .authenticatedFeed:
                viewModel.isAuthenticated = true
                viewModel.sessionState = .authenticated
            case .expiredFeed:
                viewModel.isAuthenticated = false
                viewModel.sessionState = .expired
            case .defaultFeed, .sourceSwitch:
                viewModel.isAuthenticated = false
                viewModel.sessionState = .signedOut
            case .pagedThread, .v2exRestoredHot:
                break
            }
            viewModel.loginState = .empty
            viewModel.forum = ForumPayload.mock.forum
            viewModel.channels = ForumPayload.mock.channels
            viewModel.pinnedThreads = ForumPayload.mock.pinned
            viewModel.threads = ForumPayload.mock.threads + (0..<12).map { index in
                ForumThread(
                    id: 91_000 + index,
                    title: "用于验证长列表折叠的主题 \(index + 1)",
                    summary: "固定 UI Test 数据",
                    author: "测试用户",
                    createdAt: "2026-07-16 20:\(String(format: "%02d", index))",
                    lastReplyAt: "2026-07-16 21:\(String(format: "%02d", index))",
                    replyCount: index,
                    viewCount: 100 + index,
                    body: "",
                    replies: []
                )
            }
            viewModel.hasLoadedInitialFeed = true
            return viewModel
        }
    }

    private func markerThread(id: Int, title: String, source: ForumSource) -> ForumThread {
        ForumThread(
            id: id,
            title: title,
            summary: "固定 UI Test 数据",
            author: "测试用户",
            createdAt: "2026-07-17 10:00",
            lastReplyAt: "2026-07-17 10:01",
            replyCount: 1,
            viewCount: 1,
            body: "固定 UI Test 正文",
            replies: [],
            source: source
        )
    }
}

private struct UITestRefreshTrackingRepository: ThreadRepository {
    let source: ForumSource
    var capabilities: ForumCapabilities { MockThreadRepository(source: source).capabilities }
    var defaultChannel: ForumChannel {
        switch source {
        case .nga: .defaultForum
        case .v2ex: .v2exHot
        case .linuxDo: .linuxDoLatest
        }
    }

    func fetchChannels() async throws -> [ForumChannel] {
        source == .nga ? ForumPayload.mock.channels : [defaultChannel]
    }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        if source == .v2ex, channel.nativeKey == "hot", page > 1 {
            let realChannel = ForumChannel(
                id: 65,
                title: "二手交易",
                source: .v2ex,
                nativeKey: "all4all"
            )
            return result(
                id: 990_200 + page,
                title: "V2EX 聚合已加载更多新帖",
                channel: channel,
                threadChannel: realChannel
            )
        }
        return result(id: 990_101, title: "首页下拉刷新已完成", channel: channel)
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult {
        if source == .v2ex, page > 1 {
            return result(
                id: 990_200 + page,
                title: "V2EX 聚合已加载更多新帖",
                channel: defaultChannel
            )
        }
        return result(id: 990_102, title: "热门下拉刷新已完成", channel: defaultChannel)
    }

    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult {
        result(id: 990_103, title: "收藏刷新已完成", channel: defaultChannel)
    }

    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult {
        result(id: 990_104, title: query, channel: defaultChannel)
    }

    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult {
        ThreadDetailFetchResult(thread: markerThread(id: tid, title: "刷新主题详情"), rawText: "{}")
    }

    func addFavoriteThread(tid: Int) async throws {}
    func removeFavoriteThread(tid: Int) async throws {}
    func replyThread(tid: Int, target: ThreadReplyTarget, content: String, attachments: [ReplyAttachmentUpload]) async throws {}

    private func result(
        id: Int,
        title: String,
        channel: ForumChannel,
        threadChannel: ForumChannel? = nil
    ) -> ThreadFetchResult {
        let thread = markerThread(id: id, title: title).withChannel(threadChannel ?? channel)
        return ThreadFetchResult(
            payload: ForumPayload(
                forum: ForumSummary(
                    id: channel.id,
                    title: channel.title,
                    subtitle: "固定 UI Test 刷新结果",
                    todayPosts: 0,
                    onlineUsers: 1,
                    source: source
                ),
                channels: source == .nga ? ForumPayload.mock.channels : [channel],
                pinned: [],
                threads: [thread]
            ),
            rawText: "{}",
            hasMore: false
        )
    }

    private func markerThread(id: Int, title: String) -> ForumThread {
        ForumThread(
            id: id,
            title: title,
            summary: "固定 UI Test 数据",
            author: "测试用户",
            createdAt: "2026-07-17 10:00",
            lastReplyAt: "2026-07-17 10:01",
            replyCount: 1,
            viewCount: 1,
            body: "固定 UI Test 正文",
            replies: [],
            source: source
        )
    }
}
