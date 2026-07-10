import Observation

@MainActor
@Observable
final class ThreadDetailPaginationState {
    var currentPage = 1
    var hasMoreReplies = true
    var visiblePage = 1
    var pageStartReplyIndices: [Int: Int] = [1: 0]
    var pendingPageSelection = 1
    var deferredScrollTargetPage: Int?
    var lastAutoLoadedPage: Int?
}
