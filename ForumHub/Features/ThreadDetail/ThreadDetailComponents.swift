import SwiftUI

struct ThreadDetailCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ThreadDetailHeaderSection: View {
    let thread: ForumThread
    let threadReplyTotalCount: Int
    let activeInlineGIFPlaybackIDs: Set<UUID>
    let scrollTrackingSpaceName: String

    var body: some View {
        ThreadDetailCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(thread.title)
                    .font(.system(size: 25, weight: .bold, design: .serif))
                    .foregroundStyle(PaperTheme.ink)

                HStack(alignment: .center, spacing: 12) {
                    AvatarView(name: thread.author, imageURL: thread.authorAvatarURL, size: 52)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TagChip(title: thread.source == .nga ? "0楼" : "主楼")
                            TagChip(title: thread.author)
                            TagChip(title: "\(threadReplyTotalCount) 回复")
                            TagChip(title: "\(thread.viewCount) 浏览")
                        }

                        if thread.createdAt.isUsefulForumValue {
                            Text(thread.createdAt)
                                .font(.caption)
                                .foregroundStyle(PaperTheme.mutedText)
                        }
                    }
                }

                ForumRichContentView(
                    document: thread.contentDocument,
                    fontSize: 18,
                    activeGIFPlaybackImageIDs: activeInlineGIFPlaybackIDs,
                    scrollTrackingSpaceName: scrollTrackingSpaceName
                )
            }
            .padding(.vertical, 8)
        }
    }
}

struct ThreadDetailReplySection: View {
    let title: String
    let entries: [ThreadDetailDisplayedReplyEntry]
    let showsOnlyThreadAuthor: Bool
    let displayedRepliesAreEmpty: Bool
    let supportsReply: Bool
    let supportsReplyTargeting: Bool
    let activeInlineGIFPlaybackIDs: Set<UUID>
    let scrollTrackingSpaceName: String
    let pageAnchorID: (Int) -> String
    let onReplyAppear: (ThreadDetailDisplayedReplyEntry) -> Void
    let onReplyAction: (ThreadDetailDisplayedReplyEntry) -> Void
    let onSnapshot: (ThreadDetailDisplayedReplyEntry) -> Void
    let onBlockUser: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(PaperTheme.ink)
                .padding(.horizontal, 4)

            Color.clear
                .frame(height: 1)
                .id("thread-detail-reply-top-anchor")

            if displayedRepliesAreEmpty, showsOnlyThreadAuthor {
                ThreadDetailCard {
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

            ForEach(entries) { entry in
                ThreadDetailReplyRow(
                    entry: entry,
                    supportsReply: supportsReply,
                    supportsReplyTargeting: supportsReplyTargeting,
                    activeInlineGIFPlaybackIDs: activeInlineGIFPlaybackIDs,
                    scrollTrackingSpaceName: scrollTrackingSpaceName,
                    pageAnchorID: pageAnchorID,
                    onAppear: { onReplyAppear(entry) },
                    onReplyAction: { onReplyAction(entry) },
                    onSnapshot: { onSnapshot(entry) },
                    onBlockUser: { onBlockUser(entry.reply.author) }
                )
            }
        }
    }
}

struct ThreadDetailReplyRow: View {
    let entry: ThreadDetailDisplayedReplyEntry
    let supportsReply: Bool
    let supportsReplyTargeting: Bool
    let activeInlineGIFPlaybackIDs: Set<UUID>
    let scrollTrackingSpaceName: String
    let pageAnchorID: (Int) -> String
    let onAppear: () -> Void
    let onReplyAction: () -> Void
    let onSnapshot: () -> Void
    let onBlockUser: () -> Void

    var body: some View {
        Group {
            if entry.showsPageAnchor {
                Color.clear
                    .frame(height: 1)
                    .id(pageAnchorID(entry.page))
                    .background(
                        GeometryReader { anchorProxy in
                            Color.clear.preference(
                                key: ThreadDetailPageAnchorOffsetPreferenceKey.self,
                                value: [entry.page: anchorProxy.frame(in: .named(scrollTrackingSpaceName)).minY]
                            )
                        }
                    )
            }

            ThreadDetailCard {
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
                            ThreadDetailReplyMenu(
                                entry: entry,
                                supportsReply: supportsReply,
                                supportsReplyTargeting: supportsReplyTargeting,
                                onReplyAction: onReplyAction,
                                onSnapshot: onSnapshot,
                                onBlockUser: onBlockUser
                            )
                        }

                        ForumRichContentView(
                            document: entry.displayedContentDocument,
                            fontSize: 17,
                            activeGIFPlaybackImageIDs: activeInlineGIFPlaybackIDs,
                            scrollTrackingSpaceName: scrollTrackingSpaceName
                        )
                        .accessibilityLabel(entry.reply.body)
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.leading, CGFloat(entry.visualDepth) * 12)
            .overlay(alignment: .leading) {
                if entry.showsThreadBranch {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(PaperTheme.accent.opacity(0.28))
                        .frame(width: 2)
                        .padding(.vertical, 8)
                }
            }
            .accessibilityIdentifier("thread-detail-reply-\(entry.reply.id)-depth-\(entry.visualDepth)")
            .onAppear(perform: onAppear)
        }
    }
}

struct ThreadDetailReplyMenu: View {
    let entry: ThreadDetailDisplayedReplyEntry
    let supportsReply: Bool
    let supportsReplyTargeting: Bool
    let onReplyAction: () -> Void
    let onSnapshot: () -> Void
    let onBlockUser: () -> Void

    var body: some View {
        Menu {
            if supportsReply && supportsReplyTargeting && entry.reply.sourcePostID != nil {
                Button(action: onReplyAction) {
                    Label("回复本层", systemImage: "arrowshape.turn.up.left")
                }
            }

            Button(action: onSnapshot) {
                Label("截图此层", systemImage: "camera.viewfinder")
            }

            if entry.reply.author.isBlockableForumUsername {
                Button(role: .destructive, action: onBlockUser) {
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
}

struct ThreadDetailActionBar: View {
    let supportsReply: Bool
    let supportsFavorites: Bool
    let isFavorited: Bool
    let canFilterByAuthor: Bool
    let showsOnlyThreadAuthor: Bool
    let isSubmittingReply: Bool
    let isUpdatingFavorite: Bool
    let isPreparingSnapshot: Bool
    let isLoading: Bool
    let showsRepliesInReverseOrder: Bool
    let supportsThreadedReplies: Bool
    let showsThreadedReplies: Bool
    let loadedSnapshotTitle: String
    let canShareThread: Bool
    let canBrowseOriginalThread: Bool
    let hasRawResponse: Bool
    let onReply: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleAuthorFilter: () -> Void
    let onRefresh: () -> Void
    let onToggleReplyOrder: () -> Void
    let onToggleThreadedReplies: () -> Void
    let onShareThreadLink: () -> Void
    let onSnapshotMainPost: () -> Void
    let onSnapshotLoadedContent: () -> Void
    let onBrowseOriginalThread: () -> Void
    let onCopyRawResponse: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if supportsReply {
                    ThreadActionButton(
                        title: "回复",
                        systemImage: "square.and.pencil",
                        isProminent: true,
                        isDisabled: isSubmittingReply,
                        action: onReply
                    )
                    .accessibilityIdentifier("thread-detail-reply-action")
                }

                ForumFloatingBar(padding: 4) {
                    HStack(spacing: 2) {
                        ThreadActionButton(
                            title: showsOnlyThreadAuthor ? "查看全部" : "只看楼主",
                            systemImage: showsOnlyThreadAuthor ? "person.2" : "person.crop.circle.badge.checkmark",
                            isActive: showsOnlyThreadAuthor,
                            isDisabled: !canFilterByAuthor,
                            action: onToggleAuthorFilter
                        )

                        Menu {
                            Button(action: onSnapshotMainPost) {
                                Label("分享主楼截图", systemImage: "camera.viewfinder")
                            }

                            if canShareThread {
                                Button(action: onShareThreadLink) {
                                    Label("分享帖子链接", systemImage: "link")
                                }
                            }

                            Button(action: onSnapshotLoadedContent) {
                                Label(loadedSnapshotTitle, systemImage: "rectangle.stack")
                            }
                        } label: {
                            ThreadActionButtonLabel(
                                title: "分享",
                                systemImage: "square.and.arrow.up",
                                isActive: false,
                                isProminent: false
                            )
                        }
                        .disabled(isPreparingSnapshot || isLoading)
                        .accessibilityLabel("分享")

                        Menu {
                            if supportsFavorites {
                                Button(action: onToggleFavorite) {
                                    Label(
                                        isFavorited ? "取消收藏" : "收藏帖子",
                                        systemImage: isFavorited ? "star.fill" : "star"
                                    )
                                }
                                .disabled(isUpdatingFavorite)
                            }

                            if canBrowseOriginalThread {
                                Button(action: onBrowseOriginalThread) {
                                    Label("浏览网页原帖", systemImage: "safari")
                                }
                            }

                            Button(action: onRefresh) {
                                Label("刷新", systemImage: "arrow.clockwise")
                            }

                            Button(action: onToggleReplyOrder) {
                                Label(
                                    showsRepliesInReverseOrder ? "恢复正序" : "倒叙排列",
                                    systemImage: showsRepliesInReverseOrder ? "arrow.down.to.line" : "arrow.up.arrow.down"
                                )
                            }

                            if supportsThreadedReplies {
                                Button(action: onToggleThreadedReplies) {
                                    Label(
                                        showsThreadedReplies ? "平铺回帖" : "楼中楼显示",
                                        systemImage: showsThreadedReplies ? "list.bullet" : "arrow.turn.down.right"
                                    )
                                }
                                .accessibilityIdentifier("thread-detail-reply-tree-toggle")
                            }

                            #if DEBUG
                            if hasRawResponse {
                                Button(action: onCopyRawResponse) {
                                    Label("复制当前原始响应（调试）", systemImage: "doc.on.doc")
                                }
                            }
                            #endif
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
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

struct ThreadDetailFloatingControls: View {
    let showsScrollToTopControl: Bool
    let supportsDirectPagination: Bool
    let totalPageCount: Int
    let isLoading: Bool
    let isLoadingMore: Bool
    let visiblePage: Int
    let floatingControlTransition: AnyTransition
    let floatingControlAnimation: Animation
    let onScrollToTop: () -> Void
    let onNavigateToPreviousPage: () -> Void
    let onNavigateToNextPage: () -> Void
    let onOpenPagePicker: () -> Void

    var body: some View {
        Group {
            if supportsDirectPagination, totalPageCount > 1, !isLoading {
                ThreadDetailFloatingPaginationControl(
                    showsScrollToTopControl: showsScrollToTopControl,
                    visiblePage: visiblePage,
                    totalPageCount: totalPageCount,
                    isLoadingMore: isLoadingMore,
                    onScrollToTop: onScrollToTop,
                    onNavigateToPreviousPage: onNavigateToPreviousPage,
                    onNavigateToNextPage: onNavigateToNextPage,
                    onOpenPagePicker: onOpenPagePicker
                )
                .transition(floatingControlTransition)
            } else if showsScrollToTopControl {
                Button(action: onScrollToTop) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .frame(width: 44, height: 44)
                        .forumGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .transition(floatingControlTransition)
                .accessibilityLabel("回到顶部")
                .accessibilityIdentifier("thread-detail-scroll-to-top")
            }
        }
        .padding(.trailing, 18)
        .padding(.bottom, 88)
        .animation(floatingControlAnimation, value: showsScrollToTopControl)
        .animation(
            floatingControlAnimation,
            value: supportsDirectPagination && totalPageCount > 1 && !isLoading
        )
    }
}

struct ThreadDetailFloatingPaginationControl: View {
    let showsScrollToTopControl: Bool
    let visiblePage: Int
    let totalPageCount: Int
    let isLoadingMore: Bool
    let onScrollToTop: () -> Void
    let onNavigateToPreviousPage: () -> Void
    let onNavigateToNextPage: () -> Void
    let onOpenPagePicker: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if showsScrollToTopControl {
                paginationIconButton(
                    systemImage: "arrow.up",
                    accessibilityLabel: "回到顶部",
                    accessibilityIdentifier: "thread-detail-scroll-to-top",
                    action: onScrollToTop
                )
                controlDivider
            }

            paginationIconButton(
                systemImage: "chevron.left",
                isDisabled: isLoadingMore || visiblePage <= 1,
                accessibilityLabel: "上一页",
                accessibilityIdentifier: "thread-detail-previous-page",
                action: onNavigateToPreviousPage
            )
            controlDivider

            Button(action: onOpenPagePicker) {
                Text("\(visiblePage) / \(totalPageCount)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PaperTheme.secondaryInk)
                    .frame(minWidth: 62, minHeight: 44)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("thread-detail-current-page")
            .accessibilityLabel("当前页码")
            .accessibilityValue("\(visiblePage) / \(totalPageCount)")

            controlDivider
            paginationIconButton(
                systemImage: "chevron.right",
                isDisabled: isLoadingMore || visiblePage >= totalPageCount,
                accessibilityLabel: "下一页",
                accessibilityIdentifier: "thread-detail-next-page",
                action: onNavigateToNextPage
            )
        }
        .forumGlass(in: Capsule())
        .animation(.easeInOut(duration: 0.18), value: showsScrollToTopControl)
    }

    private var controlDivider: some View {
        Capsule()
            .fill(Color.white.opacity(0.16))
            .frame(width: 1, height: 18)
            .allowsHitTesting(false)
    }

    private func paginationIconButton(
        systemImage: String,
        isDisabled: Bool = false,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct ThreadDetailPagePickerSheet: View {
    @Binding var pendingPageSelection: Int
    let totalPageCount: Int
    let onJump: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
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
                        .fill(.clear)
                        .forumGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))

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
                        onJump(1)
                    }

                    pagePickerActionButton(
                        title: "最后一页",
                        systemImage: "forward.end.fill"
                    ) {
                        onJump(totalPageCount)
                    }
                }

                HStack(spacing: 10) {
                    pagePickerActionButton(
                        title: "取消",
                        systemImage: "xmark",
                        style: .secondary,
                        action: onCancel
                    )

                    pagePickerActionButton(
                        title: "确定",
                        systemImage: "checkmark",
                        style: .primary
                    ) {
                        onJump(pendingPageSelection)
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

    private func pagePickerActionButton(
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

    private func pagePickerActionBackground(for style: PagePickerActionButtonStyle) -> some ShapeStyle {
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

    private func pagePickerActionBorderColor(for style: PagePickerActionButtonStyle) -> Color {
        switch style {
        case .primary:
            return PaperTheme.accent.opacity(0.38)
        case .secondary:
            return Color.white.opacity(0.14)
        case .neutral:
            return Color.white.opacity(0.2)
        }
    }

    private func pagePickerActionForegroundColor(for style: PagePickerActionButtonStyle) -> Color {
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

struct ThreadDetailDisplayedReplyEntry: Identifiable {
    let reply: Reply
    let page: Int
    let showsPageAnchor: Bool
    let floorLabel: String
    let loadsNextPageWhenAppearing: Bool
    let hierarchyDepth: Int
    let visualDepth: Int
    let displayedContentDocument: ForumPostDocument

    var id: Int { reply.id }
    var showsThreadBranch: Bool { hierarchyDepth > 0 }
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
            if isProminent || isActive {
                Circle()
                    .stroke(borderColor, lineWidth: 0.8)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isProminent ? 0.16 : 0.12),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(1)
            }

            Image(systemName: systemImage)
                .font(.system(size: isProminent ? 17 : 15, weight: .semibold))
                .foregroundColor(foregroundColor)
        }
        .frame(width: isProminent ? 48 : 44, height: isProminent ? 48 : 44)
        .contentShape(Circle())
        .shadow(color: shadowColor, radius: isProminent ? 10 : 0, y: isProminent ? 5 : 0)
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
            Color.clear
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
