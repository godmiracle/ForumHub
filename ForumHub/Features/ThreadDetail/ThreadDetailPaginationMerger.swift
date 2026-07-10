import Foundation

struct ThreadDetailPaginationMergeResult {
    let thread: ForumThread
    let continuationReplies: [Reply]
    let appendedReplies: [Reply]
    let pageStartReplyIndex: Int

    var didAppendReplies: Bool {
        !appendedReplies.isEmpty
    }
}

enum ThreadDetailPaginationMerger {
    static func merge(
        currentThread: ForumThread,
        continuationThread: ForumThread,
        replyTotalCount: Int
    ) -> ThreadDetailPaginationMergeResult {
        let continuationReplies = continuationThread.replies.filter {
            !isDuplicateOfMainPost($0, in: currentThread)
        }
        let existingIDs = Set(currentThread.replies.map(\.id))
        let existingSignatureKeys = Set(currentThread.replies.map(\.signatureKey))
        let appendedReplies = continuationReplies.filter { reply in
            !existingIDs.contains(reply.id) && !existingSignatureKeys.contains(reply.signatureKey)
        }
        let combinedReplies = currentThread.replies + appendedReplies
        let resolvedReplyTotal = max(
            replyTotalCount,
            currentThread.replyCount,
            continuationThread.replyCount,
            combinedReplies.count
        )
        let mergedThread = currentThread.replacingReplies(
            combinedReplies,
            lastReplyAt: appendedReplies.last?.createdAt ?? currentThread.lastReplyAt,
            replyCount: resolvedReplyTotal
        )

        return ThreadDetailPaginationMergeResult(
            thread: mergedThread,
            continuationReplies: continuationReplies,
            appendedReplies: appendedReplies,
            pageStartReplyIndex: currentThread.replies.count
        )
    }

    private static func isDuplicateOfMainPost(
        _ reply: Reply,
        in thread: ForumThread
    ) -> Bool {
        let normalizedReplyAuthor = reply.author.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedThreadAuthor = thread.author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReplyAuthor.isEmpty,
              !normalizedThreadAuthor.isEmpty,
              normalizedReplyAuthor.compare(
                  normalizedThreadAuthor,
                  options: [.caseInsensitive, .diacriticInsensitive]
              ) == .orderedSame
        else {
            return false
        }

        let normalizedReplyBody = normalizedContent(reply.body)
        let normalizedMainBody = normalizedContent(thread.body)
        guard !normalizedReplyBody.isEmpty, !normalizedMainBody.isEmpty else {
            return false
        }

        return normalizedReplyBody == normalizedMainBody
    }

    private static func normalizedContent(_ content: String) -> String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
