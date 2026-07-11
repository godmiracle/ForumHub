import Observation

@MainActor
@Observable
final class ThreadDetailActionState {
    var favoriteErrorMessage: String?
    var isUpdatingFavorite = false
    var showsReplyComposer = false
    var replyTarget: ThreadReplyTarget = .thread
    var replyDocument = ReplyComposerDocument()
    var replyAttachments: [ReplyComposerAttachment] = []
    var isSubmittingReply = false
    var replyErrorMessage: String?
    var replySuccessMessage: String?
}
