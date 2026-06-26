import SwiftUI

struct FavoriteThreadsView: View {
    let repository: any ThreadRepository
    @Bindable var blockedUsers: BlockedUsersStore
    @Bindable var favoriteThreads: FavoriteThreadsStore
    @State private var threads: [ForumThread] = []
    @State private var currentPage = 1
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                            .padding(14)
                    }

                    if threads.isEmpty, isLoading {
                        ProgressView("正在加载收藏")
                            .tint(PaperTheme.accent)
                            .foregroundStyle(PaperTheme.mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                    } else if threads.isEmpty {
                        ContentUnavailableView(
                            "暂无收藏帖子",
                            systemImage: "star",
                            description: Text("在 NGA 收藏的主题会显示在这里。")
                        )
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .padding(.top, 80)
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
                await loadFavorites()
            }
        }
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .task {
            guard threads.isEmpty else { return }
            await loadFavorites()
        }
    }

    private var visibleThreads: [ForumThread] {
        blockedUsers.filtering(threads)
    }

    private func loadFavorites() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await repository.fetchFavoriteThreads(page: 1)
            threads = result.payload?.threads ?? []
            threads.forEach { favoriteThreads.save($0) }
            canLoadMore = result.hasMore && !threads.isEmpty
            currentPage = 1
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
            let result = try await repository.fetchFavoriteThreads(page: nextPage)
            let newThreads = result.payload?.threads ?? []
            guard !newThreads.isEmpty else {
                canLoadMore = false
                return
            }
            newThreads.forEach { favoriteThreads.save($0) }
            threads.append(contentsOf: newThreads.filter { newThread in
                !threads.contains(where: { $0.id == newThread.id })
            })
            canLoadMore = result.hasMore
            currentPage = nextPage
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
