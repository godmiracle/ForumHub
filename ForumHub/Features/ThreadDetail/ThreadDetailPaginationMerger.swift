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
        var seenIdentityKeys = Set(currentThread.replies.map {
            $0.stableIdentityKey(source: currentThread.source)
        })
        let appendedReplies = continuationReplies.filter { reply in
            seenIdentityKeys.insert(
                reply.stableIdentityKey(source: currentThread.source)
            ).inserted
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

        let normalizedReplyBody = ForumContentProjector.contentSignature(from: reply.contentDocument.blocks)
        let normalizedMainBody = ForumContentProjector.contentSignature(from: thread.contentDocument.blocks)
        guard !normalizedReplyBody.isEmpty, !normalizedMainBody.isEmpty else {
            return false
        }

        return normalizedReplyBody == normalizedMainBody
    }

}
