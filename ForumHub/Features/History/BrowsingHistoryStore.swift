import Foundation
import Observation

struct BrowsingHistoryEntry: Codable, Equatable, Identifiable {
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
    let visitedAt: Date

    var id: String { "\(source.rawValue):\(threadID)" }

    init(thread: ForumThread, visitedAt: Date = .now) {
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
        self.visitedAt = visitedAt
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
            body: "",
            replies: [],
            source: source,
            channelID: channelID,
            channelTitle: channelTitle
        )
    }
}

@MainActor
@Observable
final class BrowsingHistoryStore {
    private(set) var entries: [BrowsingHistoryEntry]
    private let defaults: UserDefaults
    private let storageKey = "forum-browsing-history-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let savedEntries = try? JSONDecoder().decode([BrowsingHistoryEntry].self, from: data) {
            entries = savedEntries
        } else {
            entries = []
        }
    }

    func record(_ thread: ForumThread) {
        let entry = BrowsingHistoryEntry(thread: thread)
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(50))
        persist()
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
