import Foundation

enum ThreadPaginationPolicy {
    static func supportsDirectPagination(for capabilities: ForumCapabilities) -> Bool {
        if case .numbered = capabilities.threadPaginationStyle { return true }
        return false
    }

    static func pageSize(for capabilities: ForumCapabilities) -> Int? {
        if case let .numbered(pageSize) = capabilities.threadPaginationStyle { return pageSize }
        return nil
    }

    static func totalPageCount(replyCount: Int, fallbackReplyCount: Int, capabilities: ForumCapabilities) -> Int {
        guard let pageSize = pageSize(for: capabilities), pageSize > 0 else { return 1 }
        let totalPosts = max(max(replyCount, fallbackReplyCount) + 1, 1)
        return max(1, Int(ceil(Double(totalPosts) / Double(pageSize))))
    }
}
