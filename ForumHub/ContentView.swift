import Foundation
import CoreFoundation
import Observation
import Security
import SwiftUI
import UIKit
import WebKit

@MainActor
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: ForumViewModel
    @State private var showsLogin = false
    @State private var didCompleteLogin = false
    @State private var showsLinuxDoBrowserVerification = false
    @State private var submittedSearchText = ""
    @State private var showsSearchResults = false
    @State private var selectedChannelKey = ForumChannel.defaultForum.canonicalKey
    @State private var selectedTab: FeedTab = .home
    @State private var subscriptions = ForumSubscriptionStore()
    @State private var blockedUsers = BlockedUsersStore()
    @State private var favoriteThreads = FavoriteThreadsStore()
    @State private var v2exAuthStore = V2EXAuthStore()
    @State private var linuxDoAuthStore = LinuxDoAuthStore()
    @State private var browsingHistory = BrowsingHistoryStore()
    @State private var tabScrollRequest: TabScrollRequest?
    @State private var tabScrollRequestGeneration = 0
    @State private var feedRetapRefreshTab: FeedTab?
    @State private var feedRetapRefreshGeneration = 0
    @State private var showsPinnedThreads = true
    @State private var feedPreferences = FeedPreferencesStore()
    @State private var authoritativeChildForumDirectories = AuthoritativeChildForumDirectoryStore()
    @State private var cancelledSubscribedChannelNotice: String?
    @State private var isFeedHeaderCollapsed = false
    @State private var pendingComposeAction: PendingComposeAction?
    @State private var composeDestination: ComposeDestination?
    @State private var lastSessionRestoreAt: Date?

    init() {
        if let scenario = UITestScenario.current {
            UserDefaults.standard.removeObject(forKey: "forum-feed-preferences-v2")
            UserDefaults.standard.removeObject(forKey: "nga-authoritative-child-forum-directories-v1")
            _feedPreferences = State(initialValue: FeedPreferencesStore())
            _authoritativeChildForumDirectories = State(initialValue: AuthoritativeChildForumDirectoryStore())
            _viewModel = State(initialValue: scenario.makeViewModel())
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
        .sheet(isPresented: $showsLogin, onDismiss: {
            if !didCompleteLogin {
                pendingComposeAction = nil
            }
            didCompleteLogin = false
        }) {
            NGALoginSheet {
                didCompleteLogin = true
                showsLogin = false
                Task {
                    await viewModel.restoreSession()
                    await viewModel.reload()
                    resumePendingComposeIfPossible()
                }
            }
        }
        .sheet(item: $composeDestination) { destination in
            ForumComposeWebSheet(destination: destination)
        }
        .sheet(isPresented: $showsLinuxDoBrowserVerification, onDismiss: {
            Task { await viewModel.reload() }
        }) {
            LinuxDoLoginSheet(authStore: linuxDoAuthStore)
        }
        .task {
            if UITestScenario.current != nil {
                subscriptions.prepareDefaults(for: viewModel.channels)
                selectedChannelKey = viewModel.currentForumChannel.canonicalKey
                return
            }
            await AuthSessionRegistry.restoreAll(
                ngaRestore: viewModel.restoreSession,
                v2exAuthStore: v2exAuthStore,
                linuxDoAuthStore: linuxDoAuthStore
            )
            lastSessionRestoreAt = .now
            subscriptions.prepareDefaults(for: viewModel.channels)
            selectedChannelKey = viewModel.currentForumChannel.canonicalKey
            await refreshAuthoritativeChildForumsAndRestorePreferences()
            await viewModel.reload()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: NSUbiquitousKeyValueStore.default
            )
        ) { notification in
            guard let reason = (notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber)?.intValue else {
                return
            }
            blockedUsers.handleICloudChange(reason: reason)
        }
        .onChange(of: selectedTab) { _, tab in
            Task {
                await handleTabSelection(tab, isReselection: false)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            guard UITestScenario.current == nil else { return }
            blockedUsers.refreshFromICloud(reconcilesConflicts: true)
            guard lastSessionRestoreAt.map({ Date.now.timeIntervalSince($0) >= 30 }) ?? true else {
                return
            }
            lastSessionRestoreAt = .now
            Task {
                await AuthSessionRegistry.restoreAll(
                    ngaRestore: viewModel.restoreSession,
                    v2exAuthStore: v2exAuthStore,
                    linuxDoAuthStore: linuxDoAuthStore
                )
                await refreshAuthoritativeChildForumsAndRestorePreferences(reloadsFeedOnSelectionChange: true)
            }
        }
    }

    private var mainContent: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                if selectedTab == .home || selectedTab == .hot {
                    feedTopBar
                }

                TabView(selection: $selectedTab) {
                    feedTabContent(for: .home)
                        .tag(FeedTab.home)
                        .tabItem { Label(FeedTab.home.title, systemImage: FeedTab.home.systemImage) }

                    feedTabContent(for: .hot)
                        .tag(FeedTab.hot)
                        .tabItem { Label(FeedTab.hot.title, systemImage: FeedTab.hot.systemImage) }

                    communityTabContent
                        .tag(FeedTab.community)
                        .tabItem { Label(FeedTab.community.title, systemImage: FeedTab.community.systemImage) }

                    historyTabContent
                        .tag(FeedTab.history)
                        .tabItem { Label(FeedTab.history.title, systemImage: FeedTab.history.systemImage) }

                    userTabContent
                        .tag(FeedTab.user)
                        .tabItem { Label(FeedTab.user.title, systemImage: FeedTab.user.systemImage) }
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
            scrollRequest: tabScrollRequest,
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
            catalog: channelCatalog,
            isLoading: viewModel.isLoading,
            pendingNewChildKeys: viewModel.pendingNewChildForumStableKeys,
            cancelledSubscriptionNotice: cancelledSubscribedChannelNotice,
            subscriptions: subscriptions,
            scrollRequest: tabScrollRequest,
            onChannelSelect: { channel in
                selectedTab = .home
                await switchToChannel(channel)
            },
            onCancelledSubscriptionNoticeDismiss: {
                cancelledSubscribedChannelNotice = nil
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
            scrollRequest: tabScrollRequest,
            repositoryForSource: { source in
                viewModel.repository(for: source)
            }
        )
        .background(PaperTheme.paper)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func feedTabContent(for tab: FeedTab) -> some View {
        ForumFeedContent(
                tab: tab,
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
                showsBrowserVerificationAction: viewModel.source == .linuxDo && viewModel.requiresLinuxDoBrowserVerification,
                scrollRequest: tabScrollRequest,
                showsRetapRefreshIndicator: feedRetapRefreshTab == tab,
                sortMode: viewModel.feedSortMode,
                filterState: currentFilterState,
                childChannels: tab == .home ? availableChildChannels : [],
                childForumStatus: tab == .home ? currentChildForumStatus : FeedChildForumStatus(),
                onSortChange: { mode in
                    withAnimation(.snappy(duration: 0.22)) { viewModel.feedSortMode = mode }
                    persistFeedPreferences()
                },
                onFilterApply: { filter in
                    withAnimation(.snappy(duration: 0.22)) {
                        showsPinnedThreads = filter.showsPinnedThreads
                    }
                    persistFeedPreferences(filter: filter)
                    await viewModel.setSelectedChildForumKeys(filter.selectedChildForumKeys)
                },
                onFilterReset: {
                    let reset = FeedFilterState()
                    withAnimation(.snappy(duration: 0.22)) { showsPinnedThreads = true }
                    persistFeedPreferences(filter: reset)
                    await viewModel.setSelectedChildForumKeys([])
                },
                onNewChildForumsSeen: {
                    viewModel.confirmPendingNewChildForumsSeen(using: authoritativeChildForumDirectories)
                },
                onCancelledChildForumNoticeDismiss: {
                    viewModel.dismissCancelledChildForumNotice()
                },
                onRetryFailedChildForums: {
                    await viewModel.retryFailedChildForums()
                },
                onRefresh: { await viewModel.reload() },
                onLoadNextPage: { await viewModel.loadNextPage() },
                onBrowserVerificationRequested: {
                    showsLinuxDoBrowserVerification = true
                },
                onOpenThread: { browsingHistory.record($0) },
                onSwipeChannel: { direction in
                    guard tab == .home,
                          !viewModel.isLoading,
                          let destination = ChannelPagingPolicy.destination(
                            currentKey: selectedChannelKey,
                            channels: visibleChannels,
                            direction: direction
                          )
                    else { return }
                    withAnimation(.snappy(duration: 0.28)) { selectedChannelKey = destination.canonicalKey }
                    Task { await switchToChannel(destination) }
                },
                onHeaderCollapseChange: { collapsed in
                    guard tab == selectedTab, isFeedHeaderCollapsed != collapsed else { return }
                    withAnimation(.snappy(duration: 0.22)) { isFeedHeaderCollapsed = collapsed }
                }
            )
            .background(PaperTheme.paper)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var feedTopBar: some View {
        ForumTopBar(
                selectedChannelKey: $selectedChannelKey,
                activeTab: selectedTab,
                selectedSource: viewModel.source,
                availableSources: viewModel.availableSources,
                channels: selectedTab == .hot ? [] : visibleChannels,
                isLoading: viewModel.isLoading,
                isAuthenticated: viewModel.isAuthenticated,
                isV2EXAuthenticated: v2exAuthStore.isAuthenticated,
                linuxDoUsername: linuxDoAuthStore.username,
                capabilities: viewModel.capabilities,
                canComposeInCurrentChannel: canComposeInCurrentChannel,
                sessionState: activeSessionState,
                isCollapsed: isFeedHeaderCollapsed,
                onSourceSelect: { source in
                    Task {
                        guard source != viewModel.source else { return }
                        pendingComposeAction = nil
                        composeDestination = nil
                        isFeedHeaderCollapsed = false
                        await viewModel.switchSource(to: source, reloadsFeed: false)
                        subscriptions.prepareDefaults(for: viewModel.channels)
                        selectedChannelKey = viewModel.currentForumChannel.canonicalKey
                        await refreshAuthoritativeChildForumsAndRestorePreferences()
                        await viewModel.reload()
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
                        await switchToChannel(channel)
                    }
                },
                onCompose: handleComposeTap,
                onLogin: handleHomeLogin
            )
    }

    private var visibleChannels: [ForumChannel] {
        guard selectedTab != .hot else { return [] }
        return subscriptions.visibleChannels(from: channelCatalog.channels)
    }

    private var channelCatalog: ForumChannelCatalog {
        ForumChannelCatalog.build(
            source: viewModel.source,
            channels: viewModel.channels,
            authoritativeDirectory: viewModel.authoritativeChildForumDirectory
        )
    }

    private var displayedPinnedThreads: [ForumThread] {
        guard showsPinnedThreads, selectedTab != .hot else { return [] }
        return viewModel.displayedPinnedThreads
    }

    private var displayedThreads: [ForumThread] {
        viewModel.displayedThreads
    }

    private var availableChildChannels: [AuthoritativeChildForum] {
        guard selectedTab == .home,
              selectedChannelKey == viewModel.repository.defaultChannel.canonicalKey
        else { return [] }
        return viewModel.availableChildChannels
    }

    private var currentFilterState: FeedFilterState {
        FeedFilterState(
            selectedChildForumKeys: viewModel.selectedChildForumKeys,
            showsPinnedThreads: showsPinnedThreads
        )
    }

    private var currentChildForumStatus: FeedChildForumStatus {
        let isApplicable = selectedTab == .home
            && viewModel.source == .nga
            && selectedChannelKey == viewModel.repository.defaultChannel.canonicalKey
        return FeedChildForumStatus(
            isApplicable: isApplicable,
            hasConfirmedDirectory: isApplicable && viewModel.authoritativeChildForumDirectory != nil,
            pendingNewStableKeys: isApplicable ? viewModel.pendingNewChildForumStableKeys : [],
            cancelledSelectionNotice: isApplicable ? viewModel.cancelledChildForumNotice : nil,
            failedChildForumCount: isApplicable ? viewModel.failedChildForumStableKeys.count : 0
        )
    }

    private var activeSessionState: SourceSessionState {
        switch viewModel.source {
        case .nga:
            return viewModel.sessionState
        case .v2ex:
            return (v2exAuthStore.isAuthenticated || v2exAuthStore.hasWebSession) ? .authenticated : .signedOut
        case .linuxDo:
            return linuxDoAuthStore.isAuthenticated ? .authenticated : .signedOut
        }
    }

    private var canComposeInCurrentChannel: Bool {
        guard viewModel.capabilities.supportsCreateThread else { return false }
        return !(viewModel.source == .nga && viewModel.currentForumChannel.canonicalNativeKey.hasPrefix("stid:"))
    }

    private func restoreFeedPreferences() {
        let preference = feedPreferences.preference(
            source: viewModel.source,
            parent: viewModel.currentForumChannel,
            directory: viewModel.authoritativeChildForumDirectory
        )
        showsPinnedThreads = preference.filter.showsPinnedThreads
        viewModel.restoreFeedPreferences(
            sortMode: preference.sortMode,
            selectedChildForumKeys: preference.filter.selectedChildForumKeys
        )
    }

    private func refreshAuthoritativeChildForumsAndRestorePreferences(
        reloadsFeedOnSelectionChange: Bool = false
    ) async {
        viewModel.restoreCachedAuthoritativeChildForumDirectory(using: authoritativeChildForumDirectories)
        restoreFeedPreferences()
        let result = await viewModel.refreshAuthoritativeChildForumDirectory(
            using: authoritativeChildForumDirectories,
            reloadsFeedOnSelectionChange: reloadsFeedOnSelectionChange
        )
        if let result {
            feedPreferences.removeCancelledAuthoritativeChildForumKeys(
                result.removedStableKeys,
                source: viewModel.source,
                parent: viewModel.repository.defaultChannel
            )
            let removed = subscriptions.removeCancelledAuthoritativeChannels(
                result.removedChildren.map(\.channel)
            )
            if removed.count == 1, let title = removed.first?.title {
                cancelledSubscribedChannelNotice = "\(title) 已从首页栏目中移除。"
            } else if !removed.isEmpty {
                cancelledSubscribedChannelNotice = "\(removed.count) 个已取消子版已从首页栏目中移除。"
            }
        }
        restoreFeedPreferences()
    }

    private func persistFeedPreferences(filter: FeedFilterState? = nil) {
        feedPreferences.save(
            source: viewModel.source,
            parent: viewModel.currentForumChannel,
            sortMode: viewModel.feedSortMode,
            filter: filter ?? currentFilterState
        )
    }

    private func switchToChannel(_ channel: ForumChannel) async {
        selectedChannelKey = channel.canonicalKey
        await viewModel.switchForum(to: channel, reloadsFeed: false)
        await refreshAuthoritativeChildForumsAndRestorePreferences()
        await viewModel.reload()
    }

    private func handleHomeLogin() {
        switch viewModel.source {
        case .nga:
            showsLogin = true
        case .v2ex, .linuxDo:
            selectedTab = .user
        }
    }

    private func handleComposeTap() {
        guard canComposeInCurrentChannel else { return }
        let action = PendingComposeAction(source: viewModel.source, channelID: viewModel.currentForumChannel.id)
        guard activeSessionState == .authenticated else {
            pendingComposeAction = action
            handleHomeLogin()
            return
        }
        openCompose(action)
    }

    private func resumePendingComposeIfPossible() {
        guard let action = pendingComposeAction,
              action.canResume(
                source: viewModel.source,
                channelID: viewModel.currentForumChannel.id,
                sessionState: activeSessionState,
                capabilities: viewModel.capabilities
              )
        else {
            pendingComposeAction = nil
            return
        }
        pendingComposeAction = nil
        openCompose(action)
    }

    private func openCompose(_ action: PendingComposeAction) {
        guard let url = action.destinationURL else { return }
        composeDestination = ComposeDestination(
            source: action.source,
            channelTitle: visibleChannels.first(where: { $0.canonicalKey == selectedChannelKey })?.title ?? viewModel.forum.title,
            url: url
        )
    }

    private func handleTabSelection(_ tab: FeedTab, isReselection: Bool) async {
        if isReselection {
            switch TabReselectionPolicy.behavior(for: tab) {
            case .scrollToTopAndRefresh:
                requestScrollToTop(of: tab)
                feedRetapRefreshGeneration += 1
                let generation = feedRetapRefreshGeneration
                withAnimation(.snappy(duration: 0.18)) {
                    feedRetapRefreshTab = tab
                }
                await viewModel.reload()
                guard generation == feedRetapRefreshGeneration else { return }
                if selectedTab == tab {
                    // Refresh can replace the feed rows after the immediate scroll command.
                    requestScrollToTop(of: tab)
                }
                withAnimation(.snappy(duration: 0.24)) {
                    feedRetapRefreshTab = nil
                }
            case .scrollToTop:
                requestScrollToTop(of: tab)
            }
            return
        }

        switch tab {
        case .community, .history, .user:
            viewModel.suspendFeedLoading()
            return
        case .home, .hot:
            break
        }

        await viewModel.switchFeed(to: tab)
    }

    private func requestScrollToTop(of tab: FeedTab) {
        tabScrollRequestGeneration += 1
        tabScrollRequest = TabScrollRequest(id: tabScrollRequestGeneration, target: tab)
    }

}

struct PendingComposeAction: Equatable {
    let source: ForumSource
    let channelID: Int

    var destinationURL: URL? {
        guard source == .nga else { return nil }
        var components = URLComponents(string: "https://bbs.nga.cn/post.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "new"),
            URLQueryItem(name: "fid", value: String(channelID))
        ]
        return components?.url
    }

    func canResume(
        source currentSource: ForumSource,
        channelID currentChannelID: Int,
        sessionState: SourceSessionState,
        capabilities: ForumCapabilities
    ) -> Bool {
        source == currentSource
            && channelID == currentChannelID
            && sessionState == .authenticated
            && capabilities.supportsCreateThread
            && destinationURL != nil
    }
}

private struct ComposeDestination: Identifiable {
    let id = UUID()
    let source: ForumSource
    let channelTitle: String
    let url: URL
}

private struct ForumComposeWebSheet: View {
    let destination: ComposeDestination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ForumComposeWebView(url: destination.url, source: destination.source)
                .navigationTitle("在\(destination.channelTitle)发帖")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") { dismiss() }
                    }
                }
        }
    }
}

private struct ForumComposeWebView: UIViewRepresentable {
    let url: URL
    let source: ForumSource

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        Task {
            if source == .nga {
                _ = await NGAAuthStore.shared.currentLoginState()
            }
            for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
                await context.coordinator.set(cookie: cookie, in: configuration.websiteDataStore.httpCookieStore)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { _ = webView.load(URLRequest(url: url)) }
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        func set(cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) { continuation.resume() }
            }
        }
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

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var currentTab: FeedTab
        var onReselect: (FeedTab) -> Void
        private weak var tabBar: UITabBar?
        private var tapRecognizer: UITapGestureRecognizer?

        init(currentTab: FeedTab, onReselect: @escaping (FeedTab) -> Void) {
            self.currentTab = currentTab
            self.onReselect = onReselect
        }

        func attach(to tabBar: UITabBar) {
            guard self.tabBar !== tabBar else { return }
            if let previousTabBar = self.tabBar,
               let tapRecognizer {
                previousTabBar.removeGestureRecognizer(tapRecognizer)
            }

            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tabBarTapped))
            tapRecognizer.cancelsTouchesInView = false
            tapRecognizer.delaysTouchesBegan = false
            tapRecognizer.delaysTouchesEnded = false
            tapRecognizer.delegate = self
            self.tabBar = tabBar
            self.tapRecognizer = tapRecognizer
            tabBar.addGestureRecognizer(tapRecognizer)
        }

        @objc private func tabBarTapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let tabBar,
                  let tab = tab(at: recognizer.location(in: tabBar), in: tabBar)
            else { return }

            guard tab == currentTab else { return }
            onReselect(tab)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func tab(at location: CGPoint, in tabBar: UITabBar) -> FeedTab? {
            guard let items = tabBar.items,
                  let index = itemIndex(at: location, in: tabBar, itemCount: items.count)
            else { return nil }
            let tabs = FeedTab.allCases
            guard tabs.indices.contains(index) else { return nil }
            return tabs[index]
        }

        private func itemIndex(at location: CGPoint, in tabBar: UITabBar, itemCount: Int) -> Int? {
            let controls = tabBar.subviews
                .compactMap { $0 as? UIControl }
                .filter { !$0.isHidden && $0.alpha > 0 && $0.bounds.width > 0 }
                .sorted { $0.frame.minX < $1.frame.minX }

            if controls.count == itemCount,
               let index = controls.firstIndex(where: { $0.frame.contains(location) }) {
                return index
            }

            // Native tab buttons are normally UIControls; retain a geometric fallback
            // if SwiftUI changes their internal view hierarchy in a future iOS release.
            guard itemCount > 0, tabBar.bounds.width > 0 else { return nil }
            let index = Int(location.x / (tabBar.bounds.width / CGFloat(itemCount)))
            return (0..<itemCount).contains(index) ? index : nil
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
