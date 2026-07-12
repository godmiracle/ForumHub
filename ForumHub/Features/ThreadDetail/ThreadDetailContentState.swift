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
        // 信息流只提供主题摘要；它不是可用于详情页的 0 楼正文。
        // 在详情请求成功前保留其元数据，但绝不把摘要当作主楼内容展示。
        self.thread = Self.placeholder(from: thread)
        replyTotalCount = thread.replyCount
        isLoading = true
    }

    private static func placeholder(from thread: ForumThread) -> ForumThread {
        ForumThread(
            id: thread.id,
            title: thread.title,
            summary: thread.summary,
            author: thread.author,
            authorAvatarURL: thread.authorAvatarURL,
            createdAt: thread.createdAt,
            lastReplyAt: thread.lastReplyAt,
            replyCount: thread.replyCount,
            viewCount: thread.viewCount,
            body: "",
            contentDocument: .plainText(""),
            replies: [],
            source: thread.source,
            channelID: thread.channelID,
            channelTitle: thread.channelTitle
        )
    }
}
