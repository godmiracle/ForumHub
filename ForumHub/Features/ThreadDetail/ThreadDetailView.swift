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
    @State private var errorMessage: String?
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

                        threadDetailCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(detailThread.title)
                                    .font(.system(size: 25, weight: .bold, design: .serif))
                                    .foregroundStyle(PaperTheme.ink)

                                HStack(alignment: .center, spacing: 12) {
                                    AvatarView(name: detailThread.author, imageURL: detailThread.authorAvatarURL, size: 52)

                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            TagChip(title: "1楼")
                                            TagChip(title: detailThread.author)
                                            TagChip(title: "\(threadReplyTotalCount) 回复")
                                            TagChip(title: "\(detailThread.viewCount) 浏览")
                                        }

                                        if detailThread.createdAt.isUsefulForumValue {
                                            Text(detailThread.createdAt)
                                                .font(.caption)
                                                .foregroundStyle(PaperTheme.mutedText)
                                        }
                                    }
                                }

                                ForumRichContentView(
                                    text: detailThread.body,
                                    fontSize: 18,
                                    activeGIFPlaybackImageIDs: activeInlineGIFPlaybackIDs,
                                    scrollTrackingSpaceName: scrollTrackingSpaceName
                                )
                            }
                            .padding(.vertical, 8)
                        }

                        if isLoading {
                            threadDetailCard {
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

                        if let errorMessage {
                            threadDetailCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("错误")
                                        .font(.headline)
                                        .foregroundStyle(PaperTheme.ink)
                                    Text(errorMessage)
                                        .foregroundStyle(PaperTheme.accent)
                                }
                            }
                        }

                        if !detailThread.replies.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(replySectionTitle)
                                    .font(.system(size: 18, weight: .semibold, design: .serif))
                                    .foregroundStyle(PaperTheme.ink)
                                    .padding(.horizontal, 4)

                                Color.clear
                                    .frame(height: 1)
                                    .id(replyTopAnchorID)

                                if displayedReplies.isEmpty, showsOnlyThreadAuthor {
                                    threadDetailCard {
                                        VStack(spacing: 10) {
                                            Image(systemName: "person.crop.circle.badge.questionmark")
                                                .font(.system(size: 28))
                                            Text("楼主暂时没有继续回复")
                                                .font(.headline)
                                            Text("点击下方“查看全部”恢复所有回帖。")
                                                .font(.footnote)
                                        }
                                        .foregroundStyle(PaperTheme.mutedText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 28)
                                    }
                                }

                                ForEach(replyEntries) { entry in
                                    if entry.showsPageAnchor {
                                        Color.clear
                                            .frame(height: 1)
                                            .id(pageAnchorID(for: entry.page))
                                            .background(
                                                GeometryReader { anchorProxy in
                                                    Color.clear.preference(
                                                        key: ThreadDetailPageAnchorOffsetPreferenceKey.self,
                                                        value: [entry.page: anchorProxy.frame(in: .named(scrollTrackingSpaceName)).minY]
                                                    )
                                                }
                                            )
                                    }

                                    threadDetailCard {
                                        HStack(alignment: .top, spacing: 12) {
                                            AvatarView(name: entry.reply.author, imageURL: entry.reply.avatarURL, size: 40)

                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack {
                                                    Text(entry.reply.author)
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundStyle(PaperTheme.ink)
                                                    Spacer()
                                                    Text(entry.floorLabel)
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(PaperTheme.secondaryInk)
                                                    Text(entry.reply.createdAt)
                                                        .font(.caption)
                                                        .foregroundStyle(PaperTheme.mutedText)
                                                    replyTargetMenu(for: entry)
                                                }

                                                ForumRichContentView(
                                                    text: entry.reply.body,
                                                    fontSize: 17,
                                                    activeGIFPlaybackImageIDs: activeInlineGIFPlaybackIDs,
                                                    scrollTrackingSpaceName: scrollTrackingSpaceName
                                                )
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .onAppear {
                                        handleReplyEntryAppear(entry)
                                    }
                                }
                            }
                        }

                        if hasMoreReplies, !isLoading, !supportsDirectPagination {
                            threadDetailCard {
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
                            threadDetailCard {
                                Text("已经加载全部回帖")
                                    .font(.footnote)
                                    .foregroundStyle(PaperTheme.mutedText)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }

                        if supportsDirectPagination, !isLoading {
                            if currentPage >= totalPageCount, totalPageCount > 1 {
                                threadDetailCard {
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
                .toolbarBackground(.regularMaterial, for: .navigationBar)
                .task {
                    await refreshDetail()
                }
                .refreshable {
                    await refreshDetail()
                }
                .safeAreaInset(edge: .bottom) {
                    threadActionBar
                }
                .overlay(alignment: .bottomTrailing) {
                    trailingFloatingControls(proxy: proxy)
                }
                .onAppear {
                    scrollViewportHeight = listGeometry.size.height
                }
                .onChange(of: listGeometry.size.height) { _, height in
                    scrollViewportHeight = height
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
            pagePickerSheet
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
        let replies = showsOnlyThreadAuthor ? detailThread.authorReplies : detailThread.replies
        let visibleReplies = replies.filter { reply in
            !blockedUsers.isBlocked(source: repository.source, username: reply.author)
        }
        return showsRepliesInReverseOrder ? Array(visibleReplies.reversed()) : visibleReplies
    }

    private var replyScrollTargetID: String {
        displayedReplies.isEmpty ? topAnchorID : replyTopAnchorID
    }

    private var supportsDirectPagination: Bool {
        repository.source == .nga
    }

    private var displayedReplyEntries: [ThreadDetailDisplayedReplyEntry] {
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

    private func threadDetailCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var threadActionBar: some View {
        let isFavorited = favoriteThreads.contains(detailThread)
        let canFilterByAuthor = detailThread.author.isUsefulForumValue
        let loadedSnapshotTitle = showsOnlyThreadAuthor ? "生成已加载楼主内容" : "生成已加载整贴"

        return HStack {
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                if repository.capabilities.supportsReply {
                    ThreadActionButton(
                        title: "回复",
                        systemImage: "square.and.pencil",
                        isProminent: true,
                        isDisabled: isSubmittingReply,
                        action: {
                            replyTarget = .thread
                            showsReplyComposer = true
                        }
                    )
                }

                ThreadActionButton(
                    title: isFavorited ? "已收藏" : "收藏",
                    systemImage: isFavorited ? "star.fill" : "star",
                    isActive: isFavorited,
                    isDisabled: isUpdatingFavorite,
                    action: { Task { await toggleFavorite() } }
                )

                ThreadActionButton(
                    title: showsOnlyThreadAuthor ? "查看全部" : "只看楼主",
                    systemImage: showsOnlyThreadAuthor ? "person.2" : "person.crop.circle.badge.checkmark",
                    isActive: showsOnlyThreadAuthor,
                    isDisabled: !canFilterByAuthor,
                    action: { toggleAuthorFilter() }
                )

                Menu {
                    Button {
                        Task { await refreshDetail() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsRepliesInReverseOrder.toggle()
                        }
                    } label: {
                        Label(
                            showsRepliesInReverseOrder ? "恢复正序" : "倒叙排列",
                            systemImage: showsRepliesInReverseOrder ? "arrow.down.to.line" : "arrow.up.arrow.down"
                        )
                    }

                    Button {
                        Task { await prepareSnapshot(scope: .mainPost) }
                    } label: {
                        Label("截图此层", systemImage: "camera.viewfinder")
                    }

                    Button {
                        Task { await prepareSnapshot(scope: .loadedContent) }
                    } label: {
                        Label(loadedSnapshotTitle, systemImage: "rectangle.stack")
                    }
                } label: {
                    ThreadActionButtonLabel(
                        title: "更多",
                        systemImage: "ellipsis.circle",
                        isActive: false,
                        isProminent: false
                    )
                }
                .disabled(isPreparingSnapshot || isLoading)
                .accessibilityLabel("更多")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.18),
                                        Color.white.opacity(0.03)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
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
            snapshotErrorMessage = error.localizedDescription
        }
    }

    private func refreshDetail() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await repository.fetchThread(tid: thread.id, page: 1)
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
        } catch {
            errorMessage = error.localizedDescription
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
        guard !isLoading, !isLoadingMore else { return false }

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

        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }

        do {
            var workingThread = detailThread
            var workingCanonicalThread = canonicalThread ?? detailThread.mergingMetadataFallback(from: thread)
            var resolvedReplyTotal = threadReplyTotalCount
            var nextPageStarts = loadedPageStartReplyIndices

            for nextPage in (currentPage + 1)...targetPage {
                let result = try await repository.fetchThread(tid: thread.id, page: nextPage)
                resolvedReplyTotal = max(resolvedReplyTotal, thread.replyCount, result.thread.replyCount)

                if nextPage == 1 {
                    let mergedThread = result.thread.mergingMetadataFallback(from: thread)
                    workingThread = mergedThread
                    workingCanonicalThread = mergedThread
                    nextPageStarts = [1: 0]
                    continue
                }

                let pageReplies = normalizedContinuationReplies(from: result.thread.replies)
                let startIndex = workingThread.replies.count
                let appendedThread = workingThread.appendingReplies(pageReplies)
                workingThread = appendedThread.replacingReplies(
                    appendedThread.replies,
                    lastReplyAt: pageReplies.last?.createdAt ?? workingThread.lastReplyAt,
                    replyCount: resolvedReplyTotal
                )
                nextPageStarts[nextPage] = startIndex
            }

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
            lastAutoLoadedPage = nil
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func loadNextPage() async {
        guard hasMoreReplies, !isLoading, !isLoadingMore else { return }

        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }

        do {
            let authorReplyCountBeforeLoad = detailThread.authorReplies.count
            var scannedPageCount = 0

            repeat {
                let nextPage = currentPage + 1
                let result = try await repository.fetchThread(tid: thread.id, page: nextPage)
                let pageReplies = normalizedContinuationReplies(from: result.thread.replies)
                let existingIDs = Set(detailThread.replies.map(\.id))
                let existingSignatureKeys = Set(detailThread.replies.map(\.signatureKey))
                let newReplies = pageReplies.filter { reply in
                    !existingIDs.contains(reply.id) && !existingSignatureKeys.contains(reply.signatureKey)
                }
                scannedPageCount += 1

                guard !pageReplies.isEmpty, !newReplies.isEmpty else {
                    hasMoreReplies = false
                    break
                }

                detailThread = detailThread.appendingReplies(newReplies)
                currentPage = nextPage
                hasMoreReplies = shouldTryAnotherPage(
                    loadedCount: pageReplies.count,
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedContinuationReplies(from replies: [Reply]) -> [Reply] {
        replies.filter { reply in
            !isDuplicateOfMainPost(reply)
        }
    }

    private func isDuplicateOfMainPost(_ reply: Reply) -> Bool {
        let normalizedReplyAuthor = reply.author.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedThreadAuthor = detailThread.author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReplyAuthor.isEmpty,
              !normalizedThreadAuthor.isEmpty,
              normalizedReplyAuthor.compare(
                  normalizedThreadAuthor,
                  options: [.caseInsensitive, .diacriticInsensitive]
              ) == .orderedSame
        else {
            return false
        }

        let normalizedReplyBody = reply.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let normalizedMainBody = detailThread.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard !normalizedReplyBody.isEmpty, !normalizedMainBody.isEmpty else {
            return false
        }

        return normalizedReplyBody == normalizedMainBody
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
            favoriteErrorMessage = error.localizedDescription
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
            replyErrorMessage = error.localizedDescription
        }
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

private struct ThreadDetailDisplayedReplyEntry: Identifiable {
    let reply: Reply
    let page: Int
    let showsPageAnchor: Bool
    let floorLabel: String
    let loadsNextPageWhenAppearing: Bool

    var id: Int { reply.id }
}

private extension ThreadDetailView {
    @ViewBuilder
    func replyTargetMenu(for entry: ThreadDetailDisplayedReplyEntry) -> some View {
        Menu {
            if repository.capabilities.supportsReply
                && repository.capabilities.supportsReplyTargeting
                && entry.reply.sourcePostID != nil {
                Button {
                    replyTarget = replyTarget(for: entry)
                    showsReplyComposer = true
                } label: {
                    Label("回复本层", systemImage: "arrowshape.turn.up.left")
                }
            }

            Button {
                Task { await prepareSnapshot(scope: .singleReply(entry.reply)) }
            } label: {
                Label("截图此层", systemImage: "camera.viewfinder")
            }

            if entry.reply.author.isBlockableForumUsername {
                Button(role: .destructive) {
                    blockedUsers.block(source: repository.source, username: entry.reply.author)
                } label: {
                    Label("屏蔽该用户", systemImage: "person.crop.circle.badge.xmark")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PaperTheme.mutedText)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("楼层操作")
    }

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

    @ViewBuilder
    func trailingFloatingControls(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .trailing, spacing: 7) {
            if shouldShowScrollToTopControl {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsScrollToTopButton = false
                        visiblePage = 1
                        pendingPageSelection = 1
                    }
                    withAnimation(.snappy(duration: 0.28)) {
                        proxy.scrollTo(topAnchorID, anchor: .top)
                    }
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                        Text("TOP")
                            .font(.system(size: 7, weight: .heavy, design: .rounded))
                            .tracking(0.7)
                            .foregroundStyle(PaperTheme.mutedText)
                    }
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(1)
                    }
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
                    }
                    .overlay {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .padding(4)
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .transition(floatingControlTransition)
                .accessibilityLabel("回到顶部")
            }

            if supportsDirectPagination, totalPageCount > 1, !isLoading {
                detailFloatingPaginationControl(proxy: proxy)
                    .transition(floatingControlTransition)
            }
        }
        .padding(.trailing, 18)
        .padding(.bottom, 88)
        .animation(floatingControlAnimation, value: shouldShowScrollToTopControl)
        .animation(floatingControlAnimation, value: supportsDirectPagination && totalPageCount > 1 && !isLoading)
    }

    func detailFloatingPaginationControl(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            paginationIconButton(
                systemImage: "chevron.left",
                isDisabled: isLoadingMore || visiblePage <= 1
            ) {
                Task { await navigateToAdjacentVisiblePage(-1, proxy: proxy) }
            }

            Button {
                pendingPageSelection = visiblePage
                showsPagePicker = true
            } label: {
                VStack(spacing: 1) {
                    Text("\(visiblePage) / \(totalPageCount)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .accessibilityIdentifier("thread-detail-current-page")
                    Text("PAGE")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(PaperTheme.mutedText)
                }
                .foregroundStyle(PaperTheme.secondaryInk)
                .frame(minWidth: 74)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                }
            }
            .buttonStyle(.plain)

            paginationIconButton(
                systemImage: "chevron.right",
                isDisabled: isLoadingMore || visiblePage >= totalPageCount
            ) {
                Task { await navigateToAdjacentVisiblePage(1, proxy: proxy) }
            }
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(1)
                .allowsHitTesting(false)
        }
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .overlay {
            HStack {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 1, height: 18)
                    .padding(.leading, 38)
                Spacer()
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 1, height: 18)
                    .padding(.trailing, 38)
            }
            .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
    }

    func paginationIconButton(
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isDisabled ? PaperTheme.mutedText.opacity(0.7) : PaperTheme.secondaryInk)
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(Color.white.opacity(isDisabled ? 0.04 : 0.1))
                        .padding(3)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    var pagePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Capsule()
                        .fill(Color.white.opacity(0.34))
                        .frame(width: 40, height: 5)
                        .padding(.top, 4)

                    Text("第 \(pendingPageSelection) / \(totalPageCount) 页")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(PaperTheme.ink)

                    Text("滑动选择后可直接跳转，或快速前往首页与末页")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PaperTheme.mutedText)
                }
                .padding(.top, 8)
                .padding(.bottom, 2)

                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.92))
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.16),
                                            Color.white.opacity(0.04)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .padding(1)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                        }

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 44)
                        .padding(.horizontal, 14)

                    Picker("分页", selection: $pendingPageSelection) {
                        ForEach(1...totalPageCount, id: \.self) { page in
                            Text("\(page)").tag(page)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 176)
                    .clipped()
                    .padding(.horizontal, 8)
                }
                .frame(height: 196)

                HStack(spacing: 10) {
                    pagePickerActionButton(
                        title: "首页",
                        systemImage: "backward.end.fill"
                    ) {
                        jumpToPageFromPicker(1)
                    }

                    pagePickerActionButton(
                        title: "最后一页",
                        systemImage: "forward.end.fill"
                    ) {
                        jumpToPageFromPicker(totalPageCount)
                    }
                }

                HStack(spacing: 10) {
                    pagePickerActionButton(
                        title: "取消",
                        systemImage: "xmark",
                        style: .secondary
                    ) {
                        showsPagePicker = false
                    }

                    pagePickerActionButton(
                        title: "确定",
                        systemImage: "checkmark",
                        style: .primary
                    ) {
                        jumpToPageFromPicker(pendingPageSelection)
                    }
                }

                Text("首页与最后一页会直接跳转")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PaperTheme.mutedText.opacity(0.9))
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .background(PaperBackground())
        }
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.visible)
    }

    func jumpToPageFromPicker(_ page: Int) {
        pendingPageSelection = page
        showsPagePicker = false
        Task {
            await loadSpecificPage(page, proxy: nil, shouldScrollAfterLoad: true)
        }
    }

    func pagePickerActionButton(
        title: String,
        systemImage: String,
        style: PagePickerActionButtonStyle = .neutral,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: style == .primary ? .bold : .semibold))

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(pagePickerActionForegroundColor(for: style))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(pagePickerActionBackground(for: style), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(pagePickerActionBorderColor(for: style), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    func pagePickerActionBackground(for style: PagePickerActionButtonStyle) -> some ShapeStyle {
        switch style {
        case .primary:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        PaperTheme.accent.opacity(0.3),
                        PaperTheme.accent.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .secondary:
            return AnyShapeStyle(Color.white.opacity(0.08))
        case .neutral:
            return AnyShapeStyle(.ultraThinMaterial.opacity(0.72))
        }
    }

    func pagePickerActionBorderColor(for style: PagePickerActionButtonStyle) -> Color {
        switch style {
        case .primary:
            return PaperTheme.accent.opacity(0.38)
        case .secondary:
            return Color.white.opacity(0.14)
        case .neutral:
            return Color.white.opacity(0.2)
        }
    }

    func pagePickerActionForegroundColor(for style: PagePickerActionButtonStyle) -> Color {
        switch style {
        case .primary:
            return PaperTheme.accent
        case .secondary:
            return PaperTheme.mutedText
        case .neutral:
            return PaperTheme.secondaryInk
        }
    }
}

private enum PagePickerActionButtonStyle {
    case primary
    case secondary
    case neutral
}

private struct ThreadActionButton: View {
    let title: String
    let systemImage: String
    var isActive: Bool = false
    var isProminent: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ThreadActionButtonLabel(
                title: title,
                systemImage: systemImage,
                isActive: isActive,
                isProminent: isProminent
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

private struct ThreadActionButtonLabel: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let isProminent: Bool

    var body: some View {
        ZStack {
            backgroundCircle
            Circle()
                .stroke(borderColor, lineWidth: 0.8)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isProminent ? 0.16 : 0.2),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(1)

            Image(systemName: systemImage)
                .font(.system(size: isProminent ? 14 : 13, weight: .semibold))
                .foregroundColor(foregroundColor)
        }
        .frame(width: isProminent ? 36 : 32, height: isProminent ? 36 : 32)
        .shadow(color: shadowColor, radius: 8, y: 4)
    }

    private var foregroundColor: Color {
        if isProminent {
            return .white
        }
        if isActive {
            return PaperTheme.accent
        }
        return PaperTheme.secondaryInk
    }

    @ViewBuilder
    private var backgroundCircle: some View {
        if isProminent {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            PaperTheme.accent.opacity(0.9),
                            PaperTheme.accent.opacity(0.68)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else if isActive {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            PaperTheme.accent.opacity(0.22),
                            PaperTheme.accent.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            Circle()
                .fill(.ultraThinMaterial)
        }
    }

    private var borderColor: Color {
        if isProminent {
            return PaperTheme.accent.opacity(0.7)
        }
        if isActive {
            return PaperTheme.accent.opacity(0.22)
        }
        return Color.white.opacity(0.18)
    }

    private var shadowColor: Color {
        Color.black.opacity(isProminent ? 0.08 : 0.04)
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

private struct TagChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(PaperTheme.secondaryInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(PaperTheme.paperDeep.opacity(0.55), in: Capsule())
    }
}

private struct ThreadDetailScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ThreadDetailPageAnchorOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [1: 0]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
