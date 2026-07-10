import Foundation
import Observation

@MainActor
@Observable
final class ForumViewModel {
    var forum = ForumSummary.defaultForum
    var pinnedThreads: [ForumThread] = [] { didSet { rebuildDisplayedThreads() } }
    var threads: [ForumThread] = [] { didSet { rebuildDisplayedThreads() } }
    private(set) var displayedPinnedThreads: [ForumThread] = []
    private(set) var displayedThreads: [ForumThread] = []
    var feedSortMode: FeedSortMode = .lastReply { didSet { rebuildDisplayedThreads() } }
    var isLoading = false
    var hasLoadedInitialFeed = false
    var isAuthenticated = false
    var errorMessage: String?
    var loginState = NGALoginState.empty
    var isLoadingMore = false
    var canLoadMore = false
    var channels: [ForumChannel] = ForumChannel.defaultChannels
    var selectedChildChannelIDs: Set<Int> = []

    private let repositories: [ForumSource: any ThreadRepository]
    private(set) var source: ForumSource
    private var currentPage = 1
    private var feedTab: FeedTab = .home
    private var selectedForum: ForumChannel = .defaultForum
    private var feedLoadGeneration = 0
    private var feedLoadTask: Task<Void, Never>?
    private static let sourceStorageKey = "active-forum-source-v1"

    var repository: any ThreadRepository {
        repositories[source]!
    }

    var capabilities: ForumCapabilities {
        repository.capabilities
    }

    var availableSources: [ForumSource] {
        ForumSource.allCases.filter { repositories[$0] != nil }
    }

    private func rebuildDisplayedThreads() {
        displayedPinnedThreads = sorted(pinnedThreads)
        displayedThreads = sorted(threads)
    }

    private func sorted(_ threads: [ForumThread]) -> [ForumThread] {
        threads.sorted { lhs, rhs in
            let leftDate: Date?
            let rightDate: Date?
            switch feedSortMode {
            case .lastReply:
                leftDate = lhs.lastReplySortDate ?? lhs.createdAtSortDate
                rightDate = rhs.lastReplySortDate ?? rhs.createdAtSortDate
            case .latestPost:
                leftDate = lhs.createdAtSortDate ?? lhs.lastReplySortDate
                rightDate = rhs.createdAtSortDate ?? rhs.lastReplySortDate
            }
            if let leftDate, let rightDate, leftDate != rightDate { return leftDate > rightDate }
            if lhs.replyCount != rhs.replyCount { return lhs.replyCount > rhs.replyCount }
            return lhs.id > rhs.id
        }
    }

    func repository(for source: ForumSource) -> any ThreadRepository {
        repositories[source] ?? repository
    }

    init() {
        let ngaRepository = NGALiveThreadRepository()
        let v2exRepository = V2EXThreadRepository()
        let discourseRepository = DiscourseThreadRepository()
        let availableRepositories: [ForumSource: any ThreadRepository] = [
            .nga: ngaRepository,
            .v2ex: v2exRepository,
            .linuxDo: discourseRepository
        ]
        repositories = availableRepositories
        let initialSource = UserDefaults.standard.string(forKey: Self.sourceStorageKey)
            .flatMap(ForumSource.init(rawValue:))
            .flatMap { availableRepositories[$0] == nil ? nil : $0 }
            ?? .nga
        source = initialSource
        selectedForum = availableRepositories[initialSource]?.defaultChannel ?? .defaultForum
        channels = [selectedForum]
    }

    init(repository: any ThreadRepository) {
        repositories = [repository.source: repository]
        source = repository.source
        selectedForum = repository.defaultChannel
        channels = [repository.defaultChannel]
        forum = ForumSummary(
            id: repository.defaultChannel.id,
            title: repository.defaultChannel.title,
            subtitle: "Preview 数据",
            todayPosts: 0,
            onlineUsers: 0,
            source: repository.source
        )
    }

    static func preview() -> ForumViewModel {
        let viewModel = ForumViewModel(repository: MockThreadRepository())
        viewModel.isAuthenticated = true
        viewModel.loginState = NGALoginState(
            uid: "preview-user",
            cid: "preview-cookie",
            cookieNames: ["ngaPassportUid", "ngaPassportCid"]
        )
        viewModel.forum = ForumPayload.mock.forum
        viewModel.channels = ForumPayload.mock.channels
        viewModel.pinnedThreads = ForumPayload.mock.pinned
        viewModel.threads = ForumPayload.mock.threads
        viewModel.hasLoadedInitialFeed = true
        return viewModel
    }

    static func pagedPreview() -> ForumViewModel {
        let repository = MockPagedThreadRepository()
        let viewModel = ForumViewModel(repository: repository)
        viewModel.isAuthenticated = false
        viewModel.loginState = .empty
        viewModel.forum = ForumPayload.mock.forum
        viewModel.channels = ForumPayload.mock.channels
        viewModel.pinnedThreads = ForumPayload.mock.pinned
        viewModel.threads = [
            repository.previewThread.withChannel(repository.defaultChannel),
            ForumPayload.mock.threads[1].withChannel(repository.defaultChannel)
        ]
        viewModel.canLoadMore = false
        viewModel.hasLoadedInitialFeed = true
        return viewModel
    }

    func restoreSession() async {
        loginState = await NGAAuthStore.shared.currentLoginState()
        isAuthenticated = loginState.isLoggedIn

        await loadChannels()
    }

    func reload() async {
        currentPage = 1
        let request = makeFeedRequest(page: currentPage)
        await replaceFeedLoad(with: request)
    }

    func suspendFeedLoading() {
        feedLoadGeneration += 1
        feedLoadTask?.cancel()
        feedLoadTask = nil
        isLoading = false
        isLoadingMore = false
    }

    private func replaceFeedLoad(with request: FeedRequest) async {
        feedLoadGeneration += 1
        let generation = feedLoadGeneration
        feedLoadTask?.cancel()
        isLoading = true
        errorMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performFeedLoad(request, generation: generation)
        }
        feedLoadTask = task
        await task.value
    }

    private func performFeedLoad(_ request: FeedRequest, generation: Int) async {
        defer {
            if isCurrentFeedLoad(generation) {
                isLoading = false
                feedLoadTask = nil
            }
        }

        do {
            let result = try await fetchFirstPage(for: request)
            guard isCurrentFeedLoad(generation) else { return }
            apply(result, for: request)
        } catch {
            guard isCurrentFeedLoad(generation), !error.isCancellationLike else { return }
            canLoadMore = false
            pinnedThreads = []
            threads = []
            errorMessage = error.localizedDescription
            hasLoadedInitialFeed = true
        }
    }

    private func fetchFirstPage(for request: FeedRequest) async throws -> FeedFirstPageResult {
        switch request.tab {
        case .hot:
            return .hot(try await request.repository.fetchHotThreads(page: request.page))
        case .home, .community, .history, .user:
            if request.usesAggregatedChildForums {
                return .aggregated(try await fetchAggregatedForum(for: request))
            }
            return .forum(try await request.repository.fetchForum(channel: request.selectedForum, page: request.page))
        }
    }

    private func apply(_ result: FeedFirstPageResult, for request: FeedRequest) {
        switch result {
        case let .aggregated(aggregated):
            canLoadMore = aggregated.hasMore
            pinnedThreads = aggregated.pinned
            threads = aggregated.threads
            forum = aggregated.forum
        case let .forum(result):
            canLoadMore = result.hasMore
            guard let payload = result.payload else {
                pinnedThreads = []
                threads = []
                errorMessage = "请求成功，但还没完全匹配到响应结构。"
                hasLoadedInitialFeed = true
                return
            }
            let channelTitle = request.channels.first(where: { $0.id == payload.forum.id })?.title
                ?? (request.selectedForum.id == payload.forum.id ? request.selectedForum.title : payload.forum.title)
            forum = ForumSummary(
                id: payload.forum.id,
                title: channelTitle,
                subtitle: payload.forum.subtitle,
                todayPosts: payload.forum.todayPosts,
                onlineUsers: payload.forum.onlineUsers,
                source: request.source
            )
            if request.channels.count <= 1 {
                channels = payload.channels
            }
            pinnedThreads = payload.pinned.map { $0.withChannel(request.selectedForum) }
            threads = payload.threads.map { $0.withChannel(request.selectedForum) }
        case let .hot(result):
            canLoadMore = result.hasMore
            guard let payload = result.payload else {
                pinnedThreads = []
                threads = []
                errorMessage = "热门接口请求成功，但还没匹配到主题结构。"
                hasLoadedInitialFeed = true
                return
            }
            forum = payload.forum
            pinnedThreads = payload.pinned
            threads = payload.threads
        }
        hasLoadedInitialFeed = true
    }

    func loadNextPage() async {
        guard !isLoadingMore else { return }

        let generation = feedLoadGeneration
        isLoadingMore = true
        errorMessage = nil
        defer {
            if isCurrentFeedLoad(generation) {
                isLoadingMore = false
            }
        }

        do {
            let nextPage = currentPage + 1
            switch feedTab {
            case .hot:
                let result = try await repository.fetchHotThreads(page: nextPage)
                guard isCurrentFeedLoad(generation) else { return }
                guard let payload = result.payload, !payload.threads.isEmpty else {
                    canLoadMore = false
                    return
                }
                currentPage = nextPage
                canLoadMore = result.hasMore
                if channels.count <= 1 {
                    channels = payload.channels
                }
                threads.append(contentsOf: payload.threads.filter { newThread in
                    !threads.contains(where: { $0.id == newThread.id })
                })
            case .home, .community, .history, .user:
                if usesAggregatedChildForums {
                    let aggregated = try await fetchAggregatedForum(page: nextPage)
                    guard isCurrentFeedLoad(generation) else { return }
                    guard !aggregated.threads.isEmpty else {
                        canLoadMore = false
                        return
                    }
                    currentPage = nextPage
                    canLoadMore = aggregated.hasMore
                    appendUniqueThreads(aggregated.threads)
                } else {
                    let result = try await repository.fetchForum(channel: selectedForum, page: nextPage)
                    guard isCurrentFeedLoad(generation) else { return }
                    guard let payload = result.payload, !payload.threads.isEmpty else {
                        canLoadMore = false
                        return
                    }

                    currentPage = nextPage
                    canLoadMore = result.hasMore
                    if channels.count <= 1 {
                        channels = payload.channels
                    }
                    appendUniqueThreads(payload.threads.map { $0.withChannel(selectedForum) })
                }
            }
        } catch {
            guard isCurrentFeedLoad(generation), !error.isCancellationLike else { return }
            errorMessage = error.localizedDescription
        }
    }

    func switchForum(to channel: ForumChannel) async {
        suspendFeedLoading()
        forum = ForumSummary(
            id: channel.id,
            title: channel.title,
            subtitle: "正在切换到 \(channel.title)",
            todayPosts: 0,
            onlineUsers: 0,
            source: channel.source
        )
        pinnedThreads = []
        threads = []
        canLoadMore = false
        currentPage = 1
        hasLoadedInitialFeed = false
        feedTab = .home
        selectedForum = channel
        selectedChildChannelIDs = []

        await reload()
    }

    func switchFeed(to tab: FeedTab) async {
        suspendFeedLoading()
        feedTab = tab
        switch tab {
        case .home:
            forum = ForumSummary(
                id: selectedForum.id,
                title: selectedForum.title,
                subtitle: "正在浏览 \(selectedForum.title)",
                todayPosts: 0,
                onlineUsers: 0,
                source: source
            )
            pinnedThreads = []
            threads = []
            canLoadMore = false
            currentPage = 1
            hasLoadedInitialFeed = false
            await reload()
        case .hot:
            forum = ForumSummary(
                id: -1,
                title: "热门",
                subtitle: "来自 \(source.title) 热门主题。",
                todayPosts: 0,
                onlineUsers: 0,
                source: source
            )
            pinnedThreads = []
            threads = []
            canLoadMore = false
            currentPage = 1
            hasLoadedInitialFeed = false
            await reload()
        case .community, .history, .user:
            break
        }
    }

    func setSelectedChildChannels(_ ids: Set<Int>) async {
        let normalized = ids.intersection(Set(availableChildChannels.map(\.id)))
        guard normalized != selectedChildChannelIDs else { return }
        selectedChildChannelIDs = normalized
        guard feedTab == .home, selectedForum.id == repository.defaultChannel.id else { return }
        await reload()
    }

    var availableChildChannels: [ForumChannel] {
        guard source == .nga else { return [] }
        return channels.filter { $0.id != selectedForum.id }
    }

    func loadChannels() async {
        do {
            let fetchedChannels = try await repository.fetchChannels()
            if !fetchedChannels.isEmpty {
                channels = fetchedChannels
            }
        } catch {
            if channels.isEmpty {
                channels = [repository.defaultChannel]
            }
        }
    }

    func switchSource(to newSource: ForumSource) async {
        guard newSource != source, let newRepository = repositories[newSource] else { return }

        suspendFeedLoading()
        source = newSource
        UserDefaults.standard.set(newSource.rawValue, forKey: Self.sourceStorageKey)
        feedTab = .home
        currentPage = 1
        selectedForum = newRepository.defaultChannel
        selectedChildChannelIDs = []
        channels = [newRepository.defaultChannel]
        forum = ForumSummary(
            id: newRepository.defaultChannel.id,
            title: newRepository.defaultChannel.title,
            subtitle: "正在载入 \(newSource.title)",
            todayPosts: 0,
            onlineUsers: 0,
            source: newSource
        )
        pinnedThreads = []
        threads = []
        canLoadMore = false
        hasLoadedInitialFeed = false
        errorMessage = nil

        await loadChannels()
        if let defaultChannel = channels.first(where: { $0.nativeKey == newRepository.defaultChannel.nativeKey })
            ?? channels.first {
            selectedForum = defaultChannel
            forum = ForumSummary(
                id: defaultChannel.id,
                title: defaultChannel.title,
                subtitle: "正在浏览 \(defaultChannel.title)",
                todayPosts: 0,
                onlineUsers: 0,
                source: newSource
            )
        }
        await reload()
    }

    func logout() async {
        suspendFeedLoading()
        await NGAAuthStore.shared.logout()
        loginState = .empty
        isAuthenticated = false
        pinnedThreads = []
        threads = []
        canLoadMore = false
        hasLoadedInitialFeed = false
        errorMessage = nil
        let currentDefault = repository.defaultChannel
        channels = [currentDefault]
        currentPage = 1
        feedTab = .home
        selectedForum = currentDefault
        selectedChildChannelIDs = []
        forum = ForumSummary(
            id: currentDefault.id,
            title: currentDefault.title,
            subtitle: "正在浏览 \(currentDefault.title)",
            todayPosts: 0,
            onlineUsers: 0,
            source: source
        )
    }

    private var usesAggregatedChildForums: Bool {
        source == .nga
            && feedTab == .home
            && selectedForum.id == repository.defaultChannel.id
            && !selectedChildChannelIDs.isEmpty
    }

    private func makeFeedRequest(page: Int) -> FeedRequest {
        let selectedChildren = availableChildChannels.filter { selectedChildChannelIDs.contains($0.id) }
        return FeedRequest(
            tab: feedTab,
            source: source,
            repository: repository,
            selectedForum: selectedForum,
            selectedChildChannels: selectedChildren,
            channels: channels,
            page: page,
            usesAggregatedChildForums: usesAggregatedChildForums
        )
    }

    private func isCurrentFeedLoad(_ generation: Int) -> Bool {
        generation == feedLoadGeneration
    }

    private func fetchAggregatedForum(page: Int) async throws -> AggregatedForumResult {
        try await fetchAggregatedForum(for: makeFeedRequest(page: page))
    }

    private func fetchAggregatedForum(for request: FeedRequest) async throws -> AggregatedForumResult {
        let forumsToLoad = [request.selectedForum] + request.selectedChildChannels

        var results: [(channel: ForumChannel, result: ThreadFetchResult)] = []
        for channel in forumsToLoad {
            try Task.checkCancellation()
            let result = try await request.repository.fetchForum(channel: channel, page: request.page)
            results.append((channel, result))
        }

        let payloads = results.compactMap { entry -> (ForumChannel, ForumPayload)? in
            guard let payload = entry.result.payload else { return nil }
            return (entry.channel, payload)
        }
        guard !payloads.isEmpty else {
            throw NSError(domain: "ForumViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有加载到子版内容。"])
        }

        let mergedPinned = deduplicatedThreads(
            payloads.flatMap { channel, payload in
                payload.pinned.map { $0.withChannel(channel) }
            }
        )
        let mergedThreads = deduplicatedThreads(
            payloads.flatMap { channel, payload in
                payload.threads.map { $0.withChannel(channel) }
            }
        )
        let subtitle = request.selectedChildChannels.isEmpty
            ? "正在浏览 \(request.selectedForum.title)"
            : "已包含 " + request.selectedChildChannels.map(\.title).joined(separator: "、")

        return AggregatedForumResult(
            forum: ForumSummary(
                id: request.selectedForum.id,
                title: request.selectedForum.title,
                subtitle: subtitle,
                todayPosts: payloads.first?.1.forum.todayPosts ?? 0,
                onlineUsers: payloads.reduce(0) { $0 + $1.1.forum.onlineUsers },
                source: request.source
            ),
            pinned: mergedPinned,
            threads: mergedThreads,
            hasMore: results.contains { $0.result.hasMore }
        )
    }

    private func deduplicatedThreads(_ items: [ForumThread]) -> [ForumThread] {
        var seen: Set<String> = []
        var deduplicated: [ForumThread] = []
        for thread in items {
            let key = "\(thread.source.rawValue)-\(thread.id)"
            if seen.insert(key).inserted {
                deduplicated.append(thread)
            }
        }
        return deduplicated
    }

    private func appendUniqueThreads(_ newThreads: [ForumThread]) {
        let existingKeys = Set(threads.map { "\($0.source.rawValue)-\($0.id)" })
        threads.append(contentsOf: newThreads.filter { !existingKeys.contains("\($0.source.rawValue)-\($0.id)") })
    }
}

private extension Error {
    var isCancellationLike: Bool {
        if self is CancellationError {
            return true
        }

        if let urlError = self as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        return localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "cancelled"
    }
}

private struct AggregatedForumResult {
    let forum: ForumSummary
    let pinned: [ForumThread]
    let threads: [ForumThread]
    let hasMore: Bool
}

private struct FeedRequest {
    let tab: FeedTab
    let source: ForumSource
    let repository: any ThreadRepository
    let selectedForum: ForumChannel
    let selectedChildChannels: [ForumChannel]
    let channels: [ForumChannel]
    let page: Int
    let usesAggregatedChildForums: Bool
}

private enum FeedFirstPageResult {
    case forum(ThreadFetchResult)
    case hot(ThreadFetchResult)
    case aggregated(AggregatedForumResult)
}
