import Foundation
import Observation

@MainActor
@Observable
final class ForumViewModel {
    var forum = ForumSummary.defaultForum
    var pinnedThreads: [ForumThread] = []
    var threads: [ForumThread] = []
    var isLoading = false
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
        return viewModel
    }

    func restoreSession() async {
        loginState = await NGAAuthStore.shared.currentLoginState()
        isAuthenticated = loginState.isLoggedIn

        await loadChannels()
    }

    func reload() async {
        switch feedTab {
        case .home, .community, .history, .user:
            await reloadForum()
        case .hot:
            await reloadHot()
        }
    }

    private func reloadForum() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            currentPage = 1
            if usesAggregatedChildForums {
                let aggregated = try await fetchAggregatedForum(page: currentPage)
                canLoadMore = aggregated.hasMore
                pinnedThreads = aggregated.pinned
                threads = aggregated.threads
                forum = aggregated.forum
            } else {
                let result = try await repository.fetchForum(channel: selectedForum, page: currentPage)
                canLoadMore = result.hasMore
                if let payload = result.payload {
                    let channelTitle = channels.first(where: { $0.id == payload.forum.id })?.title
                        ?? (selectedForum.id == payload.forum.id ? selectedForum.title : payload.forum.title)
                    forum = ForumSummary(
                        id: payload.forum.id,
                        title: channelTitle,
                        subtitle: payload.forum.subtitle,
                        todayPosts: payload.forum.todayPosts,
                        onlineUsers: payload.forum.onlineUsers,
                        source: source
                    )
                    if channels.count <= 1 {
                        channels = payload.channels
                    }
                    pinnedThreads = payload.pinned.map { $0.withChannel(selectedForum) }
                    threads = payload.threads.map { $0.withChannel(selectedForum) }
                } else {
                    pinnedThreads = []
                    threads = []
                    errorMessage = "请求成功，但还没完全匹配到响应结构。"
                }
            }
        } catch {
            guard !error.isCancellationLike else {
                errorMessage = nil
                return
            }
            canLoadMore = false
            pinnedThreads = []
            threads = []
            errorMessage = error.localizedDescription
        }
    }

    private func reloadHot() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            currentPage = 1
            let result = try await repository.fetchHotThreads(page: currentPage)
            canLoadMore = result.hasMore
            if let payload = result.payload {
                forum = payload.forum
                pinnedThreads = payload.pinned
                threads = payload.threads
            } else {
                pinnedThreads = []
                threads = []
                errorMessage = "热门接口请求成功，但还没匹配到主题结构。"
            }
        } catch {
            guard !error.isCancellationLike else {
                errorMessage = nil
                return
            }
            canLoadMore = false
            pinnedThreads = []
            threads = []
            errorMessage = error.localizedDescription
        }
    }

    func loadNextPage() async {
        guard !isLoadingMore else { return }

        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            switch feedTab {
            case .hot:
                let result = try await repository.fetchHotThreads(page: nextPage)
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
                    guard !aggregated.threads.isEmpty else {
                        canLoadMore = false
                        return
                    }
                    currentPage = nextPage
                    canLoadMore = aggregated.hasMore
                    appendUniqueThreads(aggregated.threads)
                } else {
                    let result = try await repository.fetchForum(channel: selectedForum, page: nextPage)
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
            guard !error.isCancellationLike else {
                errorMessage = nil
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func switchForum(to channel: ForumChannel) async {
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
        feedTab = .home
        selectedForum = channel
        selectedChildChannelIDs = []

        await reload()
    }

    func switchFeed(to tab: FeedTab) async {
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
        await NGAAuthStore.shared.logout()
        loginState = .empty
        isAuthenticated = false
        pinnedThreads = []
        threads = []
        canLoadMore = false
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

    private func fetchAggregatedForum(page: Int) async throws -> AggregatedForumResult {
        let selectedChildren = availableChildChannels.filter { selectedChildChannelIDs.contains($0.id) }
        let forumsToLoad = [selectedForum] + selectedChildren

        var results: [(channel: ForumChannel, result: ThreadFetchResult)] = []
        for channel in forumsToLoad {
            let result = try await repository.fetchForum(channel: channel, page: page)
            results.append((channel, result))
        }

        let payloads = results.compactMap { entry -> (ForumChannel, ForumPayload)? in
            guard let payload = entry.result.payload else { return nil }
            return (entry.channel, payload)
        }
        guard !payloads.isEmpty else {
            throw NSError(domain: "ForumViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有加载到子版内容。"])
        }

        if channels.count <= 1, let firstPayload = payloads.first {
            channels = firstPayload.1.channels
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
        let subtitle = selectedChildren.isEmpty
            ? "正在浏览 \(selectedForum.title)"
            : "已包含 " + selectedChildren.map(\.title).joined(separator: "、")

        return AggregatedForumResult(
            forum: ForumSummary(
                id: selectedForum.id,
                title: selectedForum.title,
                subtitle: subtitle,
                todayPosts: payloads.first?.1.forum.todayPosts ?? 0,
                onlineUsers: payloads.reduce(0) { $0 + $1.1.forum.onlineUsers },
                source: source
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
