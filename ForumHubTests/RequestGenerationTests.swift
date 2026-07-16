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
        #expect(viewModel.content.thread.contentDocument.bodyText.isEmpty)
        #expect(viewModel.content.thread.replies.isEmpty)
        #expect(viewModel.content.replyTotalCount == 3)
        #expect(viewModel.content.isLoading)

        let refresh = Task { @MainActor in
            await viewModel.refresh(thread: feedThread, repository: repository)
        }
        _ = await refresh.value

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

    @Test func detailMetadataFallbackNeverPromotesFeedSummaryToMainPost() async {
        let feedThread = ForumThread(
            id: 1,
            title: "主题标题",
            summary: "列表摘要，不能作为主楼正文",
            author: "测试用户",
            createdAt: "",
            lastReplyAt: "",
            replyCount: 3,
            viewCount: 8,
            body: "列表摘要，不能作为主楼正文",
            replies: []
        )
        let emptyDetail = ForumThread(
            id: 1,
            title: "",
            summary: "",
            author: "",
            createdAt: "",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "",
            contentDocument: .plainText(""),
            replies: []
        )
        let viewModel = ThreadDetailViewModel(thread: feedThread)

        _ = await viewModel.refresh(
            thread: feedThread,
            repository: ImmediateThreadRepository(thread: emptyDetail)
        )

        #expect(viewModel.content.thread.title == feedThread.title)
        #expect(viewModel.content.thread.author == feedThread.author)
        #expect(viewModel.content.thread.replyCount == feedThread.replyCount)
        #expect(viewModel.content.thread.body.isEmpty)
        #expect(viewModel.content.thread.contentDocument.bodyText.isEmpty)
    }

    @Test func latePageJumpFailureCannotOverwriteNewerPageJump() async throws {
        let repository = ControlledThreadDetailRepository()
        let feedThread = ControlledThreadDetailRepository.thread(page: 1, title: "列表主题")
        let viewModel = ThreadDetailViewModel(thread: feedThread)

        let refresh = Task { @MainActor in
            await viewModel.refresh(thread: feedThread, repository: repository)
        }
        let initialRequest = try await repository.waitForPendingRequest(page: 1, ordinal: 0)
        repository.succeed(initialRequest, with: ControlledThreadDetailRepository.thread(page: 1, title: "初始详情"))
        #expect(await refresh.value)

        let olderJump = Task { @MainActor in
            await viewModel.loadThroughPage(3, thread: feedThread, repository: repository)
        }
        let olderPageTwoRequest = try await repository.waitForPendingRequest(page: 2, ordinal: 0)

        let newerJump = Task { @MainActor in
            await viewModel.loadThroughPage(2, thread: feedThread, repository: repository)
        }
        let newerPageTwoRequest = try await repository.waitForPendingRequest(page: 2, ordinal: 1)
        repository.succeed(newerPageTwoRequest, with: ControlledThreadDetailRepository.thread(page: 2, title: "新跳页"))
        #expect(await newerJump.value)

        repository.fail(olderPageTwoRequest, with: ControlledThreadDetailRepository.TestFailure.staleFallback)
        #expect(!(await olderJump.value))

        #expect(viewModel.pagination.currentPage == 2)
        #expect(viewModel.content.thread.replies.contains { $0.body == "第 21 楼-新跳页" })
        #expect(viewModel.content.error == nil)
    }

    @Test func lateWebFallbackCannotOverwriteNewerRefresh() async throws {
        let repository = ControlledThreadDetailRepository()
        let feedThread = ControlledThreadDetailRepository.thread(page: 1, title: "列表主题")
        let viewModel = ThreadDetailViewModel(thread: feedThread)

        let olderRefresh = Task { @MainActor in
            await viewModel.refresh(thread: feedThread, repository: repository)
        }
        let olderFallbackRequest = try await repository.waitForPendingRequest(page: 1, ordinal: 0)

        let newerRefresh = Task { @MainActor in
            await viewModel.refresh(thread: feedThread, repository: repository)
        }
        let newerRequest = try await repository.waitForPendingRequest(page: 1, ordinal: 1)
        repository.succeed(newerRequest, with: ControlledThreadDetailRepository.thread(page: 1, title: "新刷新"))
        #expect(await newerRefresh.value)

        repository.succeed(olderFallbackRequest, with: ControlledThreadDetailRepository.thread(page: 1, title: "旧 Web fallback"))
        #expect(!(await olderRefresh.value))

        #expect(viewModel.content.thread.title == "新刷新")
        #expect(viewModel.content.thread.body == "主楼-新刷新")
        #expect(viewModel.content.error == nil)
        #expect(!viewModel.content.isLoading)
    }

    @Test func lateContinuationFallbackCannotOverwriteNewerRefresh() async throws {
        let repository = ControlledThreadDetailRepository()
        let feedThread = ControlledThreadDetailRepository.thread(page: 1, title: "列表主题")
        let viewModel = ThreadDetailViewModel(thread: feedThread)

        let initialRefresh = Task { @MainActor in
            await viewModel.refresh(thread: feedThread, repository: repository)
        }
        let initialRequest = try await repository.waitForPendingRequest(page: 1, ordinal: 0)
        repository.succeed(initialRequest, with: ControlledThreadDetailRepository.thread(page: 1, title: "初始详情"))
        #expect(await initialRefresh.value)

        let continuationLoad = Task { @MainActor in
            await viewModel.loadNextPage(
                thread: feedThread,
                repository: repository,
                showsOnlyAuthor: false
            )
        }
        let staleContinuationRequest = try await repository.waitForPendingRequest(page: 2, ordinal: 0)

        let newerRefresh = Task { @MainActor in
            await viewModel.refresh(thread: feedThread, repository: repository)
        }
        let newerRefreshRequest = try await repository.waitForPendingRequest(page: 1, ordinal: 1)
        repository.succeed(newerRefreshRequest, with: ControlledThreadDetailRepository.thread(page: 1, title: "刷新后详情"))
        #expect(await newerRefresh.value)

        repository.succeed(
            staleContinuationRequest,
            with: ControlledThreadDetailRepository.thread(page: 2, title: "迟到 continuation")
        )
        await continuationLoad.value

        #expect(viewModel.content.thread.title == "刷新后详情")
        #expect(!viewModel.content.thread.replies.contains { $0.body.contains("迟到 continuation") })
        #expect(viewModel.pagination.currentPage == 1)
        #expect(viewModel.content.error == nil)
        #expect(viewModel.content.isLoadingMore == false)
    }
}

@MainActor
private final class ControlledThreadDetailRepository: ThreadRepository {
    enum TestFailure: Error {
        case staleFallback
        case requestNotObserved
    }

    private struct PendingRequest {
        let id: Int
        let page: Int
        let continuation: CheckedContinuation<ThreadDetailFetchResult, Error>
    }

    let source = ForumSource.nga
    let capabilities = ForumCapabilities(
        supportsSearch: false,
        supportsFavorites: false,
        supportsReply: false,
        supportsReplyTargeting: false,
        supportsAuthentication: false,
        supportsFeedPagination: true,
        threadPaginationStyle: .numbered(pageSize: 20),
        supportsWebFallback: true
    )
    let defaultChannel = ForumChannel(id: 1, title: "测试版块")
    private var nextRequestID = 0
    private var pendingRequests: [PendingRequest] = []
    private var observedRequestIDsByPage: [Int: [Int]] = [:]

    func fetchChannels() async throws -> [ForumChannel] { [defaultChannel] }
    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult { fatalError() }
    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult { fatalError() }
    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult { fatalError() }
    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult { fatalError() }

    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult {
        let requestID = nextRequestID
        nextRequestID += 1
        observedRequestIDsByPage[page, default: []].append(requestID)
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests.append(PendingRequest(id: requestID, page: page, continuation: continuation))
        }
    }

    func addFavoriteThread(tid: Int) async throws {}
    func removeFavoriteThread(tid: Int) async throws {}
    func replyThread(tid: Int, target: ThreadReplyTarget, content: String, attachments: [ReplyAttachmentUpload]) async throws {}

    func waitForPendingRequest(page: Int, ordinal: Int) async throws -> Int {
        for _ in 0..<100 {
            if let requestID = observedRequestIDsByPage[page]?[safe: ordinal],
               pendingRequests.contains(where: { $0.id == requestID }) {
                return requestID
            }
            await Task.yield()
        }
        throw TestFailure.requestNotObserved
    }

    func succeed(_ requestID: Int, with thread: ForumThread) {
        guard let index = pendingRequests.firstIndex(where: { $0.id == requestID }) else { return }
        let request = pendingRequests.remove(at: index)
        request.continuation.resume(returning: ThreadDetailFetchResult(thread: thread, rawText: "request-\(requestID)"))
    }

    func fail(_ requestID: Int, with error: Error) {
        guard let index = pendingRequests.firstIndex(where: { $0.id == requestID }) else { return }
        pendingRequests.remove(at: index).continuation.resume(throwing: error)
    }

    static func thread(page: Int, title: String) -> ForumThread {
        let firstFloor = ((page - 1) * 20) + 1
        let replies = (firstFloor..<(firstFloor + 20)).map { floor in
            Reply(
                id: floor,
                sourcePostID: floor,
                author: "用户 \(floor)",
                createdAt: "",
                body: "第 \(floor) 楼-\(title)",
                floorNumber: floor
            )
        }
        return ForumThread(
            id: 47,
            title: title,
            summary: "",
            author: "楼主",
            createdAt: "",
            lastReplyAt: "",
            replyCount: 60,
            viewCount: 0,
            body: page == 1 ? "主楼-\(title)" : "",
            replies: replies
        )
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct ImmediateThreadRepository: ThreadRepository {
    let thread: ForumThread
    let source = ForumSource.nga
    let capabilities = ForumCapabilities(
        supportsSearch: true,
        supportsFavorites: false,
        supportsReply: false,
        supportsReplyTargeting: false,
        supportsAuthentication: false,
        supportsFeedPagination: true
    )
    let defaultChannel = ForumChannel(id: 1, title: "测试版块")

    func fetchChannels() async throws -> [ForumChannel] { [defaultChannel] }
    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult { fatalError() }
    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult { fatalError() }
    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult { fatalError() }
    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult { fatalError() }
    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult {
        ThreadDetailFetchResult(thread: thread, rawText: "")
    }
    func addFavoriteThread(tid: Int) async throws {}
    func removeFavoriteThread(tid: Int) async throws {}
    func replyThread(tid: Int, target: ThreadReplyTarget, content: String, attachments: [ReplyAttachmentUpload]) async throws {}
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
