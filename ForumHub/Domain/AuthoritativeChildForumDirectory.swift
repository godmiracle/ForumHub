import Foundation

struct AuthoritativeChildForum: Identifiable, Equatable {
    let stableKey: String
    let title: String
    let channel: ForumChannel

    var id: String { stableKey }
}

struct AuthoritativeChildForumDirectory: Equatable {
    let parent: ForumChannel
    let children: [AuthoritativeChildForum]
}
