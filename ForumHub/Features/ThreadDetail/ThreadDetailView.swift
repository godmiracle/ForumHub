import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit
import WebKit

struct ThreadDetailView: View {
    let thread: ForumThread
    let repository: any ThreadRepository
    @Bindable var favoriteThreads: FavoriteThreadsStore
    @State private var detailThread: ForumThread
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var showsOnlyThreadAuthor = false
    @State private var showsRepliesInReverseOrder = false
    @State private var currentPage = 1
    @State private var hasMoreReplies = true
    @State private var isPreparingSnapshot = false
    @State private var snapshotImages: [UIImage] = []
    @State private var showsSnapshotShare = false
    @State private var snapshotErrorMessage: String?
    @State private var favoriteErrorMessage: String?
    @State private var isUpdatingFavorite = false
    @State private var showsReplyComposer = false
    @State private var replyText = ""
    @State private var replyAttachments: [ReplyComposerAttachment] = []
    @State private var isSubmittingReply = false
    @State private var replyErrorMessage: String?
    @State private var replySuccessMessage: String?

    init(thread: ForumThread, repository: any ThreadRepository, favoriteThreads: FavoriteThreadsStore) {
        self.thread = thread
        self.repository = repository
        self.favoriteThreads = favoriteThreads
        _detailThread = State(initialValue: thread)
    }

    var body: some View {
        List {
            Section {
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
                                TagChip(title: "\(detailThread.replyCount) 回复")
                                TagChip(title: "\(detailThread.viewCount) 浏览")
                            }

                            if detailThread.createdAt.isUsefulForumValue {
                                Text(detailThread.createdAt)
                                    .font(.caption)
                                    .foregroundStyle(PaperTheme.mutedText)
                            }
                        }
                    }

                    ForumRichContentView(text: detailThread.body, fontSize: 18)
                }
                .padding(.vertical, 8)
                .listRowBackground(PaperTheme.card)
            }

            if isLoading {
                Section {
                    ProgressView("正在加载回帖")
                        .tint(PaperTheme.mutedText)
                        .foregroundStyle(PaperTheme.mutedText)
                        .listRowBackground(PaperTheme.card)
                }
            }

            if let errorMessage {
                Section("错误") {
                    Text(errorMessage)
                        .foregroundStyle(PaperTheme.accent)
                        .listRowBackground(PaperTheme.card)
                }
            }

            if !detailThread.replies.isEmpty {
                Section(replySectionTitle) {
                    if displayedReplies.isEmpty, showsOnlyThreadAuthor {
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
                        .listRowBackground(PaperTheme.card)
                    }

                    ForEach(displayedReplies) { reply in
                        HStack(alignment: .top, spacing: 12) {
                            AvatarView(name: reply.author, imageURL: reply.avatarURL, size: 40)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(reply.author)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(PaperTheme.ink)
                                    Spacer()
                                    Text(floorLabel(for: reply))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(PaperTheme.secondaryInk)
                                    Text(reply.createdAt)
                                        .font(.caption)
                                        .foregroundStyle(PaperTheme.mutedText)
                                }

                                ForumRichContentView(text: reply.body, fontSize: 17)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(PaperTheme.card)
                    }
                }
            }

            if hasMoreReplies, !isLoading {
                Section {
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
                    .listRowBackground(PaperTheme.card)
                    .onAppear {
                        Task { await loadNextPage() }
                    }
                }
            } else if currentPage > 1, !isLoadingMore {
                Section {
                    Text("已经加载全部回帖")
                        .font(.footnote)
                        .foregroundStyle(PaperTheme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(PaperTheme.card)
                }
            }

        }
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
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
        .sheet(isPresented: $showsSnapshotShare, onDismiss: {
            snapshotImages = []
        }) {
            ActivityShareView(activityItems: snapshotImages)
                .presentationDetents([.medium, .large])
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
                text: $replyText,
                attachments: $replyAttachments,
                isSubmitting: isSubmittingReply,
                onCancel: {
                    showsReplyComposer = false
                },
                onSubmit: {
                    Task { await submitReply() }
                }
            )
            .presentationDetents([.medium])
        }
    }

    private var displayedReplies: [Reply] {
        let replies = showsOnlyThreadAuthor ? detailThread.authorReplies : detailThread.replies
        return showsRepliesInReverseOrder ? Array(replies.reversed()) : replies
    }

    private var replySectionTitle: String {
        showsOnlyThreadAuthor
            ? "楼主回帖 · \(displayedReplies.count)"
            : "回帖 · \(detailThread.replies.count)"
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
                        action: { showsReplyComposer = true }
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
                        Label("生成主楼长图", systemImage: "doc.richtext")
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
            showsSnapshotShare = true
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
            detailThread = loadedThread.mergingMetadataFallback(from: thread)
            currentPage = 1
            hasMoreReplies = shouldTryAnotherPage(
                loadedCount: loadedThread.replies.count,
                totalCount: detailThread.replyCount
            )
        } catch {
            errorMessage = error.localizedDescription
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

    private func floorLabel(for reply: Reply) -> String {
        if let index = detailThread.replies.firstIndex(where: { $0.id == reply.id }) {
            return "\(index + 2)楼"
        }
        return "--楼"
    }

    private func toggleAuthorFilter() {
        let enablesOnlyAuthor = !showsOnlyThreadAuthor
        withAnimation(.easeInOut(duration: 0.2)) {
            showsOnlyThreadAuthor.toggle()
        }
        if enablesOnlyAuthor, hasMoreReplies {
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
                replyErrorMessage = "登录 NGA 后才能回复主题。"
                return
            }
        }

        isSubmittingReply = true
        replyErrorMessage = nil
        defer { isSubmittingReply = false }

        do {
            try await repository.replyThread(
                tid: detailThread.id,
                content: trimmedReply,
                attachments: replyAttachments.map(\.upload)
            )
            replyText = ""
            replyAttachments = []
            showsReplyComposer = false
            await refreshDetail()
            replySuccessMessage = "回复已发送，帖子内容已刷新。"
        } catch {
            replyErrorMessage = error.localizedDescription
        }
    }

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

private struct ReplyComposerSheet: View {
    let source: ForumSource
    @Binding var text: String
    @Binding var attachments: [ReplyComposerAttachment]
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var imageLoadErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("将作为 \(source.title) 主题回复发送。")
                    .font(.footnote)
                    .foregroundStyle(PaperTheme.mutedText)

                if source == .nga {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 9,
                        matching: .images
                    ) {
                        Label("添加图片", systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PaperTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(isSubmitting)

                    if !attachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(attachments) { attachment in
                                    attachmentPreview(for: attachment)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 180)
                    .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack {
                    Text("\(text.trimmingCharacters(in: .whitespacesAndNewlines).count) 字")
                        .font(.caption)
                        .foregroundStyle(PaperTheme.mutedText)
                    Spacer()
                    if !attachments.isEmpty {
                        Text("\(attachments.count) 张图片")
                            .font(.caption)
                            .foregroundStyle(PaperTheme.mutedText)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(PaperBackground())
            .navigationTitle("回复主题")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await loadSelectedImages(items)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", action: onCancel)
                        .disabled(isSubmitting)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSubmit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("发送")
                        }
                    }
                    .disabled(isSubmitting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("图片处理失败", isPresented: imageLoadErrorBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(imageLoadErrorMessage ?? "请换一张图片重试。")
            }
        }
    }

    private var imageLoadErrorBinding: Binding<Bool> {
        Binding(
            get: { imageLoadErrorMessage != nil },
            set: { if !$0 { imageLoadErrorMessage = nil } }
        )
    }

    private func attachmentPreview(for attachment: ReplyComposerAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Image(uiImage: attachment.previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(attachment.filename)
                    .font(.caption2)
                    .foregroundStyle(PaperTheme.mutedText)
                    .lineLimit(1)
                    .frame(width: 96)
            }

            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .offset(x: 6, y: -6)
            .disabled(isSubmitting)
        }
    }

    private func loadSelectedImages(_ items: [PhotosPickerItem]) async {
        var loadedAttachments: [ReplyComposerAttachment] = []

        do {
            for (index, item) in items.enumerated() {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let preparedAttachment = ReplyComposerAttachment.make(from: image, index: attachments.count + index + 1)
                else {
                    throw ReplyComposerAttachmentError.unsupportedImage
                }
                loadedAttachments.append(preparedAttachment)
            }

            var seenKeys = Set(attachments.map(\.deduplicationKey))
            let uniqueAttachments = loadedAttachments.filter { attachment in
                seenKeys.insert(attachment.deduplicationKey).inserted
            }
            attachments.append(contentsOf: uniqueAttachments)
            selectedPhotoItems = []
        } catch {
            imageLoadErrorMessage = error.localizedDescription
            selectedPhotoItems = []
        }
    }
}

private struct ReplyComposerAttachment: Identifiable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data
    let previewImage: UIImage

    var upload: ReplyAttachmentUpload {
        ReplyAttachmentUpload(filename: filename, mimeType: mimeType, data: data)
    }

    var deduplicationKey: String {
        "\(filename)-\(data.count)"
    }

    static func make(from image: UIImage, index: Int) -> ReplyComposerAttachment? {
        let maxDimension: CGFloat = 2200
        let size = image.size
        let longestEdge = max(size.width, size.height)
        let scale = longestEdge > maxDimension ? maxDimension / longestEdge : 1
        let targetSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let renderedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = renderedImage.jpegData(compressionQuality: 0.85) else {
            return nil
        }

        return ReplyComposerAttachment(
            filename: "forumhub-reply-\(index).jpg",
            mimeType: "image/jpeg",
            data: jpegData,
            previewImage: renderedImage
        )
    }
}

private enum ReplyComposerAttachmentError: LocalizedError {
    case unsupportedImage

    var errorDescription: String? {
        "这张图片暂时无法处理，请换一张重试。"
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

private struct ForumRichContentView: View {
    let blocks: [ForumContentBlock]
    let fontSize: CGFloat

    init(text: String, fontSize: CGFloat) {
        blocks = ForumContentParser.parse(text)
        self.fontSize = fontSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                switch block.content {
                case let .text(text):
                    Text(text)
                        .font(.system(size: fontSize, design: .serif))
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .lineSpacing(fontSize >= 18 ? 6 : 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .image(url):
                    InteractiveForumImage(url: url)
                }
            }
        }
    }
}

private struct InteractiveForumImage: View {
    let url: URL
    @State private var asset: ForumRemoteImageAsset?
    @State private var failed = false
    @State private var showsPreview = false
    @State private var actionErrorMessage: String?
    @State private var isSavingImage = false

    var body: some View {
        Group {
            if let asset {
                Button {
                    showsPreview = true
                } label: {
                    ForumImageContent(asset: asset)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        Task { await saveImage() }
                    } label: {
                        if isSavingImage {
                            Label("保存中", systemImage: "arrow.down.circle")
                        } else {
                            Label("保存到相册", systemImage: "arrow.down.circle")
                        }
                    }

                    ShareLink(item: url) {
                        Label("分享图片链接", systemImage: "square.and.arrow.up")
                    }

                    Link(destination: url) {
                        Label("打开原图", systemImage: "safari")
                    }
                }
                .disabled(isSavingImage)
            } else if failed {
                Link(destination: url) {
                    Label("图片加载失败，点击打开原图", systemImage: "photo.badge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(PaperTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(PaperTheme.paperDeep.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            } else {
                ProgressView("图片加载中")
                    .tint(PaperTheme.mutedText)
                    .foregroundStyle(PaperTheme.mutedText)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .background(PaperTheme.paperDeep.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .accessibilityLabel("帖子图片")
        .task(id: url) {
            await loadImage()
        }
        .sheet(isPresented: $showsPreview) {
            if let asset {
                ForumImagePreviewSheet(
                    asset: asset,
                    imageURL: url,
                    onSave: {
                        Task { await saveImage() }
                    }
                )
            }
        }
        .alert("图片操作失败", isPresented: actionErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "请稍后重试。")
        }
    }

    private func loadImage() async {
        let hadPreviousAsset = asset != nil
        if asset == nil {
            failed = false
        }
        failed = false

        do {
            asset = try await NGAImageLoader.loadAsset(url: url)
        } catch is CancellationError {
            if !hadPreviousAsset, asset == nil {
                failed = true
            }
            return
        } catch {
            failed = true
        }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )
    }

    private func saveImage() async {
        guard let asset, !isSavingImage else { return }

        isSavingImage = true
        actionErrorMessage = nil
        defer { isSavingImage = false }

        do {
            try await ForumImageSaver.save(asset: asset)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }
}

private struct ForumImageContent: View {
    let asset: ForumRemoteImageAsset

    var body: some View {
        Group {
            if asset.isAnimatedGIF {
                AnimatedImageView(data: asset.data, mimeType: asset.mimeType, localFileURL: asset.localFileURL)
                    .aspectRatio(asset.displayAspectRatio, contentMode: .fit)
            } else {
                Image(uiImage: asset.previewImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if asset.isAnimatedGIF {
                Text("GIF")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(10)
            }
        }
    }
}

private struct ForumImagePreviewSheet: View {
    let asset: ForumRemoteImageAsset
    let imageURL: URL
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoomScale: CGFloat = 1
    @State private var accumulatedZoomScale: CGFloat = 1
    @State private var contentOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.96)
                    .ignoresSafeArea()

                previewContent
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .tint(.white)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        onSave()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .tint(.white)

                    ShareLink(item: imageURL) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .presentationBackground(.clear)
    }

    private var previewContent: some View {
        Group {
            if asset.isAnimatedGIF {
                AnimatedImageView(data: asset.data, mimeType: asset.mimeType, localFileURL: asset.localFileURL)
            } else {
                Image(uiImage: asset.previewImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
        .scaleEffect(zoomScale)
        .offset(contentOffset)
        .contentShape(Rectangle())
        .gesture(doubleTapGesture)
        .simultaneousGesture(magnificationGesture)
        .simultaneousGesture(dragGesture)
        .animation(.easeInOut(duration: 0.2), value: zoomScale)
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(duration: 0.28, bounce: 0.12)) {
                    if zoomScale > 1.01 {
                        resetZoom()
                    } else {
                        zoomScale = 2.5
                        accumulatedZoomScale = 2.5
                    }
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let nextScale = accumulatedZoomScale * value.magnification
                zoomScale = min(max(nextScale, 1), 4)
            }
            .onEnded { _ in
                accumulatedZoomScale = zoomScale
                if zoomScale <= 1.01 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        resetZoom()
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomScale > 1.01 else { return }
                contentOffset = CGSize(
                    width: accumulatedOffset.width + value.translation.width,
                    height: accumulatedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard zoomScale > 1.01 else {
                    resetZoom()
                    return
                }
                accumulatedOffset = contentOffset
            }
    }

    private func resetZoom() {
        zoomScale = 1
        accumulatedZoomScale = 1
        contentOffset = .zero
        accumulatedOffset = .zero
    }
}

private struct AnimatedImageView: UIViewRepresentable {
    let data: Data
    let mimeType: String
    let localFileURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let loadKey = localFileURL?.absoluteString ?? "\(mimeType)-\(data.count)"
        guard context.coordinator.lastLoadKey != loadKey else { return }
        context.coordinator.lastLoadKey = loadKey

        if let localFileURL {
            webView.loadFileURL(localFileURL, allowingReadAccessTo: localFileURL.deletingLastPathComponent())
            return
        }

        webView.load(
            data,
            mimeType: mimeType,
            characterEncodingName: "",
            baseURL: URL(string: "https://bbs.nga.cn/")!
        )
    }

    final class Coordinator {
        var lastLoadKey: String?
    }
}

struct ForumRemoteImageAsset {
    let data: Data
    let mimeType: String
    let previewImage: UIImage
    let localFileURL: URL?

    var isAnimatedGIF: Bool {
        mimeType == "image/gif"
    }

    var displayAspectRatio: CGFloat {
        let size = previewImage.size
        guard size.width > 0, size.height > 0 else { return 1 }
        return size.width / size.height
    }
}

private enum ForumImageSaver {
    static func save(asset: ForumRemoteImageAsset) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let authorized: PHAuthorizationStatus

        if status == .notDetermined {
            authorized = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            authorized = status
        }

        guard authorized == .authorized || authorized == .limited else {
            throw ForumImageSaveError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = asset.isAnimatedGIF ? "com.compuserve.gif" : "public.jpeg"
            request.addResource(with: .photo, data: asset.data, options: options)
        }
    }
}

private enum ForumImageSaveError: LocalizedError {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有相册写入权限，请在系统设置里允许后重试。"
        case .saveFailed:
            return "图片保存失败，请稍后再试。"
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
