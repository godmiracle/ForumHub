import Observation
import SwiftUI

@MainActor
@Observable
final class SearchThreadsViewModel {
    var query: String
    private(set) var searchedQuery: String
    private(set) var threads: [ForumThread] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = false
    private(set) var error: ForumError?

    private let repository: any ThreadRepository
    private var currentPage = 1
    private var generation = 0
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    init(initialQuery: String, repository: any ThreadRepository) {
        self.query = initialQuery
        self.searchedQuery = initialQuery
        self.repository = repository
    }

    func submit(force: Bool = false) {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty,
              force || keyword != searchedQuery || threads.isEmpty || error != nil
        else {
            return
        }

        generation += 1
        let requestGeneration = generation
        searchTask?.cancel()
        loadMoreTask?.cancel()
        isLoading = true
        isLoadingMore = false
        error = nil

        searchTask = Task { [weak self, repository] in
            do {
                let result = try await repository.searchThreads(query: keyword, page: 1)
                try Task.checkCancellation()
                guard let self, self.generation == requestGeneration else { return }
                self.threads = result.payload?.threads ?? []
                self.canLoadMore = result.hasMore && !self.threads.isEmpty
                self.searchedQuery = keyword
                self.currentPage = 1
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.generation == requestGeneration else { return }
                self.error = ForumError.resolve(error)
            }
            guard let self, self.generation == requestGeneration else { return }
            self.isLoading = false
            self.searchTask = nil
        }
    }

    func loadNextPage() {
        guard canLoadMore, !isLoading, !isLoadingMore, !searchedQuery.isEmpty else { return }

        let requestGeneration = generation
        let nextPage = currentPage + 1
        let keyword = searchedQuery
        isLoadingMore = true
        error = nil

        loadMoreTask = Task { [weak self, repository] in
            do {
                let result = try await repository.searchThreads(query: keyword, page: nextPage)
                try Task.checkCancellation()
                guard let self, self.generation == requestGeneration, self.searchedQuery == keyword else { return }
                let newThreads = result.payload?.threads ?? []
                self.threads.append(contentsOf: newThreads.filter { candidate in
                    !self.threads.contains(where: { $0.id == candidate.id && $0.source == candidate.source })
                })
                self.canLoadMore = result.hasMore && !newThreads.isEmpty
                self.currentPage = nextPage
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.generation == requestGeneration else { return }
                self.error = ForumError.resolve(error)
            }
            guard let self, self.generation == requestGeneration else { return }
            self.isLoadingMore = false
            self.loadMoreTask = nil
        }
    }

    func cancel() {
        generation += 1
        searchTask?.cancel()
        loadMoreTask?.cancel()
        searchTask = nil
        loadMoreTask = nil
        isLoading = false
        isLoadingMore = false
    }
}

struct SearchThreadsView: View {
    let repository: any ThreadRepository
    @Bindable var blockedUsers: BlockedUsersStore
    @Bindable var favoriteThreads: FavoriteThreadsStore
    @State private var viewModel: SearchThreadsViewModel
    @Environment(\.dismissSearch) private var dismissSearch

    init(
        initialQuery: String,
        repository: any ThreadRepository,
        blockedUsers: BlockedUsersStore,
        favoriteThreads: FavoriteThreadsStore
    ) {
        self.repository = repository
        self.blockedUsers = blockedUsers
        self.favoriteThreads = favoriteThreads
        _viewModel = State(initialValue: SearchThreadsViewModel(initialQuery: initialQuery, repository: repository))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack {
            PaperBackground()

            ScrollView {
                LazyVStack(spacing: 0) {
                    scopeNotice

                    if let error = viewModel.error {
                        ErrorBanner(message: error.userMessage)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }

                    if viewModel.threads.isEmpty, viewModel.isLoading {
                        ProgressView("正在搜索 \(repository.source.title)")
                            .tint(PaperTheme.accent)
                            .foregroundStyle(PaperTheme.mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 90)
                    } else if viewModel.threads.isEmpty {
                        ContentUnavailableView.search(text: viewModel.searchedQuery)
                            .foregroundStyle(PaperTheme.secondaryInk)
                            .padding(.top, 70)
                    } else {
                        if visibleThreads.isEmpty {
                            BlockedThreadsNotice()
                                .padding(.vertical, 60)
                        }

                        ForEach(Array(visibleThreads.enumerated()), id: \.element.id) { index, thread in
                            BlockableThreadLink(
                                thread: thread,
                                repository: repository,
                                blockedUsers: blockedUsers,
                                favoriteThreads: favoriteThreads
                            )
                            .task(id: viewModel.threads.count) {
                                if FeedPaginationPolicy.shouldPrefetch(
                                    itemIndex: index,
                                    itemCount: visibleThreads.count,
                                    canLoadMore: viewModel.canLoadMore
                                ) {
                                    viewModel.loadNextPage()
                                }
                            }
                        }

                        if viewModel.canLoadMore, viewModel.isLoadingMore {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("正在加载更多")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PaperTheme.mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        }
                    }

                    Color.clear.frame(height: 40)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { viewModel.submit(force: true) }
        }
        .accessibilityIdentifier("search-results-screen")
        .navigationTitle("搜索 \(repository.source.title)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .searchable(text: $viewModel.query, prompt: "搜索全站主题标题")
        .onSubmit(of: .search) {
            dismissSearch()
            viewModel.submit()
        }
        .task { viewModel.submit() }
        .onDisappear { viewModel.cancel() }
    }

    private var visibleThreads: [ForumThread] {
        blockedUsers.filtering(viewModel.threads)
    }

    private var scopeNotice: some View {
        Label(
            scopeNoticeText,
            systemImage: "magnifyingglass"
        )
        .font(.footnote)
        .foregroundStyle(PaperTheme.mutedText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    private var scopeNoticeText: String {
        switch repository.source {
        case .nga:
            return "覆盖普通版面与用户版面；仅搜索标题，需要已登录且威望大于 0。"
        case .v2ex:
            return "V2EX 当前未接入全站主题搜索。"
        case .linuxDo:
            return "搜索当前 LINUX DO 站点的公开主题。"
        }
    }
}
