import SwiftUI
import UIKit

enum ChannelPagingDirection {
    case previous
    case next
}

enum ChannelPagingPolicy {
    static func destination(
        currentKey: String,
        channels: [ForumChannel],
        direction: ChannelPagingDirection
    ) -> ForumChannel? {
        guard channels.count > 1 else { return nil }
        let currentIndex = channels.firstIndex(where: { $0.canonicalKey == currentKey }) ?? 0
        let offset = direction == .next ? 1 : -1
        let destinationIndex = (currentIndex + offset + channels.count) % channels.count
        return channels[destinationIndex]
    }

    static func isHorizontalIntent(_ translation: CGSize) -> Bool {
        abs(translation.width) > 12
            && abs(translation.width) > abs(translation.height) * 1.2
    }

    static func direction(for translation: CGSize) -> ChannelPagingDirection? {
        guard abs(translation.width) > 60,
              abs(translation.width) > abs(translation.height) * 1.35
        else { return nil }
        return translation.width < 0 ? .next : .previous
    }
}

enum FeedPaginationPolicy {
    static func shouldPrefetch(itemIndex: Int, itemCount: Int, canLoadMore: Bool) -> Bool {
        guard canLoadMore, itemCount > 0 else { return false }
        return itemIndex == max(itemCount - 3, 0)
    }
}

enum FeedSortMode: String, CaseIterable, Identifiable, Codable {
    case lastReply
    case latestPost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastReply:
            return "最后回复"
        case .latestPost:
            return "最新发帖"
        }
    }
}

struct FeedThreadTimePresentation: Equatable {
    let label: String
    let date: Date

    static func resolve(thread: ForumThread, sortMode: FeedSortMode) -> Self? {
        switch sortMode {
        case .lastReply:
            if let date = thread.lastReplyAtDate { return Self(label: "回复", date: date) }
            if let date = thread.createdAtDate { return Self(label: "发布", date: date) }
        case .latestPost:
            if let date = thread.createdAtDate { return Self(label: "发布", date: date) }
            if let date = thread.lastReplyAtDate { return Self(label: "回复", date: date) }
        }
        return nil
    }
}

struct ForumFeedContent: View {
    let tab: FeedTab
    let pinnedThreads: [ForumThread]
    let threads: [ForumThread]
    let repository: any ThreadRepository
    @Bindable var blockedUsers: BlockedUsersStore
    @Bindable var favoriteThreads: FavoriteThreadsStore
    let isLoading: Bool
    let hasLoadedInitialFeed: Bool
    let isLoadingMore: Bool
    let canLoadMore: Bool
    let errorMessage: String?
    var showsBrowserVerificationAction = false
    let scrollRequest: TabScrollRequest?
    let showsRetapRefreshIndicator: Bool
    let sortMode: FeedSortMode
    let filterState: FeedFilterState
    let childChannels: [AuthoritativeChildForum]
    let childForumStatus: FeedChildForumStatus
    let onSortChange: (FeedSortMode) -> Void
    let onFilterApply: (FeedFilterState) async -> Void
    let onFilterReset: () async -> Void
    let onNewChildForumsSeen: () -> Void
    let onCancelledChildForumNoticeDismiss: () -> Void
    let onRetryFailedChildForums: () async -> Void
    let onRefresh: () async -> Void
    let onLoadNextPage: () async -> Void
    var onBrowserVerificationRequested: () -> Void = {}
    var onOpenThread: (ForumThread) -> Void = { _ in }
    var onSwipeChannel: (ChannelPagingDirection) -> Void = { _ in }
    var onHeaderCollapseChange: (Bool) -> Void = { _ in }
    @State private var suppressesThreadNavigation = false
    @State private var tracksHorizontalSwipe = false
    @State private var suppressionGeneration = 0
    @State private var previousScrollOffset: CGFloat?
    private var topAnchorID: String { "feed-\(tab.rawValue)-top-anchor" }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: FeedScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("forum-feed-scroll")).minY
                        )
                    }
                    .frame(height: 1)
                    .id(topAnchorID)

                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            errorContent
                            pinnedContent
                            regularContent
                            Color.clear.frame(height: 112)
                        } header: {
                            FeedSortBar(
                                sortMode: sortMode,
                                filterState: filterState,
                                childChannels: childChannels,
                                childForumStatus: childForumStatus,
                                onSortChange: onSortChange,
                                onFilterApply: onFilterApply,
                                onNewChildForumsSeen: onNewChildForumsSeen
                            )
                        }
                    }
                }
                .refreshable { await onRefresh() }
                .scrollBounceBehavior(.always, axes: .vertical)
                .accessibilityIdentifier("forum-feed-\(tab.rawValue)-scroll")
                .coordinateSpace(name: "forum-feed-scroll")
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(channelPagingGesture)
                .onChange(of: scrollRequest) { _, request in
                    guard request?.targets(tab) == true else { return }
                    withAnimation(.snappy(duration: 0.28)) {
                        proxy.scrollTo(topAnchorID, anchor: .top)
                    }
                }
                .onPreferenceChange(FeedScrollOffsetPreferenceKey.self) { offset in
                    let upwardDelta = previousScrollOffset.map { offset - $0 } ?? 0
                    previousScrollOffset = offset
                    if offset > -8 || upwardDelta > 18 {
                        onHeaderCollapseChange(false)
                    } else if offset < -72 {
                        onHeaderCollapseChange(true)
                    }
                }
            }

            if showsRetapRefreshIndicator {
                RetapRefreshBanner()
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(.snappy(duration: 0.26), value: showsRetapRefreshIndicator)
    }

    private var channelPagingGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard ChannelPagingPolicy.isHorizontalIntent(value.translation),
                      !tracksHorizontalSwipe
                else { return }

                beginHorizontalSwipe()
            }
            .onEnded { value in
                if abs(value.translation.height) > abs(value.translation.width),
                   abs(value.translation.height) > 40 {
                    onHeaderCollapseChange(value.translation.height < 0)
                    return
                }
                endHorizontalSwipe(with: value.translation)
            }
    }

    private func beginHorizontalSwipe() {
        tracksHorizontalSwipe = true
        suppressesThreadNavigation = true
        suppressionGeneration += 1
    }

    private func endHorizontalSwipe(with translation: CGSize) {
        let generation = suppressionGeneration
        tracksHorizontalSwipe = false

        if let direction = ChannelPagingPolicy.direction(for: translation) {
            onSwipeChannel(direction)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard generation == suppressionGeneration else { return }
            suppressesThreadNavigation = false
        }
    }

    @ViewBuilder
    private var errorContent: some View {
        if errorMessage != nil
            || childForumStatus.cancelledSelectionNotice != nil
            || childForumStatus.partialFailureMessage != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                if showsBrowserVerificationAction {
                    Button("打开浏览器验证") {
                        onBrowserVerificationRequested()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.18, green: 0.48, blue: 0.38))
                    .accessibilityIdentifier("linuxdo-browser-verification-button")
                }
                if let notice = childForumStatus.cancelledSelectionNotice {
                    FeedStatusBanner(
                        message: notice,
                        actionTitle: "知道了",
                        action: onCancelledChildForumNoticeDismiss
                    )
                    .accessibilityIdentifier("feed-child-forum-cancelled-notice")
                }
                if let message = childForumStatus.partialFailureMessage {
                    FeedStatusBanner(
                        message: message,
                        actionTitle: "重试",
                        action: { Task { await onRetryFailedChildForums() } }
                    )
                    .accessibilityIdentifier("feed-child-forum-partial-failure")
                }
            }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var pinnedContent: some View {
        ForEach(blockedUsers.filtering(pinnedThreads)) { thread in
            BlockableThreadLink(
                thread: thread,
                badgeText: "置顶",
                repository: repository,
                blockedUsers: blockedUsers,
                favoriteThreads: favoriteThreads,
                sortMode: sortMode,
                navigationDisabled: suppressesThreadNavigation,
                onOpen: { onOpenThread(thread) }
            )
        }
    }

    @ViewBuilder
    private var regularContent: some View {
        if !threads.isEmpty {
            if visibleThreads.isEmpty {
                BlockedThreadsNotice()
                    .padding(.top, 56)
                    .padding(.bottom, 24)
            }

            ForEach(Array(visibleThreads.enumerated()), id: \.element.id) { index, thread in
                BlockableThreadLink(
                    thread: thread,
                    repository: repository,
                    blockedUsers: blockedUsers,
                    favoriteThreads: favoriteThreads,
                    sortMode: sortMode,
                    navigationDisabled: suppressesThreadNavigation,
                    onOpen: { onOpenThread(thread) }
                )
                .task(id: threads.count) {
                    if FeedPaginationPolicy.shouldPrefetch(
                        itemIndex: index,
                        itemCount: visibleThreads.count,
                        canLoadMore: canLoadMore
                    ), !isLoadingMore {
                        await onLoadNextPage()
                    }
                }
            }

            if canLoadMore {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(PaperTheme.mutedText)
                    Text("正在加载更多")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PaperTheme.mutedText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
        } else if !hasLoadedInitialFeed || isLoading {
            FeedLoadingView()
                .padding(.top, 80)
        } else if filterState.isActive {
            FilteredEmptyFeedView(activeCount: filterState.activeCount) {
                Task { await onFilterReset() }
            }
            .padding(.top, 64)
        } else {
            EmptyFeedView()
                .padding(.top, 80)
        }
    }

    private var visibleThreads: [ForumThread] {
        blockedUsers.filtering(threads)
    }
}

private struct FeedScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct RetapRefreshBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(PaperTheme.secondaryInk)
            Text("正在刷新内容")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PaperTheme.secondaryInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .forumGlass(in: Capsule(), isElevated: true)
    }
}

struct BlockableThreadLink: View {
    let thread: ForumThread
    var badgeText: String?
    let repository: any ThreadRepository
    @Bindable var blockedUsers: BlockedUsersStore
    @Bindable var favoriteThreads: FavoriteThreadsStore
    var sortMode: FeedSortMode = .lastReply
    var navigationDisabled = false
    var onOpen: () -> Void = {}
    @State private var favoriteErrorMessage: String?

    var body: some View {
        NavigationLink {
            ThreadDetailView(
                thread: thread,
                repository: repository,
                blockedUsers: blockedUsers,
                favoriteThreads: favoriteThreads
            )
        } label: {
            ThreadRow(
                thread: thread,
                badgeText: badgeText,
                isFavorited: favoriteThreads.contains(thread),
                sortMode: sortMode
            )
        }
        .accessibilityIdentifier("thread-row-\(thread.id)")
        .buttonStyle(.plain)
        .disabled(navigationDisabled)
        .simultaneousGesture(TapGesture().onEnded {
            if !navigationDisabled { onOpen() }
        })
        .contextMenu {
            if repository.capabilities.supportsFavorites {
                Button {
                    Task { await toggleFavorite() }
                } label: {
                    Label(
                        favoriteThreads.contains(thread) ? "取消收藏" : "收藏帖子",
                        systemImage: favoriteThreads.contains(thread) ? "star.slash" : "star"
                    )
                }
            }

            if thread.author.isUsefulForumValue, thread.author != "未知作者" {
                Button(role: .destructive) {
                    blockedUsers.block(source: thread.source, username: thread.author)
                } label: {
                    Label("屏蔽作者 \(thread.author)", systemImage: "person.crop.circle.badge.xmark")
                }
            }
        }
        .alert("收藏失败", isPresented: favoriteErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(favoriteErrorMessage ?? "请稍后重试。")
        }
    }

    private var favoriteErrorBinding: Binding<Bool> {
        Binding(
            get: { favoriteErrorMessage != nil },
            set: { if !$0 { favoriteErrorMessage = nil } }
        )
    }

    private func toggleFavorite() async {
        favoriteErrorMessage = nil

        do {
            guard repository.capabilities.supportsFavorites else { return }
            if favoriteThreads.contains(thread) {
                try await repository.removeFavoriteThread(tid: thread.id)
                favoriteThreads.remove(thread)
            } else {
                try await repository.addFavoriteThread(tid: thread.id)
                favoriteThreads.save(thread)
            }
        } catch {
            favoriteErrorMessage = error.localizedDescription
        }
    }
}

struct BlockedThreadsNotice: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 30))
            Text("当前页面的帖子已被屏蔽")
                .font(.headline)
            Text("可以继续加载下一页，或到“用户 → 我的屏蔽”解除。")
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(PaperTheme.mutedText)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

private struct FeedLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(PaperTheme.accent)

            Text("正在加载内容")
                .font(.system(.body, design: .serif, weight: .medium))
                .foregroundStyle(PaperTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在加载内容")
    }
}

struct ThreadRow: View {
    let thread: ForumThread
    var badgeText: String?
    var isFavorited = false
    var sortMode: FeedSortMode = .lastReply

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(name: thread.author, imageURL: thread.authorAvatarURL)

            VStack(alignment: .leading, spacing: 7) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        authorText
                        Spacer(minLength: 8)
                        timeText
                        replyCountText
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        authorText
                        HStack(spacing: 8) {
                            timeText
                            replyCountText
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    if let badgeText {
                        Text(badgeText)
                            .font(.caption.bold())
                            .foregroundStyle(PaperTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PaperTheme.accent.opacity(0.1), in: Capsule())
                    }

                    if let channelTitle = thread.channelTitle, !channelTitle.isEmpty {
                        Text(channelTitle)
                            .font(.caption.bold())
                            .foregroundStyle(Color(red: 0.27, green: 0.42, blue: 0.57))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.27, green: 0.42, blue: 0.57).opacity(0.1), in: Capsule())
                    }

                    if isFavorited {
                        Label("已收藏", systemImage: "star.fill")
                            .font(.caption.bold())
                            .foregroundStyle(PaperTheme.secondaryInk)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PaperTheme.paperDeep.opacity(0.72), in: Capsule())
                    }

                    Text(thread.title)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(PaperTheme.ink)
                        .multilineTextAlignment(.leading)

                    if !thread.summary.isEmpty, thread.summary != thread.title {
                        Text(thread.summary)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(PaperTheme.secondaryInk)
                            .lineLimit(3)
                            .lineSpacing(2)
                    }
                }

                if thread.viewCount > 0 {
                    Text("\(thread.viewCount) 浏览")
                        .font(.caption)
                        .foregroundStyle(PaperTheme.mutedText.opacity(0.76))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaperTheme.card)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PaperTheme.hairline)
                .frame(height: 0.7)
                .padding(.leading, 74)
        }
    }

    private var timePresentation: (label: String, date: Date)? {
        FeedThreadTimePresentation.resolve(thread: thread, sortMode: sortMode).map { ($0.label, $0.date) }
    }

    private var authorText: some View {
        Text(thread.author.isEmpty ? "未知作者" : thread.author)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(PaperTheme.mutedText)
    }

    @ViewBuilder
    private var timeText: some View {
        if let timePresentation {
            Text("\(timePresentation.label) \(ForumTime.feedText(timePresentation.date))")
                .font(.caption)
                .foregroundStyle(PaperTheme.mutedText.opacity(0.82))
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var replyCountText: some View {
        Text("\(thread.replyCount)回")
            .font(.caption.weight(.medium))
            .foregroundStyle(PaperTheme.secondaryInk)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct ForumTopBar: View {
    @Binding var selectedChannelKey: String
    let activeTab: FeedTab
    @State private var searchDraft = ""
    @FocusState private var isSearchFocused: Bool
    let selectedSource: ForumSource
    let availableSources: [ForumSource]
    let channels: [ForumChannel]
    let isLoading: Bool
    let isAuthenticated: Bool
    let isV2EXAuthenticated: Bool
    let linuxDoUsername: String?
    let capabilities: ForumCapabilities
    let canComposeInCurrentChannel: Bool
    let sessionState: SourceSessionState
    let isCollapsed: Bool
    let onSourceSelect: (ForumSource) -> Void
    let onCommunitySelect: () -> Void
    let onRefresh: () -> Void
    let onSearch: (String) -> Void
    let onChannelSelect: (ForumChannel) -> Void
    let onCompose: () -> Void
    let onLogin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isCollapsed {
                HStack(spacing: 8) {
                Menu {
                    Section("论坛来源") {
                        ForEach(availableSources) { source in
                            Button {
                                onSourceSelect(source)
                            } label: {
                                Label {
                                    HStack {
                                        Text(source.title)
                                        Spacer()
                                        if let status = sourceStatus(source) {
                                            Text(status)
                                                .foregroundStyle(PaperTheme.mutedText)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: selectedSource == source ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            onCommunitySelect()
                        } label: {
                            Label("管理当前来源栏目", systemImage: "slider.horizontal.3")
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(sourceTint(selectedSource))
                            .frame(width: 7, height: 7)
                        Text(selectedSource.title)
                            .font(.subheadline.bold())
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(PaperTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(minHeight: 44)
                    .background(PaperTheme.card, in: Capsule())
                    .overlay {
                        Capsule().stroke(sourceTint(selectedSource).opacity(0.48), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("current-community-button")
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !isCollapsed {
                HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PaperTheme.mutedText)
                    TextField(searchPlaceholder, text: $searchDraft)
                        .accessibilityIdentifier("forum-search-field")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            submitSearch()
                        }
                        .foregroundStyle(PaperTheme.ink)
                        .disabled(!capabilities.supportsSearch)
                    if !searchDraft.isEmpty {
                        Button {
                            searchDraft = ""
                            isSearchFocused = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(PaperTheme.mutedText.opacity(0.72))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索")
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完成") {
                            isSearchFocused = false
                        }
                    }
                }
                .font(.body)
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PaperTheme.hairline, lineWidth: 1)
                }

                Button(action: onRefresh) {
                    Group {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(PaperTheme.secondaryInk)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .frame(width: 44, height: 44)
                    .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(PaperTheme.hairline, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .accessibilityIdentifier("forum-refresh-button")
                .accessibilityLabel(isLoading ? "正在刷新版面" : "刷新版面")

                    if canComposeInCurrentChannel {
                        Button(action: onCompose) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(width: 44, height: 44)
                                .background(PaperTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: PaperTheme.accent.opacity(0.18), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("forum-compose-button")
                        .accessibilityLabel("发帖")
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !channels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(channels, id: \.canonicalKey) { channel in
                            Button {
                                onChannelSelect(channel)
                            } label: {
                                VStack(spacing: 4) {
                                    Text(channel.title)
                                        .font(.system(
                                            .body,
                                            design: .serif,
                                            weight: selectedChannelKey == channel.canonicalKey ? .bold : .medium
                                        ))
                                        .foregroundStyle(selectedChannelKey == channel.canonicalKey ? PaperTheme.accent : PaperTheme.mutedText)

                                    Capsule()
                                        .fill(selectedChannelKey == channel.canonicalKey ? PaperTheme.accent : .clear)
                                        .frame(width: 26, height: 3)
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("forum-channel-\(channel.canonicalKey)")
                            .accessibilityValue(selectedChannelKey == channel.canonicalKey ? "已选择" : "未选择")
                            .accessibilityAddTraits(selectedChannelKey == channel.canonicalKey ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }

            if sessionState == .signedOut || sessionState == .expired {
                HStack(spacing: 10) {
                    Text(sessionState == .expired ? "登录状态已失效" : "登录后可发帖和使用账号功能")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PaperTheme.mutedText)
                    Spacer(minLength: 8)
                    Button(sessionState == .expired ? "重新登录" : "登录", action: onLogin)
                        .font(.caption.bold())
                        .frame(minHeight: 44)
                        .buttonStyle(.borderedProminent)
                        .tint(PaperTheme.accent)
                        .accessibilityIdentifier("forum-session-action-button")
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background {
            LinearGradient(
                colors: [
                    PaperTheme.paper.opacity(0.98),
                    PaperTheme.paperDeep.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PaperTheme.hairline)
                .frame(height: 0.7)
        }
        .onChange(of: activeTab) { _, _ in
            isSearchFocused = false
        }
        .animation(.snappy(duration: 0.22), value: isCollapsed)
    }

    private func submitSearch() {
        let keyword = searchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard capabilities.supportsSearch, !keyword.isEmpty else { return }
        isSearchFocused = false
        onSearch(keyword)
    }

    private var searchPlaceholder: String {
        capabilities.supportsSearch
            ? "搜索 \(selectedSource.title)"
            : "\(selectedSource.title) 暂不支持全站搜索"
    }

    private func sourceStatus(_ source: ForumSource) -> String? {
        switch source {
        case .nga:
            return isAuthenticated ? nil : "需要登录"
        case .v2ex:
            return isV2EXAuthenticated ? nil : "可公开浏览"
        case .linuxDo:
            return linuxDoUsername == nil ? "可公开浏览" : nil
        }
    }

    private func sourceTint(_ source: ForumSource) -> Color {
        switch source {
        case .nga:
            return PaperTheme.accent
        case .v2ex:
            return Color(red: 0.27, green: 0.42, blue: 0.57)
        case .linuxDo:
            return Color(red: 0.18, green: 0.48, blue: 0.38)
        }
    }

}

private struct FeedSortBar: View {
    let sortMode: FeedSortMode
    let filterState: FeedFilterState
    let childChannels: [AuthoritativeChildForum]
    let childForumStatus: FeedChildForumStatus
    let onSortChange: (FeedSortMode) -> Void
    let onFilterApply: (FeedFilterState) async -> Void
    let onNewChildForumsSeen: () -> Void
    @State private var showsFilter = false
    @State private var draft = FeedFilterState()

    private var childPresentation: ChildForumFilterPresentation {
        ChildForumFilterPresentation(
            children: childChannels,
            selectedStableKeys: filterState.selectedChildForumKeys,
            pendingNewStableKeys: childForumStatus.pendingNewStableKeys,
            searchText: ""
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            sortButton(for: .lastReply)
            sortButton(for: .latestPost)

            Spacer(minLength: 8)

            Button {
                draft = filterState
                showsFilter = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 12, weight: .bold))
                    Text(filterState.activeCount == 0 ? "筛选" : "筛选 \(filterState.activeCount)")
                        .font(.subheadline.weight(.semibold))
                    if childPresentation.pendingNewCount > 0 {
                        Text("新")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(PaperTheme.accent.opacity(0.14), in: Capsule())
                    }
                }
                .foregroundStyle(filterState.isActive ? PaperTheme.accent : PaperTheme.secondaryInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(PaperTheme.card, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(filterState.isActive ? PaperTheme.accent.opacity(0.35) : PaperTheme.hairline, lineWidth: 0.9)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("feed-filter-button")
            .accessibilityLabel(filterButtonAccessibilityLabel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(PaperTheme.paper.opacity(0.78))
        .sheet(isPresented: $showsFilter, onDismiss: {
            if !childForumStatus.pendingNewStableKeys.isEmpty {
                onNewChildForumsSeen()
            }
        }) {
            FeedFilterSheet(
                draft: $draft,
                childChannels: childChannels,
                childForumStatus: childForumStatus,
                onApply: { appliedFilter in
                    await onFilterApply(appliedFilter)
                    showsFilter = false
                },
                onCancel: { showsFilter = false }
            )
        }
    }

    private var filterButtonAccessibilityLabel: String {
        var parts = [filterState.activeCount == 0 ? "筛选帖子" : "筛选帖子，已启用 \(filterState.activeCount) 项"]
        if childPresentation.pendingNewCount > 0 {
            parts.append("有 \(childPresentation.pendingNewCount) 个新子版")
        }
        return parts.joined(separator: "，")
    }

    private func sortButton(for mode: FeedSortMode) -> some View {
        let isSelected = sortMode == mode

        return Button {
            onSortChange(mode)
        } label: {
            Text(mode.title)
                .font(.subheadline.weight(isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? PaperTheme.accent : PaperTheme.secondaryInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(
                    isSelected ? PaperTheme.accent.opacity(0.14) : PaperTheme.card,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(isSelected ? PaperTheme.accent.opacity(0.35) : PaperTheme.hairline, lineWidth: 0.9)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("feed-sort-\(mode.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FeedFilterSheet: View {
    @Binding var draft: FeedFilterState
    let childChannels: [AuthoritativeChildForum]
    let childForumStatus: FeedChildForumStatus
    let onApply: (FeedFilterState) async -> Void
    let onCancel: () -> Void
    @State private var childSearchText = ""
    @State private var isApplying = false

    private var childPresentation: ChildForumFilterPresentation {
        ChildForumFilterPresentation(
            children: childChannels,
            selectedStableKeys: draft.selectedChildForumKeys,
            pendingNewStableKeys: childForumStatus.pendingNewStableKeys,
            searchText: childSearchText
        )
    }

    var body: some View {
        NavigationStack {
            searchableFilterForm
                .navigationTitle("筛选")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("应用") {
                            guard !isApplying else { return }
                            isApplying = true
                            let appliedFilter = draft
                            Task { await onApply(appliedFilter) }
                        }
                        .disabled(isApplying)
                        .accessibilityIdentifier("feed-filter-apply-button")
                    }
                }
        }
    }

    @ViewBuilder
    private var searchableFilterForm: some View {
        if childPresentation.needsSearch {
            filterForm.searchable(text: $childSearchText, prompt: "搜索子版名称或编号")
        } else {
            filterForm
        }
    }

    private var filterForm: some View {
        Form {
            if childForumStatus.isApplicable {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(PaperTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("网事杂谈主版")
                                .font(.body.weight(.semibold))
                            Text("主版始终包含")
                                .font(.footnote)
                                .foregroundStyle(PaperTheme.secondaryInk)
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("网事杂谈主版，始终包含")

                    Button("只看主版") {
                        draft.selectedChildForumKeys = []
                    }
                    .foregroundStyle(draft.selectedChildForumKeys.isEmpty ? PaperTheme.accent : PaperTheme.ink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityHint("清空所有子版草稿，应用后只加载主版")

                    if let message = childForumStatus.directoryUnavailableMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(PaperTheme.secondaryInk)
                            .accessibilityIdentifier("feed-child-forum-directory-unavailable")
                    } else if childChannels.isEmpty {
                        Text("暂无可选子版")
                            .font(.footnote)
                            .foregroundStyle(PaperTheme.secondaryInk)
                    } else if childPresentation.filteredChildren.isEmpty {
                        ContentUnavailableView.search(text: childSearchText)
                    } else {
                        ForEach(childPresentation.filteredChildren) { channel in
                            Toggle(isOn: childBinding(for: channel.stableKey)) {
                                HStack(spacing: 8) {
                                    Text(channel.title)
                                    if childPresentation.isNew(channel.stableKey) {
                                        Text("新")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(PaperTheme.accent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(PaperTheme.accent.opacity(0.12), in: Capsule())
                                    }
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                            .accessibilityLabel(childAccessibilityLabel(channel))
                            .accessibilityIdentifier("feed-child-forum-\(channel.stableKey)")
                        }
                    }
                } header: {
                    Text("子版（已选 \(childPresentation.selectedCount)）")
                } footer: {
                    Text("只显示网事杂谈权威目录中的真实直接子版。")
                }
            }

            Section("主题") {
                Toggle("显示置顶", isOn: $draft.showsPinnedThreads)
                    .accessibilityIdentifier("feed-filter-pinned-toggle")
            }

            Section {
                Button("重置筛选", role: .destructive) {
                    draft = FeedFilterState()
                }
                .accessibilityIdentifier("feed-filter-reset-button")
            }
        }
    }

    private func childAccessibilityLabel(_ child: AuthoritativeChildForum) -> String {
        childPresentation.isNew(child.stableKey) ? "\(child.title)，新子版" : child.title
    }

    private func childBinding(for stableKey: String) -> Binding<Bool> {
        Binding(
            get: { draft.selectedChildForumKeys.contains(stableKey) },
            set: { isSelected in
                if isSelected {
                    draft.selectedChildForumKeys.insert(stableKey)
                } else {
                    draft.selectedChildForumKeys.remove(stableKey)
                }
            }
        )
    }
}

struct AvatarView: View {
    let name: String
    let imageURL: URL?
    let size: CGFloat
    @State private var image: UIImage?

    init(name: String, imageURL: URL? = nil, size: CGFloat = 48) {
        self.name = name
        self.imageURL = imageURL
        self.size = size
    }

    var body: some View {
        ZStack {
            avatarBackground

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(PaperTheme.hairline, lineWidth: 1)
        }
        .accessibilityHidden(true)
        .task(id: imageURL) {
            guard let imageURL else {
                image = nil
                return
            }
            image = try? await NGAImageLoader.load(url: imageURL)
        }
    }

    private var avatarBackground: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.58, green: 0.53, blue: 0.43),
                        Color(red: 0.33, green: 0.28, blue: 0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var placeholder: some View {
        Text(initial)
            .font(.system(size: max(14, size * 0.38), weight: .bold))
            .foregroundStyle(Color(red: 0.98, green: 0.94, blue: 0.84))
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "N"
    }
}

enum FeedTab: String, CaseIterable, Identifiable {
    case home
    case hot
    case community
    case history
    case user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "首页"
        case .hot:
            return "热门"
        case .community:
            return "栏目"
        case .history:
            return "足迹"
        case .user:
            return "用户"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house.fill"
        case .hot:
            return "flame"
        case .community:
            return "rectangle.3.group"
        case .history:
            return "clock.arrow.circlepath"
        case .user:
            return "person"
        }
    }
}

struct ForumBottomBar: View {
    @Binding var selectedTab: FeedTab
    let onSelect: (FeedTab, Bool) -> Void
    @Namespace private var glassNamespace
    @State private var scrubbedTab: FeedTab?
    @State private var selectionPulse = 0
    @State private var reselectionPulse = 0

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            nativeGlassBar
        } else {
            materialFallbackBar
        }
    }

    @available(iOS 26.0, *)
    private var nativeGlassBar: some View {
        GlassEffectContainer(spacing: 10) {
            GeometryReader { geometry in
                HStack(spacing: 6) {
                    ForEach(FeedTab.allCases) { tab in
                        nativeGlassButton(for: tab)
                    }
                }
                .padding(8)
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
                .simultaneousGesture(scrubGesture(width: geometry.size.width))
            }
            .frame(maxWidth: 390)
            .frame(height: 70)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .sensoryFeedback(.selection, trigger: selectionPulse)
        .sensoryFeedback(.success, trigger: reselectionPulse)
    }

    @available(iOS 26.0, *)
    private func nativeGlassButton(for tab: FeedTab) -> some View {
        let isSelected = tab == displayedTab

        return Button {
            commitSelection(tab)
        } label: {
            tabLabel(tab, isSelected: isSelected, animationValue: selectionPulse)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.clear)
                            .glassEffect(
                                .regular
                                    .tint(PaperTheme.accent.opacity(0.16))
                                    .interactive(),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .glassEffectID("selected-tab", in: glassNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var materialFallbackBar: some View {
        HStack(spacing: 6) {
            ForEach(FeedTab.allCases) { tab in
                let isSelected = tab == selectedTab

                Button {
                    commitSelection(tab)
                } label: {
                    tabLabel(tab, isSelected: isSelected, animationValue: selectionPulse)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(PaperTheme.hairline, lineWidth: 0.8)
                                }
                                .shadow(color: PaperTheme.ink.opacity(0.14), radius: 12, x: 0, y: 8)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }
        .padding(8)
        .frame(maxWidth: 390)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    PaperTheme.ink.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                }
                .shadow(color: PaperTheme.ink.opacity(0.2), radius: 22, x: 0, y: 14)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .sensoryFeedback(.selection, trigger: selectionPulse)
        .sensoryFeedback(.success, trigger: reselectionPulse)
    }

    private var displayedTab: FeedTab {
        scrubbedTab ?? selectedTab
    }

    private func tabLabel(_ tab: FeedTab, isSelected: Bool, animationValue: Int) -> some View {
        VStack(spacing: 4) {
            Image(systemName: tab.systemImage)
                .font(.system(size: isSelected ? 22 : 20, weight: .semibold))
                .symbolEffect(.bounce, value: isSelected ? animationValue : 0)
            Text(tab.title)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(isSelected ? PaperTheme.accent : PaperTheme.mutedText)
        .scaleEffect(isSelected ? 1.04 : 1)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.3), value: isSelected)
    }

    private func commitSelection(_ tab: FeedTab) {
        let isReselection = tab == selectedTab

        withAnimation(.snappy(duration: 0.34, extraBounce: 0.08)) {
            scrubbedTab = nil
            selectedTab = tab
            selectionPulse += 1
            if isReselection {
                reselectionPulse += 1
            }
        }

        onSelect(tab, isReselection)
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                let tab = tab(at: value.location.x, width: width)
                guard tab != scrubbedTab else { return }

                withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) {
                    scrubbedTab = tab
                    selectionPulse += 1
                }
            }
            .onEnded { value in
                commitSelection(tab(at: value.location.x, width: width))
            }
    }

    private func tab(at xPosition: CGFloat, width: CGFloat) -> FeedTab {
        let tabs = FeedTab.allCases
        let safeWidth = max(width, 1)
        let normalizedPosition = min(max(xPosition / safeWidth, 0), 0.999)
        let index = min(Int(normalizedPosition * CGFloat(tabs.count)), tabs.count - 1)
        return tabs[index]
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(PaperTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(PaperTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FeedStatusBanner: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(PaperTheme.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: action)
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FilteredEmptyFeedView: View {
    let activeCount: Int
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 30))
            Text("当前筛选没有匹配帖子")
                .font(.headline)
            Text("已启用 \(activeCount) 项筛选，可以重置后查看全部内容。")
                .font(.footnote)
                .multilineTextAlignment(.center)
            Button("重置筛选", action: onReset)
                .buttonStyle(.borderedProminent)
                .tint(PaperTheme.accent)
                .accessibilityIdentifier("feed-filter-empty-reset-button")
        }
        .foregroundStyle(PaperTheme.mutedText)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

private struct EmptyFeedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 34))
                .foregroundStyle(PaperTheme.mutedText)
            Text("暂时没有可显示的主题")
                .font(.headline)
                .foregroundStyle(PaperTheme.ink)
            Text("可以下拉刷新，或切换栏目后再试。")
                .font(.subheadline)
                .foregroundStyle(PaperTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
    }
}
