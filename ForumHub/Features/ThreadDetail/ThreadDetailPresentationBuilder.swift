import Foundation

enum ThreadDetailPresentationBuilder {
    static func displayedReplies(
        thread: ForumThread,
        showsOnlyThreadAuthor: Bool,
        showsRepliesInReverseOrder: Bool,
        source: ForumSource,
        isBlocked: (ForumSource, String) -> Bool
    ) -> [Reply] {
        let sourceReplies = showsOnlyThreadAuthor ? thread.authorReplies : thread.replies
        let visibleReplies = sourceReplies.filter { !isBlocked(source, $0.author) }
        return showsRepliesInReverseOrder ? Array(visibleReplies.reversed()) : visibleReplies
    }

    static func displayedReplyEntries(
        displayedReplies: [Reply],
        allReplies: [Reply],
        pageStartReplyIndices: [Int: Int],
        supportsDirectPagination: Bool,
        pageSize: Int,
        prefetchReplyDistance: Int
    ) -> [ThreadDetailDisplayedReplyEntry] {
        let sortedPageStarts = pageStartReplyIndices.sorted { $0.value < $1.value }
        let replyIndices = Dictionary(uniqueKeysWithValues: allReplies.enumerated().map { ($1.id, $0) })
        let prefetchStartIndex = max(displayedReplies.count - prefetchReplyDistance, 0)
        var firstVisibleReplyIDByPage: [Int: Int] = [:]

        return displayedReplies.enumerated().map { visualIndex, reply in
            let replyIndex = replyIndices[reply.id]
            let page = resolvedPage(forReplyIndex: replyIndex, pageStarts: sortedPageStarts)
            let showsPageAnchor = firstVisibleReplyIDByPage[page] == nil
            if showsPageAnchor { firstVisibleReplyIDByPage[page] = reply.id }

            return ThreadDetailDisplayedReplyEntry(
                reply: reply,
                page: page,
                showsPageAnchor: showsPageAnchor,
                floorLabel: floorLabel(
                    replyIndex: replyIndex,
                    page: page,
                    floorNumber: reply.floorNumber,
                    pageStartReplyIndices: pageStartReplyIndices,
                    supportsDirectPagination: supportsDirectPagination,
                    pageSize: pageSize
                ),
                loadsNextPageWhenAppearing: visualIndex >= prefetchStartIndex
            )
        }
    }

    private static func resolvedPage(forReplyIndex replyIndex: Int?, pageStarts: [(key: Int, value: Int)]) -> Int {
        guard let replyIndex else { return 1 }
        return pageStarts.last(where: { $0.value <= replyIndex })?.key ?? 1
    }

    private static func floorLabel(
        replyIndex: Int?, page: Int, floorNumber: Int?, pageStartReplyIndices: [Int: Int], supportsDirectPagination: Bool, pageSize: Int
    ) -> String {
        if let floorNumber, floorNumber > 0 { return "\(floorNumber)楼" }
        guard let replyIndex else { return "--楼" }
        guard supportsDirectPagination, page > 1 else { return "\(replyIndex + 2)楼" }
        let pageStartIndex = pageStartReplyIndices[page] ?? 0
        return "\(((page - 1) * pageSize) + (replyIndex - pageStartIndex) + 1)楼"
    }
}
