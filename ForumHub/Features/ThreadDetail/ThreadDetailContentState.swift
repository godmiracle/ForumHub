import Observation

@MainActor
@Observable
final class ThreadDetailContentState {
    var thread: ForumThread
    var canonicalThread: ForumThread?
    var replyTotalCount: Int
    var rawText = ""
    var isLoading = false
    var isLoadingMore = false
    var error: ForumError?

    init(thread: ForumThread) {
        self.thread = thread
        replyTotalCount = thread.replyCount
    }
}
