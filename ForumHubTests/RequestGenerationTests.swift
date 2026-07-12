import Foundation
import Testing
@testable import ForumHub

@MainActor
struct RequestGenerationTests {
    @Test func searchIgnoresCancelledOlderQuery() async throws {
        let repository = DelayedThreadRepository()
        let viewModel = SearchThreadsViewModel(initialQuery: "slow", repository: repository)

        viewModel.submit()
        await Task.yield()
        viewModel.query = "fast"
        viewModel.submit()

        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(viewModel.searchedQuery == "fast")
        #expect(viewModel.threads.map(\.title) == ["fast"])
        #expect(!viewModel.isLoading)
    }

    @Test func feedIgnoresCancelledOlderForumLoad() async {
        let repository = DelayedThreadRepository()
        let viewModel = ForumViewModel(repository: repository)
        let slowLoad = Task { @MainActor in
            await viewModel.reload()
        }
        await Task.yield()

        await viewModel.switchForum(to: ForumChannel(id: 2, title: "快速版块"))
        await slowLoad.value

        #expect(viewModel.forum.title == "快速版块")
        #expect(viewModel.threads.map(\.title) == ["快速版块"])
        #expect(!viewModel.isLoading)
    }

    @Test func detailIgnoresCancelledOlderRefresh() async {
        let repository = DelayedThreadRepository()
        let initialThread = DelayedThreadRepository.thread(id: 1, title: "初始")
        let replacementThread = DelayedThreadRepository.thread(id: 2, title: "新请求")
        let viewModel = ThreadDetailViewModel(thread: initialThread)
        let slowRefresh = Task { @MainActor in
            await viewModel.refresh(thread: initialThread, repository: repository)
        }
        await Task.yield()

        _ = await viewModel.refresh(thread: replacementThread, repository: repository)
        _ = await slowRefresh.value

        #expect(viewModel.content.thread.id == 2)
        #expect(viewModel.content.thread.title == "主题 2")
        #expect(!viewModel.content.isLoading)
    }

    @Test func detailNeverUsesFeedSummaryAsMainPostBeforeLoadCompletes() async {
        let repository = DelayedThreadRepository()
        let feedThread = ForumThread(
            id: 1,
            title: "主题标题",
            summary: "列表摘要，不能作为主楼正文",
            author: "测试用户",
            createdAt: "",
            lastReplyAt: "",
            replyCount: 3,
            viewCount: 0,
            body: "列表摘要，不能作为主楼正文",
            replies: []
        )
        let viewModel = ThreadDetailViewModel(thread: feedThread)

        #expect(viewModel.content.thread.body.isEmpty)
        #expect(viewModel.content.thread.contentDocument.normalizedText.isEmpty)
        #expect(viewModel.content.thread.replies.isEmpty)
        #expect(viewModel.content.replyTotalCount == 3)
        #expect(viewModel.content.isLoading)

        let refresh = Task { @MainActor in
            await viewModel.refresh(thread: feedThread, repository: repository)
        }
        await refresh.value

        #expect(viewModel.content.thread.body == "正文")
        #expect(!viewModel.content.isLoading)
    }

    @Test func threadContentChangeIsNotEqualToFeedSummaryWithSameIdentity() {
        let feedThread = ForumThread(
            id: 1,
            title: "主题标题",
            summary: "列表摘要",
            author: "测试用户",
            createdAt: "",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "列表摘要",
            replies: []
        )
        let detailThread = ForumThread(
            id: 1,
            title: "主题标题",
            summary: "列表摘要",
            author: "测试用户",
            createdAt: "",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "完整正文",
            replies: []
        )

        #expect(feedThread != detailThread)
    }
}

private struct DelayedThreadRepository: ThreadRepository {
    let source = ForumSource.nga
    let capabilities = ForumCapabilities(
        supportsSearch: true,
        supportsFavorites: false,
        supportsReply: false,
        supportsReplyTargeting: false,
        supportsAuthentication: false,
        supportsFeedPagination: true
    )
    let defaultChannel = ForumChannel(id: 1, title: "慢速版块")

    func fetchChannels() async throws -> [ForumChannel] { [defaultChannel] }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        if channel.id == defaultChannel.id {
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        return ThreadFetchResult(
            payload: ForumPayload(
                forum: ForumSummary(id: channel.id, title: channel.title, subtitle: "", todayPosts: 0, onlineUsers: 0),
                channels: [channel],
                pinned: [],
                threads: [Self.thread(id: channel.id, title: channel.title)]
            ),
            rawText: "",
            hasMore: false
        )
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult {
        try await fetchForum(channel: defaultChannel, page: page)
    }

    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult {
        try await fetchForum(channel: defaultChannel, page: page)
    }

    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult {
        if query == "slow" {
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        let thread = Self.thread(id: query == "fast" ? 2 : 1, title: query)
        return ThreadFetchResult(
            payload: ForumPayload(
                forum: ForumSummary(id: -1, title: query, subtitle: "", todayPosts: 0, onlineUsers: 1),
                channels: [],
                pinned: [],
                threads: [thread]
            ),
            rawText: "",
            hasMore: false
        )
    }

    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult {
        if tid == 1 {
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        return ThreadDetailFetchResult(thread: Self.thread(id: tid, title: "主题 \(tid)"), rawText: "")
    }

    func addFavoriteThread(tid: Int) async throws {}
    func removeFavoriteThread(tid: Int) async throws {}
    func replyThread(tid: Int, target: ThreadReplyTarget, content: String, attachments: [ReplyAttachmentUpload]) async throws {}

    static func thread(id: Int, title: String) -> ForumThread {
        ForumThread(
            id: id,
            title: title,
            summary: "",
            author: "测试用户",
            createdAt: "",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "正文",
            replies: []
        )
    }
}
