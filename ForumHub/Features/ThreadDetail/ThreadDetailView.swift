import Foundation
import SwiftUI
import UIKit

struct ThreadDetailView: View {
    let thread: ForumThread
    let repository: any ThreadRepository
    @Bindable var blockedUsers: BlockedUsersStore
    @Bindable var favoriteThreads: FavoriteThreadsStore
    private let topAnchorID = "thread-detail-top-anchor"
    private let replyTopAnchorID = "thread-detail-reply-top-anchor"
    private let scrollTrackingSpaceName = "thread-detail-scroll"
    private let detailPageSize = 20
    private let directPaginationPrefetchReplyDistance = 6
    private let inlineGIFPlaybackViewportBuffer: CGFloat = 180
    private let maximumSimultaneousInlineGIFs = 3
    @State private var detailThread: ForumThread
    @State private var canonicalThread: ForumThread?
    @State private var threadReplyTotalCount: Int
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var contentError: ForumError?
    @State private var showsOnlyThreadAuthor = false
    @State private var showsRepliesInReverseOrder = false
    @State private var currentPage = 1
    @State private var hasMoreReplies = true
    @State private var isPreparingSnapshot = false
    @State private var snapshotImages: [UIImage] = []
    @State private var showsSnapshotPreview = false
    @State private var snapshotErrorMessage: String?
    @State private var favoriteErrorMessage: String?
    @State private var isUpdatingFavorite = false
    @State private var showsReplyComposer = false
    @State private var replyTarget: ThreadReplyTarget = .thread
    @State private var showsPagePicker = false
    @State private var replyText = ""
    @State private var replyAttachments: [ReplyComposerAttachment] = []
    @State private var isSubmittingReply = false
    @State private var replyErrorMessage: String?
    @State private var replySuccessMessage: String?
    @State private var showsScrollToTopButton = false
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var lastObservedScrollOffset: CGFloat = 0
    @State private var visiblePage = 1
    @State private var loadedPageStartReplyIndices: [Int: Int] = [1: 0]
    @State private var pendingPageSelection = 1
    @State private var deferredScrollTargetPage: Int?
    @State private var lastAutoLoadedPage: Int?
    @State private var activeInlineGIFPlaybackIDs: Set<UUID> = []
    @State private var contentLoadGeneration = 0
    @State private var contentLoadTask: Task<Bool, Never>?
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
        _detailThread = State(initialValue: thread)
        _threadReplyTotalCount = State(initialValue: thread.replyCount)
    }

    var body: some View {
        let replyEntries = displayedReplyEntries

        GeometryReader { listGeometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Color.clear
                            .frame(height: 1)
                            .id(topAnchorID)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: ThreadDetailScrollOffsetPreferenceKey.self,
                                        value: proxy.frame(in: .named(scrollTrackingSpaceName)).minY
                                    )
                                }
                            )

                        ThreadDetailHeaderSection(
                            thread: detailThread,
                            threadReplyTotalCount: threadReplyTotalCount,
                            activeInlineGIFPlaybackIDs: activeInlineGIFPlaybackIDs,
                            scrollTrackingSpaceName: scrollTrackingSpaceName
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
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showsScrollToTopButton = false
                                visiblePage = 1
                                pendingPageSelection = 1
                            }
                            withAnimation(.snappy(duration: 0.28)) {
                                proxy.scrollTo(topAnchorID, anchor: .top)
                            }
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
        .sheet(isPresented: $showsReplyComposer) {
            ReplyComposerSheet(
                source: repository.source,
                target: $replyTarget,
                text: $replyText,
                attachments: $replyAttachments,
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
                pendingPageSelection: $pendingPageSelection,
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

        if shouldShow != showsScrollToTopButton {
            withAnimation(.easeInOut(duration: 0.18)) {
                showsScrollToTopButton = shouldShow
            }
        }
    }

    private func handlePageAnchorOffsetsChange(_ offsets: [Int: CGFloat]) {
        guard supportsDirectPagination else { return }
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
        let viewportHeight = max(scrollViewportHeight, 1)
        let expandedTop = -inlineGIFPlaybackViewportBuffer
        let expandedBottom = viewportHeight + inlineGIFPlaybackViewportBuffer

        let nextActiveIDs = Set(
            candidates
                .filter { candidate in
                    candidate.frame.maxY >= expandedTop && candidate.frame.minY <= expandedBottom
                }
                .sorted { lhs, rhs in
                    abs(lhs.frame.midY - viewportHeight / 2) < abs(rhs.frame.midY - viewportHeight / 2)
                }
                .prefix(maximumSimultaneousInlineGIFs)
                .map(\.id)
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
        let replies = showsOnlyThreadAuthor ? detailThread.authorReplies : detailThread.replies
        let visibleReplies = replies.filter { reply in
            !blockedUsers.isBlocked(source: repository.source, username: reply.author)
        }
        let displayedReplies = showsRepliesInReverseOrder
            ? Array(visibleReplies.reversed())
            : visibleReplies

        cachedDisplayedReplies = displayedReplies
        cachedDisplayedReplyEntries = makeDisplayedReplyEntries(from: displayedReplies)
    }

    private var replyScrollTargetID: String {
        displayedReplies.isEmpty ? topAnchorID : replyTopAnchorID
    }

    private var supportsDirectPagination: Bool {
        repository.source == .nga
    }

    private var displayedReplyEntries: [ThreadDetailDisplayedReplyEntry] {
        cachedDisplayedReplyEntries
    }

    private func makeDisplayedReplyEntries(
        from displayedReplies: [Reply]
    ) -> [ThreadDetailDisplayedReplyEntry] {
        let sortedPageStarts = loadedPageStartReplyIndices.sorted { $0.value < $1.value }
        let replyIndices = Dictionary(uniqueKeysWithValues: detailThread.replies.enumerated().map { ($1.id, $0) })
        var firstVisibleReplyIDByPage: [Int: Int] = [:]

        let prefetchStartIndex = max(displayedReplies.count - directPaginationPrefetchReplyDistance, 0)

        return displayedReplies.enumerated().map { visualIndex, reply in
            let replyIndex = replyIndices[reply.id]
            let page = resolvedPage(forReplyIndex: replyIndex, sortedPageStarts: sortedPageStarts)
            let showsPageAnchor = firstVisibleReplyIDByPage[page] == nil
            if showsPageAnchor {
                firstVisibleReplyIDByPage[page] = reply.id
            }

            return ThreadDetailDisplayedReplyEntry(
                reply: reply,
                page: page,
                showsPageAnchor: showsPageAnchor,
                floorLabel: resolvedFloorLabel(replyIndex: replyIndex, page: page, floorNumber: reply.floorNumber),
                loadsNextPageWhenAppearing: visualIndex >= prefetchStartIndex
            )
        }
    }

    private var displayedAnchorPages: Set<Int> {
        Set(displayedReplyEntries.lazy.filter(\.showsPageAnchor).map(\.page))
    }

    private var totalPageCount: Int {
        let totalReplies = max(threadReplyTotalCount, thread.replyCount)
        let totalPosts = max(totalReplies + 1, 1)
        return max(1, Int(ceil(Double(totalPosts) / Double(detailPageSize))))
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
        cancelContentLoad()
        let generation = contentLoadGeneration
        let task = Task { @MainActor in
            await operation(generation)
        }
        contentLoadTask = task

        let didComplete = await task.value
        if contentLoadGeneration == generation {
            contentLoadTask = nil
        }
        return didComplete
    }

    private func cancelContentLoad() {
        contentLoadTask?.cancel()
        contentLoadTask = nil
        contentLoadGeneration &+= 1
    }

    private func isCurrentContentLoad(_ generation: Int) -> Bool {
        !Task.isCancelled && contentLoadGeneration == generation
    }

    private func refreshDetail() async {
        await startContentLoad { generation in
            await refreshDetail(generation: generation)
        }
    }

    private func refreshDetail(generation: Int) async -> Bool {
        guard isCurrentContentLoad(generation) else { return false }

        isLoading = true
        contentError = nil
        defer {
            if isCurrentContentLoad(generation) {
                isLoading = false
            }
        }

        do {
            let result = try await repository.fetchThread(tid: thread.id, page: 1)
            guard isCurrentContentLoad(generation) else { return false }

            let loadedThread = result.thread
            let mergedThread = loadedThread.mergingMetadataFallback(from: thread)
            let resolvedReplyTotal = max(threadReplyTotalCount, thread.replyCount, mergedThread.replyCount)
            detailThread = mergedThread
            canonicalThread = mergedThread
            threadReplyTotalCount = resolvedReplyTotal
            currentPage = 1
            visiblePage = 1
            loadedPageStartReplyIndices = [1: 0]
            pendingPageSelection = 1
            lastAutoLoadedPage = nil
            hasMoreReplies = supportsDirectPagination
                ? totalPageCount > 1
                : shouldTryAnotherPage(
                    loadedCount: loadedThread.replies.count,
                    totalCount: resolvedReplyTotal
                )
            return true
        } catch {
            guard isCurrentContentLoad(generation) else { return false }
            contentError = ForumError.resolve(error)
            return false
        }
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

        return await startContentLoad { generation in
            await loadSpecificPage(
                targetPage,
                generation: generation,
                proxy: proxy,
                shouldScrollAfterLoad: shouldScrollAfterLoad,
                updatesPageSelection: updatesPageSelection
            )
        }
    }

    private func loadSpecificPage(
        _ targetPage: Int,
        generation: Int,
        proxy: ScrollViewProxy?,
        shouldScrollAfterLoad: Bool,
        updatesPageSelection: Bool
    ) async -> Bool {
        guard isCurrentContentLoad(generation) else { return false }

        isLoadingMore = true
        contentError = nil
        defer {
            if isCurrentContentLoad(generation) {
                isLoadingMore = false
            }
        }

        do {
            var workingThread = detailThread
            var workingCanonicalThread = canonicalThread ?? detailThread.mergingMetadataFallback(from: thread)
            var resolvedReplyTotal = threadReplyTotalCount
            var nextPageStarts = loadedPageStartReplyIndices

            for nextPage in (currentPage + 1)...targetPage {
                guard isCurrentContentLoad(generation) else { return false }
                let result = try await repository.fetchThread(tid: thread.id, page: nextPage)
                guard isCurrentContentLoad(generation) else { return false }
                resolvedReplyTotal = max(resolvedReplyTotal, thread.replyCount, result.thread.replyCount)

                if nextPage == 1 {
                    let mergedThread = result.thread.mergingMetadataFallback(from: thread)
                    workingThread = mergedThread
                    workingCanonicalThread = mergedThread
                    nextPageStarts = [1: 0]
                    continue
                }

                let mergeResult = ThreadDetailPaginationMerger.merge(
                    currentThread: workingThread,
                    continuationThread: result.thread,
                    replyTotalCount: resolvedReplyTotal
                )
                workingThread = mergeResult.thread
                nextPageStarts[nextPage] = mergeResult.pageStartReplyIndex
            }

            guard isCurrentContentLoad(generation) else { return false }
            detailThread = workingThread.replacingReplies(
                workingThread.replies,
                lastReplyAt: workingThread.lastReplyAt,
                replyCount: resolvedReplyTotal
            )
            canonicalThread = workingCanonicalThread
            threadReplyTotalCount = resolvedReplyTotal
            currentPage = targetPage
            loadedPageStartReplyIndices = nextPageStarts
            if updatesPageSelection {
                pendingPageSelection = targetPage
            }
            hasMoreReplies = currentPage < totalPageCount

            if let proxy {
                visiblePage = targetPage
                scrollToPage(targetPage, proxy: proxy)
            } else if shouldScrollAfterLoad {
                visiblePage = targetPage
                deferredScrollTargetPage = targetPage
            }
            return true
        } catch {
            guard isCurrentContentLoad(generation) else { return false }
            lastAutoLoadedPage = nil
            contentError = ForumError.resolve(error)
            return false
        }
    }

    private func loadNextPage() async {
        guard hasMoreReplies, !isLoading, !isLoadingMore else { return }

        _ = await startContentLoad { generation in
            await loadNextPage(generation: generation)
        }
    }

    private func loadNextPage(generation: Int) async -> Bool {
        guard isCurrentContentLoad(generation) else { return false }

        isLoadingMore = true
        contentError = nil
        defer {
            if isCurrentContentLoad(generation) {
                isLoadingMore = false
            }
        }

        do {
            let authorReplyCountBeforeLoad = detailThread.authorReplies.count
            var scannedPageCount = 0

            repeat {
                guard isCurrentContentLoad(generation) else { return false }
                let nextPage = currentPage + 1
                let result = try await repository.fetchThread(tid: thread.id, page: nextPage)
                guard isCurrentContentLoad(generation) else { return false }
                let resolvedReplyTotal = max(threadReplyTotalCount, detailThread.replyCount, result.thread.replyCount)
                let mergeResult = ThreadDetailPaginationMerger.merge(
                    currentThread: detailThread,
                    continuationThread: result.thread,
                    replyTotalCount: resolvedReplyTotal
                )
                scannedPageCount += 1

                guard !mergeResult.continuationReplies.isEmpty, mergeResult.didAppendReplies else {
                    hasMoreReplies = false
                    break
                }

                detailThread = mergeResult.thread
                threadReplyTotalCount = resolvedReplyTotal
                currentPage = nextPage
                hasMoreReplies = shouldTryAnotherPage(
                    loadedCount: mergeResult.continuationReplies.count,
                    totalCount: detailThread.replyCount,
                    accumulatedCount: detailThread.replies.count
                )

                guard ThreadDetailPaginationPolicy.shouldContinueAutomaticLoading(
                    showsOnlyAuthor: showsOnlyThreadAuthor,
                    authorReplyCountBeforeLoad: authorReplyCountBeforeLoad,
                    authorReplyCountAfterLoad: detailThread.authorReplies.count,
                    hasMoreReplies: hasMoreReplies,
                    scannedPageCount: scannedPageCount
                ) else {
                    break
                }
            } while hasMoreReplies
            return true
        } catch {
            guard isCurrentContentLoad(generation) else { return false }
            contentError = ForumError.resolve(error)
            return false
        }
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
        guard !isUpdatingFavorite else { return }

        isUpdatingFavorite = true
        favoriteErrorMessage = nil
        defer { isUpdatingFavorite = false }

        do {
            if repository.capabilities.supportsFavorites {
                if favoriteThreads.contains(detailThread) {
                    try await repository.removeFavoriteThread(tid: detailThread.id)
                    favoriteThreads.remove(detailThread)
                } else {
                    try await repository.addFavoriteThread(tid: detailThread.id)
                    favoriteThreads.save(detailThread)
                }
                return
            }

            favoriteThreads.toggle(detailThread)
        } catch {
            favoriteErrorMessage = userFacingMessage(for: error)
        }
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
        guard !isSubmittingReply else { return }

        let trimmedReply = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReply.isEmpty else {
            replyErrorMessage = "回复内容不能为空。"
            return
        }

        if repository.source == .nga {
            let loginState = await NGAAuthStore.shared.currentLoginState()
            guard loginState.isLoggedIn else {
                replyErrorMessage = "登录 NGA 后才能发送回复。"
                return
            }
        }

        isSubmittingReply = true
        replyErrorMessage = nil
        defer { isSubmittingReply = false }

        do {
            let submittedTarget = replyTarget
            try await repository.replyThread(
                tid: detailThread.id,
                target: submittedTarget,
                content: trimmedReply,
                attachments: replyAttachments.map(\.upload)
            )
            replyText = ""
            replyAttachments = []
            showsReplyComposer = false
            replyTarget = .thread
            await refreshDetail()
            replySuccessMessage = successMessage(for: submittedTarget)
        } catch {
            replyErrorMessage = userFacingMessage(for: error)
        }
    }

    private func userFacingMessage(for error: any Error) -> String {
        ForumError.resolve(error)?.userMessage ?? "操作已取消。"
    }

    private func successMessage(for target: ThreadReplyTarget) -> String {
        switch target {
        case .thread:
            return "回复已发送，帖子内容已刷新。"
        case let .reply(targetReply):
            return "已回复 \(targetReply.displayFloorLabel)，帖子内容已刷新。"
        }
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
