import Observation

@MainActor
@Observable
final class ThreadDetailPaginationState {
    var currentPage = 1
    var hasMoreReplies = true
    var pageStartReplyIndices: [Int: Int] = [1: 0]
}
