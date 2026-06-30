import Foundation
import CoreFoundation
import Observation
import Security
import SwiftUI
import WebKit

@MainActor
struct ContentView: View {
    @State private var viewModel: ForumViewModel
    @State private var showsLogin = false
    @State private var searchText = ""
    @State private var submittedSearchText = ""
    @State private var showsSearchResults = false
    @State private var selectedChannelID = ForumChannel.defaultForum.id
    @State private var selectedTab: FeedTab = .home
    @State private var subscriptions = ForumSubscriptionStore()
    @State private var blockedUsers = BlockedUsersStore()
    @State private var favoriteThreads = FavoriteThreadsStore()
    @State private var v2exAuthStore = V2EXAuthStore()
    @State private var linuxDoAuthStore = LinuxDoAuthStore()
    @State private var browsingHistory = BrowsingHistoryStore()
    @State private var feedScrollToTopTrigger = 0
    @State private var communityScrollToTopTrigger = 0
    @State private var historyScrollToTopTrigger = 0
    @State private var userScrollToTopTrigger = 0
    @State private var showsFeedRetapRefreshIndicator = false
    @State private var feedRetapRefreshGeneration = 0
    @State private var feedSortMode: FeedSortMode = .lastReply
    @State private var showsPinnedThreads = true

    init() {
        if ProcessInfo.processInfo.arguments.contains("UITEST_PAGED_THREAD") {
            _viewModel = State(initialValue: ForumViewModel.pagedPreview())
        } else {
            _viewModel = State(initialValue: ForumViewModel())
        }
    }

    init(viewModel: ForumViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            mainContent
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(selectedTab == .user ? .visible : .hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsSearchResults) {
                SearchThreadsView(
                    initialQuery: submittedSearchText,
                    repository: viewModel.repository,
                    blockedUsers: blockedUsers,
                    favoriteThreads: favoriteThreads
                )
            }
        }
        .sheet(isPresented: $showsLogin) {
            NGALoginSheet {
                showsLogin = false
                Task {
                    await viewModel.restoreSession()
                    await viewModel.reload()
                }
            }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("UITEST_PAGED_THREAD") {
                subscriptions.prepareDefaults(for: viewModel.channels)
                selectedChannelID = viewModel.forum.id
                return
            }
            async let ngaSession: Void = viewModel.restoreSession()
            async let v2exSession: Void = v2exAuthStore.restoreSession()
            async let linuxDoSession: Void = linuxDoAuthStore.restoreSession()
            _ = await (ngaSession, v2exSession, linuxDoSession)
            subscriptions.prepareDefaults(for: viewModel.channels)
            await viewModel.reload()
            selectedChannelID = viewModel.forum.id
        }
    }

    private var mainContent: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                if selectedTab == .user {
                    UserAccountView(
                        loginState: viewModel.loginState,
                        isAuthenticated: viewModel.isAuthenticated,
                        repository: viewModel.repository,
                        activeSource: viewModel.source,
                        availableSources: viewModel.availableSources,
                        capabilities: viewModel.capabilities,
                        blockedUsers: blockedUsers,
                        favoriteThreads: favoriteThreads,
                        v2exAuthStore: v2exAuthStore,
                        linuxDoAuthStore: linuxDoAuthStore,
                        scrollToTopTrigger: userScrollToTopTrigger,
                        repositoryForSource: { source in
                            viewModel.repository(for: source)
                        },
                        onLogin: {
                            showsLogin = true
                        },
                        onLogout: {
                            await viewModel.logout()
                            selectedTab = .home
                        }
                    )
                } else if selectedTab == .community {
                    CommunityView(
                        activeSource: viewModel.source,
                        channels: viewModel.channels,
                        isLoading: viewModel.isLoading,
                        subscriptions: subscriptions,
                        scrollToTopTrigger: communityScrollToTopTrigger,
                        onChannelSelect: { channel in
                            selectedTab = .home
                            selectedChannelID = channel.id
                            await viewModel.switchForum(to: channel)
                        }
                    )
                } else if selectedTab == .history {
                    BrowsingHistoryView(
                        history: browsingHistory,
                        blockedUsers: blockedUsers,
                        favoriteThreads: favoriteThreads,
                        scrollToTopTrigger: historyScrollToTopTrigger,
                        repositoryForSource: { source in
                            viewModel.repository(for: source)
                        }
                    )
                } else {
                    ForumTopBar(
                        searchText: $searchText,
                        selectedChannelID: $selectedChannelID,
                        selectedSource: viewModel.source,
                        availableSources: viewModel.availableSources,
                        forum: viewModel.forum,
                        channels: visibleChannels,
                        childChannels: availableChildChannels,
                        selectedChildChannelIDs: viewModel.selectedChildChannelIDs,
                        isLoading: viewModel.isLoading,
                        isAuthenticated: viewModel.isAuthenticated,
                        isV2EXAuthenticated: v2exAuthStore.isAuthenticated,
                        linuxDoUsername: linuxDoAuthStore.username,
                        capabilities: viewModel.capabilities,
                        onSourceSelect: { source in
                            Task {
                                guard source != viewModel.source else { return }
                                searchText = ""
                                await viewModel.switchSource(to: source)
                                subscriptions.prepareDefaults(for: viewModel.channels)
                                selectedChannelID = viewModel.forum.id
                            }
                        },
                        onCommunitySelect: {
                            selectedTab = .community
                        },
                        onRefresh: {
                            Task {
                                await viewModel.reload()
                            }
                        },
                        onSearch: { query in
                            let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !keyword.isEmpty else { return }
                            submittedSearchText = keyword
                            showsSearchResults = true
                        },
                        onChannelSelect: { channel in
                            Task {
                                selectedTab = .home
                                selectedChannelID = channel.id
                                await viewModel.switchForum(to: channel)
                            }
                        },
                        onChildChannelToggle: { channel in
                            Task {
                                var ids = viewModel.selectedChildChannelIDs
                                if ids.contains(channel.id) {
                                    ids.remove(channel.id)
                                } else {
                                    ids.insert(channel.id)
                                }
                                await viewModel.setSelectedChildChannels(ids)
                            }
                        },
                        onResetChildChannels: {
                            Task {
                                await viewModel.setSelectedChildChannels([])
                            }
                        },
                        onCompose: {}
                    )

                    ForumFeedContent(
                        pinnedThreads: displayedPinnedThreads,
                        threads: displayedThreads,
                        repository: viewModel.repository,
                        blockedUsers: blockedUsers,
                        favoriteThreads: favoriteThreads,
                        isLoading: viewModel.isLoading,
                        isLoadingMore: viewModel.isLoadingMore,
                        canLoadMore: viewModel.canLoadMore,
                        errorMessage: viewModel.errorMessage,
                        scrollToTopTrigger: feedScrollToTopTrigger,
                        showsRetapRefreshIndicator: showsFeedRetapRefreshIndicator,
                        sortMode: feedSortMode,
                        showsPinnedThreads: showsPinnedThreads,
                        canTogglePinnedThreads: !viewModel.pinnedThreads.isEmpty && selectedTab != .hot,
                        onSortChange: { mode in
                            withAnimation(.snappy(duration: 0.22)) {
                                feedSortMode = mode
                            }
                        },
                        onPinnedVisibilityChange: { isVisible in
                            withAnimation(.snappy(duration: 0.22)) {
                                showsPinnedThreads = isVisible
                            }
                        },
                        onLoadNextPage: {
                            await viewModel.loadNextPage()
                        },
                        onOpenThread: { thread in
                            browsingHistory.record(thread)
                        },
                        onSwipeChannel: { direction in
                            guard selectedTab == .home,
                                  !viewModel.isLoading,
                                  let destination = ChannelPagingPolicy.destination(
                                    currentID: selectedChannelID,
                                    channels: visibleChannels,
                                    direction: direction
                                  )
                            else { return }

                            withAnimation(.snappy(duration: 0.28)) {
                                selectedChannelID = destination.id
                            }
                            Task {
                                await viewModel.switchForum(to: destination)
                            }
                        }
                    )
                    .refreshable {
                        await viewModel.reload()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            ForumBottomBar(selectedTab: $selectedTab) { tab, isReselection in
                Task {
                    await handleTabSelection(tab, isReselection: isReselection)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var visibleChannels: [ForumChannel] {
        guard selectedTab != .hot else { return [] }
        return subscriptions.visibleChannels(from: viewModel.channels)
    }

    private var displayedPinnedThreads: [ForumThread] {
        guard showsPinnedThreads, selectedTab != .hot else { return [] }
        return sortedThreads(viewModel.pinnedThreads)
    }

    private var displayedThreads: [ForumThread] {
        sortedThreads(viewModel.threads)
    }

    private func sortedThreads(_ threads: [ForumThread]) -> [ForumThread] {
        threads.sorted { lhs, rhs in
            switch feedSortMode {
            case .lastReply:
                let leftDate = lhs.lastReplySortDate ?? lhs.createdAtSortDate
                let rightDate = rhs.lastReplySortDate ?? rhs.createdAtSortDate
                if let leftDate, let rightDate, leftDate != rightDate {
                    return leftDate > rightDate
                }
            case .latestPost:
                let leftDate = lhs.createdAtSortDate ?? lhs.lastReplySortDate
                let rightDate = rhs.createdAtSortDate ?? rhs.lastReplySortDate
                if let leftDate, let rightDate, leftDate != rightDate {
                    return leftDate > rightDate
                }
            }

            if lhs.replyCount != rhs.replyCount {
                return lhs.replyCount > rhs.replyCount
            }

            return lhs.id > rhs.id
        }
    }

    private var availableChildChannels: [ForumChannel] {
        guard selectedTab == .home, selectedChannelID == viewModel.repository.defaultChannel.id else { return [] }
        return viewModel.availableChildChannels
    }

    private func handleTabSelection(_ tab: FeedTab, isReselection: Bool) async {
        if isReselection {
            switch tab {
            case .home, .hot:
                feedRetapRefreshGeneration += 1
                let generation = feedRetapRefreshGeneration
                withAnimation(.snappy(duration: 0.18)) {
                    showsFeedRetapRefreshIndicator = true
                }
                feedScrollToTopTrigger += 1
                async let reload: Void = viewModel.reload()
                do {
                    try await Task.sleep(for: .milliseconds(650))
                    await reload
                } catch {
                    await reload
                }
                guard generation == feedRetapRefreshGeneration else { return }
                withAnimation(.snappy(duration: 0.24)) {
                    showsFeedRetapRefreshIndicator = false
                }
            case .community:
                communityScrollToTopTrigger += 1
            case .history:
                historyScrollToTopTrigger += 1
            case .user:
                userScrollToTopTrigger += 1
            }
            return
        }

        switch tab {
        case .community, .history, .user:
            return
        case .home, .hot:
            break
        }

        await viewModel.switchFeed(to: tab)
    }

}

#Preview {
    ContentView(viewModel: .preview())
}
