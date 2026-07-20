import Foundation
import Observation

@MainActor
@Observable
final class ThreadDetailViewModel {
    let content: ThreadDetailContentState
    let contentLoader = ThreadDetailContentLoadController()
    let pagination = ThreadDetailPaginationState()
    let actions = ThreadDetailActionState()

    init(thread: ForumThread) {
        content = ThreadDetailContentState(thread: thread)
    }

    @discardableResult
    func refresh(thread fallbackThread: ForumThread, repository: any ThreadRepository) async -> Bool {
        await contentLoader.start { generation in
            guard self.contentLoader.isCurrent(generation) else { return false }
            self.content.isLoading = true
            self.content.isLoadingMore = false
            self.content.error = nil
            defer {
                if self.contentLoader.isCurrent(generation) {
                    self.content.isLoading = false
                }
            }

            do {
                let result = try await repository.fetchThread(tid: fallbackThread.id, page: 1)
                guard self.contentLoader.isCurrent(generation) else { return false }
                let mergedThread = result.thread.mergingMetadataFallback(from: fallbackThread)
                let replyTotal = max(self.content.replyTotalCount, fallbackThread.replyCount, mergedThread.replyCount)
                self.content.thread = mergedThread
                self.content.canonicalThread = mergedThread
                self.content.replyTotalCount = replyTotal
                self.content.rawText = result.rawText
                self.pagination.currentPage = 1
                self.pagination.pageStartReplyIndices = [1: 0]
                self.pagination.hasMoreReplies = ThreadPaginationPolicy.supportsDirectPagination(for: repository.capabilities)
                    ? ThreadPaginationPolicy.totalPageCount(replyCount: replyTotal, fallbackReplyCount: fallbackThread.replyCount, capabilities: repository.capabilities) > 1
                    : result.thread.replies.count >= 20 || result.thread.replies.count < replyTotal
                return true
            } catch {
                guard self.contentLoader.isCurrent(generation) else { return false }
                self.content.error = ForumError.resolve(error)
                return false
            }
        }
    }

    func loadNextPage(
        thread fallbackThread: ForumThread,
        repository: any ThreadRepository,
        showsOnlyAuthor: Bool
    ) async {
        guard pagination.hasMoreReplies, !content.isLoading, !content.isLoadingMore else { return }

        _ = await contentLoader.start { generation in
            guard self.contentLoader.isCurrent(generation) else { return false }
            self.content.isLoadingMore = true
            self.content.error = nil
            defer {
                if self.contentLoader.isCurrent(generation) {
                    self.content.isLoadingMore = false
                }
            }

            do {
                let authorReplyCount = self.content.thread.authorReplies.count
                var scannedPageCount = 0
                repeat {
                    guard self.contentLoader.isCurrent(generation) else { return false }
                    let nextPage = self.pagination.currentPage + 1
                    let result = try await repository.fetchThread(tid: fallbackThread.id, page: nextPage)
                    guard self.contentLoader.isCurrent(generation) else { return false }
                    let total = max(self.content.replyTotalCount, self.content.thread.replyCount, result.thread.replyCount)
                    let merge = ThreadDetailPaginationMerger.merge(
                        currentThread: self.content.thread,
                        continuationThread: result.thread,
                        replyTotalCount: total
                    )
                    scannedPageCount += 1
                    guard !merge.continuationReplies.isEmpty, merge.didAppendReplies else {
                        self.pagination.hasMoreReplies = false
                        break
                    }
                    self.content.thread = merge.thread
                    self.content.replyTotalCount = total
                    self.pagination.currentPage = nextPage
                    self.pagination.hasMoreReplies = merge.continuationReplies.count >= 20 || self.content.thread.replies.count < self.content.thread.replyCount
                    guard ThreadDetailPaginationPolicy.shouldContinueAutomaticLoading(
                        showsOnlyAuthor: showsOnlyAuthor,
                        authorReplyCountBeforeLoad: authorReplyCount,
                        authorReplyCountAfterLoad: self.content.thread.authorReplies.count,
                        hasMoreReplies: self.pagination.hasMoreReplies,
                        scannedPageCount: scannedPageCount
                    ) else { break }
                } while self.pagination.hasMoreReplies
                return true
            } catch {
                guard self.contentLoader.isCurrent(generation) else { return false }
                self.content.error = ForumError.resolve(error)
                return false
            }
        }
    }

    func loadThroughPage(_ targetPage: Int, thread fallbackThread: ForumThread, repository: any ThreadRepository) async -> Bool {
        guard ThreadPaginationPolicy.supportsDirectPagination(for: repository.capabilities), !content.isLoading else { return false }
        guard targetPage > pagination.currentPage else { return true }
        return await contentLoader.start { generation in
            self.content.isLoadingMore = true
            self.content.error = nil
            defer { if self.contentLoader.isCurrent(generation) { self.content.isLoadingMore = false } }
            do {
                var workingThread = self.content.thread
                var total = self.content.replyTotalCount
                var pageStarts = self.pagination.pageStartReplyIndices
                for page in (self.pagination.currentPage + 1)...targetPage {
                    guard self.contentLoader.isCurrent(generation) else { return false }
                    let result = try await repository.fetchThread(tid: fallbackThread.id, page: page)
                    total = max(total, fallbackThread.replyCount, result.thread.replyCount)
                    let merge = ThreadDetailPaginationMerger.merge(currentThread: workingThread, continuationThread: result.thread, replyTotalCount: total)
                    workingThread = merge.thread
                    pageStarts[page] = merge.pageStartReplyIndex
                }
                guard self.contentLoader.isCurrent(generation) else { return false }
                self.content.thread = workingThread
                self.content.replyTotalCount = total
                self.pagination.currentPage = targetPage
                self.pagination.pageStartReplyIndices = pageStarts
                self.pagination.hasMoreReplies = targetPage < ThreadPaginationPolicy.totalPageCount(replyCount: total, fallbackReplyCount: fallbackThread.replyCount, capabilities: repository.capabilities)
                return true
            } catch {
                guard self.contentLoader.isCurrent(generation) else { return false }
                self.content.error = ForumError.resolve(error)
                return false
            }
        }
    }

    func toggleFavorite(
        thread: ForumThread,
        repository: any ThreadRepository,
        favoriteThreads: FavoriteThreadsStore
    ) async -> String? {
        guard !actions.isUpdatingFavorite else { return nil }

        actions.isUpdatingFavorite = true
        actions.favoriteErrorMessage = nil
        defer { actions.isUpdatingFavorite = false }

        do {
            guard repository.capabilities.supportsFavorites else { return nil }
            if favoriteThreads.contains(thread) {
                try await repository.removeFavoriteThread(tid: thread.id)
                favoriteThreads.remove(thread)
            } else {
                try await repository.addFavoriteThread(tid: thread.id)
                favoriteThreads.save(thread)
            }
            return nil
        } catch {
            let message = ForumError.resolve(error)?.userMessage ?? "收藏操作失败，请稍后重试。"
            actions.favoriteErrorMessage = message
            return message
        }
    }

    func submitReply(
        thread: ForumThread,
        repository: any ThreadRepository,
        refreshDetail: @escaping @MainActor () async -> Void
    ) async {
        guard !actions.isSubmittingReply else { return }

        let content = actions.replyDocument.markup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            actions.replyErrorMessage = "回复内容不能为空。"
            return
        }

        if repository.source == .nga {
            let loginState = await NGAAuthStore.shared.currentLoginState()
            guard loginState.isLoggedIn else {
                actions.replyErrorMessage = "登录 NGA 后才能发送回复。"
                return
            }
        }

        actions.isSubmittingReply = true
        actions.replyErrorMessage = nil
        defer { actions.isSubmittingReply = false }

        do {
            let target = actions.replyTarget
            try await repository.replyThread(
                tid: thread.id,
                target: target,
                content: content,
                attachments: actions.replyAttachments.map(\.upload)
            )
            actions.replyDocument = ReplyComposerDocument()
            actions.replyAttachments = []
            actions.showsReplyComposer = false
            await refreshDetail()
            actions.replySuccessMessage = replySuccessMessage(for: target)
        } catch where Self.isCancellation(error) {
            return
        } catch {
            actions.replyErrorMessage = ForumError.resolve(error)?.userMessage ?? "回复失败，请稍后重试。"
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func replySuccessMessage(for target: ThreadReplyTarget) -> String {
        switch target {
        case .thread:
            return "回复已发送，帖子内容已刷新。"
        case let .reply(targetReply):
            return "已回复 \(targetReply.displayFloorLabel)，帖子内容已刷新。"
        }
    }
}
