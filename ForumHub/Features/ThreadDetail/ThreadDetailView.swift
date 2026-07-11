import Foundation
import SwiftUI
import UIKit

private enum ThreadDetailScrollAnchor: Hashable {
    case top
}

struct ThreadDetailView: View {
    let thread: ForumThread
    let repository: any ThreadRepository
    @Bindable var blockedUsers: BlockedUsersStore
    @Bindable var favoriteThreads: FavoriteThreadsStore
    private let topAnchorID = ThreadDetailScrollAnchor.top
    private let replyTopAnchorID = "thread-detail-reply-top-anchor"
    private let scrollTrackingSpaceName = "thread-detail-scroll"
    private let directPaginationPrefetchReplyDistance = 6
    private let inlineGIFPlaybackCoordinator = InlineGIFPlaybackCoordinator()
    @State private var showsOnlyThreadAuthor = false
    @State private var showsRepliesInReverseOrder = false
    @State private var isPreparingSnapshot = false
    @State private var snapshotImages: [UIImage] = []
    @State private var showsSnapshotPreview = false
    @State private var snapshotErrorMessage: String?
    @State private var showsPagePicker = false
    @State private var detailViewModel: ThreadDetailViewModel
    @State private var showsScrollToTopButton = false
    @State private var isReturningToTop = false
    @State private var scrollToTopRequestGeneration = 0
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var lastObservedScrollOffset: CGFloat = 0
    @State private var activeInlineGIFPlaybackIDs: Set<UUID> = []
    @State private var cachedDisplayedReplies: [Reply] = []
    @State private var cachedDisplayedReplyEntries: [ThreadDetailDisplayedReplyEntry] = []

    init(
        thread: ForumThread,
        repository: any ThreadRepository,
        blockedUsers: BlockedUsersStore,
        favoriteThreads: FavoriteThreadsStore
    ) {
        self.thread = thread
        self.repository = repository
        self.blockedUsers = blockedUsers
        self.favoriteThreads = favoriteThreads
        _detailViewModel = State(initialValue: ThreadDetailViewModel(thread: thread))
    }

    private var actionState: ThreadDetailActionState { detailViewModel.actions }
    private var paginationState: ThreadDetailPaginationState { detailViewModel.pagination }
    private var contentLoadController: ThreadDetailContentLoadController { detailViewModel.contentLoader }
    private var detailThread: ForumThread { get { detailViewModel.content.thread } nonmutating set { detailViewModel.content.thread = newValue } }
    private var canonicalThread: ForumThread? { get { detailViewModel.content.canonicalThread } nonmutating set { detailViewModel.content.canonicalThread = newValue } }
    private var threadReplyTotalCount: Int { get { detailViewModel.content.replyTotalCount } nonmutating set { detailViewModel.content.replyTotalCount = newValue } }
    private var isLoading: Bool { get { detailViewModel.content.isLoading } nonmutating set { detailViewModel.content.isLoading = newValue } }
    private var isLoadingMore: Bool { get { detailViewModel.content.isLoadingMore } nonmutating set { detailViewModel.content.isLoadingMore = newValue } }
    private var contentError: ForumError? { get { detailViewModel.content.error } nonmutating set { detailViewModel.content.error = newValue } }

    private var currentPage: Int {
        get { paginationState.currentPage }
        nonmutating set { paginationState.currentPage = newValue }
    }

    private var hasMoreReplies: Bool {
        get { paginationState.hasMoreReplies }
        nonmutating set { paginationState.hasMoreReplies = newValue }
    }

    private var visiblePage: Int {
        get { paginationState.visiblePage }
        nonmutating set { paginationState.visiblePage = newValue }
    }

    private var loadedPageStartReplyIndices: [Int: Int] {
        get { paginationState.pageStartReplyIndices }
        nonmutating set { paginationState.pageStartReplyIndices = newValue }
    }

    private var pendingPageSelection: Int {
        get { paginationState.pendingPageSelection }
        nonmutating set { paginationState.pendingPageSelection = newValue }
    }

    private var deferredScrollTargetPage: Int? {
        get { paginationState.deferredScrollTargetPage }
        nonmutating set { paginationState.deferredScrollTargetPage = newValue }
    }

    private var lastAutoLoadedPage: Int? {
        get { paginationState.lastAutoLoadedPage }
        nonmutating set { paginationState.lastAutoLoadedPage = newValue }
    }

    private var pendingPageSelectionBinding: Binding<Int> {
        Binding(get: { paginationState.pendingPageSelection }, set: { paginationState.pendingPageSelection = $0 })
    }

    private var favoriteErrorMessage: String? { get { actionState.favoriteErrorMessage } nonmutating set { actionState.favoriteErrorMessage = newValue } }
    private var isUpdatingFavorite: Bool { get { actionState.isUpdatingFavorite } nonmutating set { actionState.isUpdatingFavorite = newValue } }
    private var showsReplyComposer: Bool { get { actionState.showsReplyComposer } nonmutating set { actionState.showsReplyComposer = newValue } }
    private var replyTarget: ThreadReplyTarget { get { actionState.replyTarget } nonmutating set { actionState.replyTarget = newValue } }
    private var replyText: String { get { actionState.replyText } nonmutating set { actionState.replyText = newValue } }
    private var replyAttachments: [ReplyComposerAttachment] { get { actionState.replyAttachments } nonmutating set { actionState.replyAttachments = newValue } }
    private var isSubmittingReply: Bool { get { actionState.isSubmittingReply } nonmutating set { actionState.isSubmittingReply = newValue } }
    private var replyErrorMessage: String? { get { actionState.replyErrorMessage } nonmutating set { actionState.replyErrorMessage = newValue } }
    private var replySuccessMessage: String? { get { actionState.replySuccessMessage } nonmutating set { actionState.replySuccessMessage = newValue } }

    private var replyTargetBinding: Binding<ThreadReplyTarget> { Binding(get: { actionState.replyTarget }, set: { actionState.replyTarget = $0 }) }
    private var replyTextBinding: Binding<String> { Binding(get: { actionState.replyText }, set: { actionState.replyText = $0 }) }
    private var replyAttachmentsBinding: Binding<[ReplyComposerAttachment]> { Binding(get: { actionState.replyAttachments }, set: { actionState.replyAttachments = $0 }) }
    private var showsReplyComposerBinding: Binding<Bool> { Binding(get: { actionState.showsReplyComposer }, set: { actionState.showsReplyComposer = $0 }) }

    var body: some View {
        let replyEntries = displayedReplyEntries

        GeometryReader { listGeometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Color.clear
                            .frame(height: 0)
                            .id(topAnchorID)

                        ThreadDetailHeaderSection(
                            thread: detailThread,
                            threadReplyTotalCount: threadReplyTotalCount,
                            activeInlineGIFPlaybackIDs: activeInlineGIFPlaybackIDs,
                            scrollTrackingSpaceName: scrollTrackingSpaceName
                        )
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ThreadDetailScrollOffsetPreferenceKey.self,
                                    value: proxy.frame(in: .named(scrollTrackingSpaceName)).minY
                                )
                            }
                        )

                        if isLoading {
                            ThreadDetailCard {
                                VStack(spacing: 10) {
                                    ProgressView()
                                        .tint(PaperTheme.mutedText)
                                    Text("正在加载回帖")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(PaperTheme.mutedText)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 10)
                            }
                        }

                        if let contentError {
                            ThreadDetailCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("错误")
                                        .font(.headline)
                                        .foregroundStyle(PaperTheme.ink)
                                    Text(contentError.userMessage)
                                        .foregroundStyle(PaperTheme.accent)
                                    if let recoverySuggestion = contentError.recoverySuggestion {
                                        Text(recoverySuggestion)
                                            .font(.footnote)
                                            .foregroundStyle(PaperTheme.mutedText)
                                    }
                                }
                            }
                        }

                        if !detailThread.replies.isEmpty {
                            ThreadDetailReplySection(
                                title: replySectionTitle,
                                entries: replyEntries,
                                showsOnlyThreadAuthor: showsOnlyThreadAuthor,
                                displayedRepliesAreEmpty: displayedReplies.isEmpty,
                                supportsReply: repository.capabilities.supportsReply,
                                supportsReplyTargeting: repository.capabilities.supportsReplyTargeting,
                                activeInlineGIFPlaybackIDs: activeInlineGIFPlaybackIDs,
                                scrollTrackingSpaceName: scrollTrackingSpaceName,
                                pageAnchorID: pageAnchorID(for:),
                                onReplyAppear: handleReplyEntryAppear(_:),
                                onReplyAction: { entry in
                                    replyTarget = replyTarget(for: entry)
                                    showsReplyComposer = true
                                },
                                onSnapshot: { entry in
                                    Task { await prepareSnapshot(scope: .singleReply(entry.reply)) }
                                },
                                onBlockUser: { username in
                                    blockedUsers.block(source: repository.source, username: username)
                                }
                            )
                        }

                        if hasMoreReplies, !isLoading, !supportsDirectPagination {
                            ThreadDetailCard {
                                Button {
                                    Task { await loadNextPage() }
                                } label: {
                                    HStack(spacing: 10) {
                                        if isLoadingMore {
                                            ProgressView()
                                                .tint(PaperTheme.mutedText)
                                        }
                                        Text(loadMoreTitle)
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(PaperTheme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                }
                                .disabled(isLoadingMore)
                                .onAppear {
                                    Task { await loadNextPage() }
                                }
                            }
                        } else if currentPage > 1, !isLoadingMore, !supportsDirectPagination {
                            ThreadDetailCard {
                                Text("已经加载全部回帖")
                                    .font(.footnote)
                                    .foregroundStyle(PaperTheme.mutedText)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }

                        if supportsDirectPagination, !isLoading {
                            if currentPage >= totalPageCount, totalPageCount > 1 {
                                ThreadDetailCard {
                                    Text("已经显示全部回帖")
                                        .font(.footnote)
                                        .foregroundStyle(PaperTheme.mutedText)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, supportsDirectPagination ? 28 : 96)
                }
                .accessibilityIdentifier("thread-detail-scroll")
                .background(PaperBackground())
                .coordinateSpace(name: scrollTrackingSpaceName)
                .navigationTitle("帖子详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .forumGlassNavigationBackground()
                .task {
                    await refreshDetail()
                }
                .onDisappear {
                    cancelContentLoad()
                }
                .refreshable {
                    await refreshDetail()
                }
                .safeAreaInset(edge: .bottom) {
                    ThreadDetailActionBar(
                        supportsReply: repository.capabilities.supportsReply,
                        isFavorited: favoriteThreads.contains(detailThread),
                        canFilterByAuthor: detailThread.author.isUsefulForumValue,
                        showsOnlyThreadAuthor: showsOnlyThreadAuthor,
                        isSubmittingReply: isSubmittingReply,
                        isUpdatingFavorite: isUpdatingFavorite,
                        isPreparingSnapshot: isPreparingSnapshot,
                        isLoading: isLoading,
                        showsRepliesInReverseOrder: showsRepliesInReverseOrder,
                        loadedSnapshotTitle: showsOnlyThreadAuthor ? "生成已加载楼主内容" : "生成已加载整贴",
                        onReply: {
                            replyTarget = .thread
                            showsReplyComposer = true
                        },
                        onToggleFavorite: {
                            Task { await toggleFavorite() }
                        },
                        onToggleAuthorFilter: toggleAuthorFilter,
                        onRefresh: {
                            Task { await refreshDetail() }
                        },
                        onToggleReplyOrder: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showsRepliesInReverseOrder.toggle()
                            }
                        },
                        onSnapshotMainPost: {
                            Task { await prepareSnapshot(scope: .mainPost) }
                        },
                        onSnapshotLoadedContent: {
                            Task { await prepareSnapshot(scope: .loadedContent) }
                        }
                    )
                }
                .overlay(alignment: .bottomTrailing) {
                    ThreadDetailFloatingControls(
                        showsScrollToTopControl: shouldShowScrollToTopControl,
                        supportsDirectPagination: supportsDirectPagination,
                        totalPageCount: totalPageCount,
                        isLoading: isLoading,
                        isLoadingMore: isLoadingMore,
                        visiblePage: visiblePage,
                        floatingControlTransition: floatingControlTransition,
                        floatingControlAnimation: floatingControlAnimation,
                        onScrollToTop: {
                            isReturningToTop = true
                            visiblePage = 1
                            pendingPageSelection = 1
                            scrollToTopRequestGeneration += 1
                        },
                        onNavigateToPreviousPage: {
                            Task { await navigateToAdjacentVisiblePage(-1, proxy: proxy) }
                        },
                        onNavigateToNextPage: {
                            Task { await navigateToAdjacentVisiblePage(1, proxy: proxy) }
                        },
                        onOpenPagePicker: {
                            pendingPageSelection = visiblePage
                            showsPagePicker = true
                        }
                    )
                    .zIndex(1)
                }
                .onAppear {
                    scrollViewportHeight = listGeometry.size.height
                    refreshDisplayedReplyCache()
                }
                .onChange(of: listGeometry.size.height) { _, height in
                    scrollViewportHeight = height
                }
                .onChange(of: detailThread.replies) { _, _ in
                    refreshDisplayedReplyCache()
                }
                .onChange(of: loadedPageStartReplyIndices) { _, _ in
                    refreshDisplayedReplyCache()
                }
                .onChange(of: showsOnlyThreadAuthor) { _, _ in
                    refreshDisplayedReplyCache()
                }
                .onChange(of: showsRepliesInReverseOrder) { _, _ in
                    refreshDisplayedReplyCache()
                }
                .onChange(of: blockedUsers.blockedUsers) { _, _ in
                    refreshDisplayedReplyCache()
                }
                .onPreferenceChange(ThreadDetailScrollOffsetPreferenceKey.self) { offset in
                    handleScrollOffsetChange(offset)
                }
                .onPreferenceChange(ThreadDetailPageAnchorOffsetPreferenceKey.self) { offsets in
                    handlePageAnchorOffsetsChange(offsets)
                }
                .onPreferenceChange(ThreadDetailGIFFramePreferenceKey.self) { candidates in
                    handleGIFFrameCandidatesChange(candidates)
                }
                .onChange(of: scrollToTopRequestGeneration) { _, generation in
                    Task { @MainActor in
                        await Task.yield()
                        guard generation == scrollToTopRequestGeneration else { return }
                        withAnimation(.snappy(duration: 0.28)) {
                            proxy.scrollTo(topAnchorID, anchor: .top)
                        }
                        try? await Task.sleep(for: .milliseconds(350))
                        guard generation == scrollToTopRequestGeneration else { return }
                        isReturningToTop = false
                    }
                }
                .onChange(of: deferredScrollTargetPage) { _, page in
                    guard let page else { return }
                    deferredScrollTargetPage = nil
                    scrollToPage(page, proxy: proxy)
                }
                .overlay {
                    if isPreparingSnapshot {
                        ZStack {
                            Color.black.opacity(0.16)
                                .ignoresSafeArea()
                            ProgressView("正在生成长图")
                                .padding(.horizontal, 22)
                                .padding(.vertical, 18)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showsSnapshotPreview, onDismiss: {
            snapshotImages = []
        }) {
            SnapshotPreviewSheet(images: snapshotImages)
        }
        .alert("长图生成失败", isPresented: snapshotErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(snapshotErrorMessage ?? "请稍后重试。")
        }
        .alert("收藏失败", isPresented: favoriteErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(favoriteErrorMessage ?? "请稍后重试。")
        }
        .alert("回复失败", isPresented: replyErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(replyErrorMessage ?? "请稍后重试。")
        }
        .alert("回复已发送", isPresented: replySuccessBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(replySuccessMessage ?? "帖子内容已刷新。")
        }
        .sheet(isPresented: showsReplyComposerBinding) {
            ReplyComposerSheet(
                source: repository.source,
                capabilities: repository.capabilities,
                target: replyTargetBinding,
                text: replyTextBinding,
                attachments: replyAttachmentsBinding,
                isSubmitting: isSubmittingReply,
                onCancel: {
                    showsReplyComposer = false
                    replyTarget = .thread
                },
                onSubmit: {
                    Task { await submitReply() }
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsPagePicker) {
            ThreadDetailPagePickerSheet(
                pendingPageSelection: pendingPageSelectionBinding,
                totalPageCount: totalPageCount,
                onJump: jumpToPageFromPicker(_:),
                onCancel: {
                    showsPagePicker = false
                }
            )
        }
    }

    private func handleScrollOffsetChange(_ offset: CGFloat) {
        let shouldShow = offset < -220
        lastObservedScrollOffset = offset

        if isReturningToTop, offset >= -24 {
            isReturningToTop = false
            visiblePage = 1
            pendingPageSelection = 1
        }

        if shouldShow != showsScrollToTopButton {
            withAnimation(.easeInOut(duration: 0.18)) {
                showsScrollToTopButton = shouldShow
            }
        }
    }

    private func handlePageAnchorOffsetsChange(_ offsets: [Int: CGFloat]) {
        guard supportsDirectPagination else { return }
        guard !isReturningToTop else { return }
        guard currentPage > 1 || !displayedReplies.isEmpty else {
            visiblePage = 1
            return
        }

        let threshold: CGFloat = 120
        let candidatePages = loadedPageStartReplyIndices.keys.sorted()
        let candidates = candidatePages.compactMap { page in
            offsets[page].map { (page, $0) }
        }
        guard !candidates.isEmpty else { return }

        let nextVisiblePage = candidates
            .filter { $0.1 <= threshold }
            .max { $0.0 < $1.0 }?.0
            ?? candidates
            .filter { $0.1 >= 0 }
            .min { $0.1 < $1.1 }?.0
            ?? 1

        guard nextVisiblePage != visiblePage else { return }
        visiblePage = nextVisiblePage
        if !showsPagePicker {
            pendingPageSelection = nextVisiblePage
        }
    }

    private func handleGIFFrameCandidatesChange(_ candidates: [ThreadDetailGIFFrameCandidate]) {
        let nextActiveIDs = inlineGIFPlaybackCoordinator.activePlaybackIDs(
            from: candidates,
            viewportHeight: scrollViewportHeight
        )

        guard nextActiveIDs != activeInlineGIFPlaybackIDs else { return }
        activeInlineGIFPlaybackIDs = nextActiveIDs
    }

    private func handleReplyEntryAppear(_ entry: ThreadDetailDisplayedReplyEntry) {
        guard supportsDirectPagination else { return }
        guard entry.loadsNextPageWhenAppearing else { return }

        guard currentPage < totalPageCount else { return }
        guard !isLoading, !isLoadingMore else { return }

        let targetPage = currentPage + 1
        guard lastAutoLoadedPage != targetPage else { return }

        lastAutoLoadedPage = targetPage
        Task {
            let didLoad = await loadSpecificPage(targetPage, proxy: nil, updatesPageSelection: false)
            if !didLoad {
                lastAutoLoadedPage = nil
            }
        }
    }

    private func navigateToAdjacentVisiblePage(_ delta: Int, proxy: ScrollViewProxy) async {
        guard supportsDirectPagination else { return }

        let targetPage = min(max(visiblePage + delta, 1), totalPageCount)
        guard targetPage != visiblePage else { return }

        await loadSpecificPage(
            targetPage,
            proxy: proxy,
            shouldScrollAfterLoad: true,
            updatesPageSelection: true
        )
    }

    private var displayedReplies: [Reply] {
        cachedDisplayedReplies
    }

    private func refreshDisplayedReplyCache() {
        cachedDisplayedReplies = ThreadDetailPresentationBuilder.displayedReplies(
            thread: detailThread,
            showsOnlyThreadAuthor: showsOnlyThreadAuthor,
            showsRepliesInReverseOrder: showsRepliesInReverseOrder,
            source: repository.source,
            isBlocked: { source, username in
                blockedUsers.isBlocked(source: source, username: username)
            }
        )
        cachedDisplayedReplyEntries = ThreadDetailPresentationBuilder.displayedReplyEntries(
            displayedReplies: cachedDisplayedReplies,
            allReplies: detailThread.replies,
            pageStartReplyIndices: loadedPageStartReplyIndices,
            supportsDirectPagination: supportsDirectPagination,
            pageSize: detailPageSize,
            prefetchReplyDistance: directPaginationPrefetchReplyDistance
        )
    }

    private var supportsDirectPagination: Bool {
        ThreadPaginationPolicy.supportsDirectPagination(for: repository.capabilities)
    }

    private var detailPageSize: Int {
        ThreadPaginationPolicy.pageSize(for: repository.capabilities) ?? 20
    }

    private var displayedReplyEntries: [ThreadDetailDisplayedReplyEntry] {
        cachedDisplayedReplyEntries
    }


    private var displayedAnchorPages: Set<Int> {
        Set(displayedReplyEntries.lazy.filter(\.showsPageAnchor).map(\.page))
    }

    private var totalPageCount: Int {
        ThreadPaginationPolicy.totalPageCount(
            replyCount: threadReplyTotalCount,
            fallbackReplyCount: thread.replyCount,
            capabilities: repository.capabilities
        )
    }

    private var replySectionTitle: String {
        showsOnlyThreadAuthor
            ? "楼主回帖 · \(displayedReplies.count)"
            : "回帖 · \(detailThread.replies.count)"
    }

    private var loadMoreTitle: String {
        if isLoadingMore {
            return showsOnlyThreadAuthor ? "正在查找楼主回复" : "正在加载后续回帖"
        }
        return showsOnlyThreadAuthor ? "继续查找楼主回复" : "加载更多回帖"
    }

    private var snapshotErrorBinding: Binding<Bool> {
        Binding(
            get: { snapshotErrorMessage != nil },
            set: { if !$0 { snapshotErrorMessage = nil } }
        )
    }

    private var favoriteErrorBinding: Binding<Bool> {
        Binding(
            get: { favoriteErrorMessage != nil },
            set: { if !$0 { favoriteErrorMessage = nil } }
        )
    }

    private var replyErrorBinding: Binding<Bool> {
        Binding(
            get: { replyErrorMessage != nil },
            set: { if !$0 { replyErrorMessage = nil } }
        )
    }

    private var replySuccessBinding: Binding<Bool> {
        Binding(
            get: { replySuccessMessage != nil },
            set: { if !$0 { replySuccessMessage = nil } }
        )
    }

    private func prepareSnapshot(scope: ThreadSnapshotScope) async {
        guard !isPreparingSnapshot else { return }

        isPreparingSnapshot = true
        snapshotErrorMessage = nil
        defer { isPreparingSnapshot = false }

        do {
            snapshotImages = try await ThreadSnapshotRenderer.render(
                thread: detailThread,
                replies: displayedReplies,
                scope: scope
            )
            showsSnapshotPreview = true
        } catch {
            snapshotErrorMessage = userFacingMessage(for: error)
        }
    }

    @discardableResult
    private func startContentLoad(
        _ operation: @escaping @MainActor (Int) async -> Bool
    ) async -> Bool {
        await contentLoadController.start(operation)
    }

    private func cancelContentLoad() {
        contentLoadController.cancel()
    }

    private func isCurrentContentLoad(_ generation: Int) -> Bool {
        contentLoadController.isCurrent(generation)
    }

    private func refreshDetail() async {
        _ = await detailViewModel.refresh(thread: thread, repository: repository)
    }

    @discardableResult
    private func loadSpecificPage(
        _ page: Int,
        proxy: ScrollViewProxy?,
        shouldScrollAfterLoad: Bool = false,
        updatesPageSelection: Bool = true
    ) async -> Bool {
        guard supportsDirectPagination else { return false }
        let targetPage = min(max(page, 1), totalPageCount)
        guard !isLoading else { return false }

        if targetPage <= currentPage {
            visiblePage = targetPage
            if updatesPageSelection {
                pendingPageSelection = targetPage
            }
            if let proxy {
                scrollToPage(targetPage, proxy: proxy)
            } else if shouldScrollAfterLoad {
                deferredScrollTargetPage = targetPage
            }
            return true
        }

        let didLoad = await detailViewModel.loadThroughPage(targetPage, thread: thread, repository: repository)
        guard didLoad else { return false }
        if updatesPageSelection { pendingPageSelection = targetPage }
        if let proxy { visiblePage = targetPage; scrollToPage(targetPage, proxy: proxy) }
        else if shouldScrollAfterLoad { visiblePage = targetPage; deferredScrollTargetPage = targetPage }
        return true
    }

    private func loadNextPage() async {
        await detailViewModel.loadNextPage(
            thread: thread,
            repository: repository,
            showsOnlyAuthor: showsOnlyThreadAuthor
        )
    }

    private func shouldTryAnotherPage(
        loadedCount: Int,
        totalCount: Int,
        accumulatedCount: Int? = nil
    ) -> Bool {
        let accumulatedCount = accumulatedCount ?? loadedCount
        return loadedCount >= 20 || accumulatedCount < totalCount
    }

    private func toggleFavorite() async {
        _ = await detailViewModel.toggleFavorite(
            thread: detailThread,
            repository: repository,
            favoriteThreads: favoriteThreads
        )
    }

    private func resolvedPage(
        forReplyIndex replyIndex: Int?,
        sortedPageStarts: [(key: Int, value: Int)]
    ) -> Int {
        guard let replyIndex else { return 1 }

        var resolvedPage = 1
        for (page, startIndex) in sortedPageStarts where startIndex <= replyIndex {
            resolvedPage = page
        }
        return resolvedPage
    }

    private func resolvedFloorLabel(
        replyIndex: Int?,
        page: Int,
        floorNumber: Int?
    ) -> String {
        if let floorNumber, floorNumber > 0 {
            return "\(floorNumber)楼"
        }

        if let replyIndex {
            if supportsDirectPagination {
                let pageStartIndex = loadedPageStartReplyIndices[page] ?? 0
                if page == 1 {
                    return "\(replyIndex + 2)楼"
                }
                return "\(((page - 1) * detailPageSize) + (replyIndex - pageStartIndex) + 1)楼"
            }

            return "\(replyIndex + 2)楼"
        }
        return "--楼"
    }

    private func toggleAuthorFilter() {
        let enablesOnlyAuthor = !showsOnlyThreadAuthor
        withAnimation(.easeInOut(duration: 0.2)) {
            showsOnlyThreadAuthor.toggle()
        }
        visiblePage = min(visiblePage, currentPage)
        if enablesOnlyAuthor, hasMoreReplies, !supportsDirectPagination {
            Task { await loadNextPage() }
        }
    }

    private func submitReply() async {
        await detailViewModel.submitReply(
            thread: detailThread,
            repository: repository,
            refreshDetail: { await refreshDetail() }
        )
    }

    private func userFacingMessage(for error: any Error) -> String {
        ForumError.resolve(error)?.userMessage ?? "操作未完成，请稍后重试。"
    }

}

private extension ThreadDetailView {
    func replyTarget(for entry: ThreadDetailDisplayedReplyEntry) -> ThreadReplyTarget {
        .reply(
            ThreadReplyTargetReply(
                replyID: entry.reply.id,
                sourcePostID: entry.reply.sourcePostID,
                floorNumber: entry.reply.floorNumber,
                displayFloorLabel: entry.floorLabel,
                author: entry.reply.author,
                createdAt: entry.reply.createdAt,
                bodyPreview: entry.reply.body
            )
        )
    }

    func pageAnchorID(for page: Int) -> String {
        page == 1 ? replyTopAnchorID : "thread-detail-page-\(page)"
    }

    func scrollToPage(_ page: Int, proxy: ScrollViewProxy) {
        let targetPage = resolvedScrollTargetPage(for: page)
        withAnimation(.snappy(duration: 0.28)) {
            proxy.scrollTo(pageAnchorID(for: targetPage), anchor: .top)
        }
    }

    func resolvedScrollTargetPage(for page: Int) -> Int {
        for candidate in stride(from: page, through: 1, by: -1) {
            if candidate == 1 || displayedAnchorPages.contains(candidate) {
                return candidate
            }
        }
        return 1
    }

    var floatingControlTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: 18, y: 6)
                .combined(with: .scale(scale: 0.94, anchor: .trailing))
                .combined(with: .opacity),
            removal: .offset(x: 14, y: 4)
                .combined(with: .scale(scale: 0.96, anchor: .trailing))
                .combined(with: .opacity)
        )
    }

    var floatingControlAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.84, blendDuration: 0.12)
    }

    var shouldShowScrollToTopControl: Bool {
        showsScrollToTopButton || visiblePage > 1
    }

    func jumpToPageFromPicker(_ page: Int) {
        pendingPageSelection = page
        showsPagePicker = false
        Task {
            await loadSpecificPage(page, proxy: nil, shouldScrollAfterLoad: true)
        }
    }

}

enum ThreadDetailPaginationPolicy {
    static let maximumAutomaticPageScan = 5

    static func shouldContinueAutomaticLoading(
        showsOnlyAuthor: Bool,
        authorReplyCountBeforeLoad: Int,
        authorReplyCountAfterLoad: Int,
        hasMoreReplies: Bool,
        scannedPageCount: Int
    ) -> Bool {
        showsOnlyAuthor
            && hasMoreReplies
            && authorReplyCountAfterLoad == authorReplyCountBeforeLoad
            && scannedPageCount < maximumAutomaticPageScan
    }
}

private struct SnapshotPreviewSheet: View {
    let images: [UIImage]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0
    @State private var showsShareSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if images.isEmpty {
                    ContentUnavailableView(
                        "暂无可预览图片",
                        systemImage: "photo",
                        description: Text("请返回后重试。")
                    )
                } else {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            GeometryReader { proxy in
                                ScrollView([.horizontal, .vertical]) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: proxy.size.width, alignment: .center)
                                        .frame(minHeight: proxy.size.height)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.92))
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
                    .background(Color.black.opacity(0.92))
                }
            }
            .navigationTitle(images.count > 1 ? "\(selectedIndex + 1) / \(images.count)" : "截图预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !images.isEmpty {
                        Button("分享") {
                            showsShareSheet = true
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsShareSheet) {
            ActivityShareView(activityItems: images)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct ThreadDetailScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ThreadDetailPageAnchorOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [1: 0]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
