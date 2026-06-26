import Foundation
import Observation

struct SavedForumThread: Codable, Equatable, Identifiable {
    let source: ForumSource
    let threadID: Int
    let title: String
    let summary: String
    let author: String
    let createdAt: String
    let lastReplyAt: String
    let replyCount: Int
    let viewCount: Int
    let channelID: Int?
    let channelTitle: String?
    let savedAt: Date

    var id: String { "\(source.rawValue):\(threadID)" }

    init(thread: ForumThread, savedAt: Date = .now) {
        source = thread.source
        threadID = thread.id
        title = thread.title
        summary = thread.summary
        author = thread.author
        createdAt = thread.createdAt
        lastReplyAt = thread.lastReplyAt
        replyCount = thread.replyCount
        viewCount = thread.viewCount
        channelID = thread.channelID
        channelTitle = thread.channelTitle
        self.savedAt = savedAt
    }

    var thread: ForumThread {
        ForumThread(
            id: threadID,
            title: title,
            summary: summary,
            author: author,
            createdAt: createdAt,
            lastReplyAt: lastReplyAt,
            replyCount: replyCount,
            viewCount: viewCount,
            body: summary,
            replies: [],
            source: source,
            channelID: channelID,
            channelTitle: channelTitle
        )
    }
}

@MainActor
@Observable
final class FavoriteThreadsStore {
    private(set) var entries: [SavedForumThread]
    private let defaults: UserDefaults
    private let storageKey = "favorite-forum-threads-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode([SavedForumThread].self, from: data) {
            entries = snapshot.sorted { $0.savedAt > $1.savedAt }
        } else {
            entries = []
        }
    }

    func contains(_ thread: ForumThread) -> Bool {
        entries.contains { $0.source == thread.source && $0.threadID == thread.id }
    }

    func save(_ thread: ForumThread) {
        let entry = SavedForumThread(thread: thread)
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(200))
        persist()
    }

    func remove(_ thread: ForumThread) {
        entries.removeAll { $0.source == thread.source && $0.threadID == thread.id }
        persist()
    }

    func toggle(_ thread: ForumThread) {
        if contains(thread) {
            remove(thread)
        } else {
            save(thread)
        }
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
