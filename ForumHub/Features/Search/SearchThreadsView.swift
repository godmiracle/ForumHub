import SwiftUI

struct SearchThreadsView: View {
    let initialQuery: String
    let repository: any ThreadRepository
    @Bindable var blockedUsers: BlockedUsersStore
    @Bindable var favoriteThreads: FavoriteThreadsStore
    @State private var query: String
    @State private var searchedQuery: String
    @State private var threads: [ForumThread] = []
    @State private var currentPage = 1
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @State private var errorMessage: String?

    init(
        initialQuery: String,
        repository: any ThreadRepository,
        blockedUsers: BlockedUsersStore,
        favoriteThreads: FavoriteThreadsStore
    ) {
        self.initialQuery = initialQuery
        self.repository = repository
        self.blockedUsers = blockedUsers
        self.favoriteThreads = favoriteThreads
        _query = State(initialValue: initialQuery)
        _searchedQuery = State(initialValue: initialQuery)
    }

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                LazyVStack(spacing: 0) {
                    scopeNotice

                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }

                    if threads.isEmpty, isLoading {
                        ProgressView("正在搜索 NGA")
                            .tint(PaperTheme.accent)
                            .foregroundStyle(PaperTheme.mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 90)
                    } else if threads.isEmpty {
                        ContentUnavailableView.search(text: searchedQuery)
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
                            .task(id: threads.count) {
                                if FeedPaginationPolicy.shouldPrefetch(
                                    itemIndex: index,
                                    itemCount: visibleThreads.count,
                                    canLoadMore: canLoadMore
                                ), !isLoadingMore {
                                    await loadNextPage()
                                }
                            }
                        }

                        if canLoadMore {
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
            .refreshable {
                await search(reset: true)
            }
        }
        .accessibilityIdentifier("search-results-screen")
        .navigationTitle("搜索 NGA")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .searchable(text: $query, prompt: "搜索全站主题标题")
        .onSubmit(of: .search) {
            Task { await search(reset: true) }
        }
        .task {
            await search(reset: true)
        }
    }

    private var visibleThreads: [ForumThread] {
        blockedUsers.filtering(threads)
    }

    private var scopeNotice: some View {
        Label(
            "覆盖普通版面与用户版面；仅搜索标题，需要已登录且威望大于 0。",
            systemImage: "magnifyingglass"
        )
        .font(.footnote)
        .foregroundStyle(PaperTheme.mutedText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    private func search(reset: Bool) async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = reset ? 1 : currentPage
            let result = try await repository.searchThreads(query: keyword, page: page)
            threads = result.payload?.threads ?? []
            canLoadMore = result.hasMore && !threads.isEmpty
            searchedQuery = keyword
            currentPage = page
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadNextPage() async {
        guard !isLoadingMore else { return }

        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let result = try await repository.searchThreads(query: searchedQuery, page: nextPage)
            let newThreads = result.payload?.threads ?? []
            guard !newThreads.isEmpty else {
                canLoadMore = false
                return
            }
            threads.append(contentsOf: newThreads.filter { newThread in
                !threads.contains(where: { $0.id == newThread.id })
            })
            canLoadMore = result.hasMore
            currentPage = nextPage
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
