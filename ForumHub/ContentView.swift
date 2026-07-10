import Foundation
import CoreFoundation
import Observation
import Security
import SwiftUI
import UIKit
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
                .navigationDestination(isPresented: $showsSearchResults) {
                    SearchThreadsView(
                        initialQuery: submittedSearchText,
                        repository: viewModel.repository,
                        blockedUsers: blockedUsers,
                        favoriteThreads: favoriteThreads
                    )
                }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(selectedTab == .user ? .visible : .hidden, for: .navigationBar)
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
            await AuthSessionRegistry.restoreAll(
                ngaRestore: viewModel.restoreSession,
                v2exAuthStore: v2exAuthStore,
                linuxDoAuthStore: linuxDoAuthStore
            )
            subscriptions.prepareDefaults(for: viewModel.channels)
            await viewModel.reload()
            selectedChannelID = viewModel.forum.id
        }
        .onChange(of: selectedTab) { _, tab in
            Task {
                await handleTabSelection(tab, isReselection: false)
            }
        }
    }

    private var mainContent: some View {
        ZStack {
            PaperBackground()

            TabView(selection: $selectedTab) {
                feedTabContent(for: .home)
                    .tag(FeedTab.home)
                    .tabItem {
                        Label(FeedTab.home.title, systemImage: FeedTab.home.systemImage)
                    }

                feedTabContent(for: .hot)
                    .tag(FeedTab.hot)
                    .tabItem {
                        Label(FeedTab.hot.title, systemImage: FeedTab.hot.systemImage)
                    }

                communityTabContent
                    .tag(FeedTab.community)
                    .tabItem {
                        Label(FeedTab.community.title, systemImage: FeedTab.community.systemImage)
                    }

                historyTabContent
                    .tag(FeedTab.history)
                    .tabItem {
                        Label(FeedTab.history.title, systemImage: FeedTab.history.systemImage)
                    }

                userTabContent
                    .tag(FeedTab.user)
                    .tabItem {
                        Label(FeedTab.user.title, systemImage: FeedTab.user.systemImage)
                    }
            }
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.automatic, for: .tabBar)
            .background(ForumTabBarAppearanceInstaller(accentColor: UIColor(PaperTheme.accent)))
            .background {
                ForumTabBarReselectionBridge(currentTab: selectedTab) { tab in
                    Task {
                        await handleTabSelection(tab, isReselection: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.light)
    }

    private var userTabContent: some View {
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
        .background(PaperTheme.paper)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var communityTabContent: some View {
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
        .background(PaperTheme.paper)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var historyTabContent: some View {
        BrowsingHistoryView(
            history: browsingHistory,
            blockedUsers: blockedUsers,
            favoriteThreads: favoriteThreads,
            scrollToTopTrigger: historyScrollToTopTrigger,
            repositoryForSource: { source in
                viewModel.repository(for: source)
            }
        )
        .background(PaperTheme.paper)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func feedTabContent(for tab: FeedTab) -> some View {
        VStack(spacing: 0) {
            ForumTopBar(
                searchText: $searchText,
                selectedChannelID: $selectedChannelID,
                selectedSource: viewModel.source,
                availableSources: viewModel.availableSources,
                forum: viewModel.forum,
                channels: tab == .hot ? [] : visibleChannels,
                childChannels: tab == .home ? availableChildChannels : [],
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
                pinnedThreads: tab == .hot ? [] : displayedPinnedThreads,
                threads: displayedThreads,
                repository: viewModel.repository,
                blockedUsers: blockedUsers,
                favoriteThreads: favoriteThreads,
                isLoading: viewModel.isLoading,
                hasLoadedInitialFeed: viewModel.hasLoadedInitialFeed,
                isLoadingMore: viewModel.isLoadingMore,
                canLoadMore: viewModel.canLoadMore,
                errorMessage: viewModel.errorMessage,
                scrollToTopTrigger: feedScrollToTopTrigger,
                showsRetapRefreshIndicator: showsFeedRetapRefreshIndicator,
                sortMode: feedSortMode,
                showsPinnedThreads: showsPinnedThreads,
                canTogglePinnedThreads: !viewModel.pinnedThreads.isEmpty && tab != .hot,
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
                    guard tab == .home,
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
        .background(PaperTheme.paper)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

private struct ForumTabBarAppearanceInstaller: UIViewControllerRepresentable {
    let accentColor: UIColor

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.accentColor = accentColor
        controller.applySoon()
    }

    final class Controller: UIViewController {
        var accentColor: UIColor = .systemOrange

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyAppearance()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyAppearance()
        }

        func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.applyAppearance()
            }
        }

        private func applyAppearance() {
            guard let tabBar = tabBarController?.tabBar ?? enclosingTabBarController()?.tabBar else { return }

            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            appearance.backgroundColor = UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor.black.withAlphaComponent(0.16)
                    : UIColor.systemBackground.withAlphaComponent(0.14)
            }
            appearance.shadowColor = UIColor.label.withAlphaComponent(0.04)

            let normalColor = UIColor.secondaryLabel.withAlphaComponent(0.82)
            configure(appearance.stackedLayoutAppearance, normalColor: normalColor, selectedColor: accentColor)
            configure(appearance.inlineLayoutAppearance, normalColor: normalColor, selectedColor: accentColor)
            configure(appearance.compactInlineLayoutAppearance, normalColor: normalColor, selectedColor: accentColor)

            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.tintColor = accentColor
            tabBar.unselectedItemTintColor = normalColor
            tabBar.isTranslucent = true
            tabBar.backgroundColor = .clear
            tabBar.layer.shadowColor = UIColor.black.cgColor
            tabBar.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.12 : 0.05
            tabBar.layer.shadowRadius = 14
            tabBar.layer.shadowOffset = CGSize(width: 0, height: -2)
        }

        private func configure(
            _ itemAppearance: UITabBarItemAppearance,
            normalColor: UIColor,
            selectedColor: UIColor
        ) {
            itemAppearance.normal.iconColor = normalColor
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: normalColor,
                .font: UIFont.systemFont(ofSize: 11.5, weight: .semibold)
            ]
            itemAppearance.selected.iconColor = selectedColor
            itemAppearance.selected.titleTextAttributes = [
                .foregroundColor: selectedColor,
                .font: UIFont.systemFont(ofSize: 11.5, weight: .bold)
            ]
        }

        private func enclosingTabBarController() -> UITabBarController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let tabBarController = current as? UITabBarController {
                    return tabBarController
                }
                responder = current.next
            }
            return nil
        }
    }
}

private struct ForumTabBarReselectionBridge: UIViewControllerRepresentable {
    let currentTab: FeedTab
    let onReselect: (FeedTab) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(currentTab: currentTab, onReselect: onReselect)
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onAttach = { tabBar in
            context.coordinator.attach(to: tabBar)
        }
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        context.coordinator.currentTab = currentTab
        context.coordinator.onReselect = onReselect
        controller.onAttach = { tabBar in
            context.coordinator.attach(to: tabBar)
        }
        controller.attachIfPossible()
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var currentTab: FeedTab
        var onReselect: (FeedTab) -> Void
        private weak var tabBar: UITabBar?
        private weak var previousDelegate: UITabBarDelegate?

        init(currentTab: FeedTab, onReselect: @escaping (FeedTab) -> Void) {
            self.currentTab = currentTab
            self.onReselect = onReselect
        }

        func attach(to tabBar: UITabBar) {
            guard self.tabBar !== tabBar else { return }
            previousDelegate = tabBar.delegate
            self.tabBar = tabBar
            tabBar.delegate = self
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let items = tabBar.items,
                  let index = items.firstIndex(of: item)
            else { return }
            let tabs = FeedTab.allCases
            guard tabs.indices.contains(index) else { return }
            let tab = tabs[index]
            if tab == currentTab {
                onReselect(tab)
            }
            previousDelegate?.tabBar?(tabBar, didSelect: item)
        }
    }

    final class Controller: UIViewController {
        var onAttach: ((UITabBar) -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachIfPossible()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            attachIfPossible()
        }

        func attachIfPossible() {
            guard let tabBar = tabBarController?.tabBar ?? enclosingTabBarController()?.tabBar else { return }
            onAttach?(tabBar)
        }

        private func enclosingTabBarController() -> UITabBarController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let tabBarController = current as? UITabBarController {
                    return tabBarController
                }
                responder = current.next
            }
            return nil
        }
    }
}

#Preview {
    ContentView(viewModel: .preview())
}
