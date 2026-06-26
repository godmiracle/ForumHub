import Foundation
import Observation

struct BlockedForumUser: Codable, Identifiable, Equatable {
    let source: ForumSource
    let username: String

    var id: String {
        "\(source.rawValue):\(username.normalizedForumUsername)"
    }
}

@MainActor
@Observable
final class BlockedUsersStore {
    private(set) var blockedUsers: [BlockedForumUser]
    private let defaults: UserDefaults
    private let storageKey = "blocked-forum-users-v2"
    private let legacyStorageKey = "blocked-forum-usernames"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([BlockedForumUser].self, from: data) {
            blockedUsers = decoded
        } else {
            blockedUsers = (defaults.stringArray(forKey: legacyStorageKey) ?? [])
                .filter(\.isBlockableForumUsername)
                .uniquedCaseInsensitive()
                .map { BlockedForumUser(source: .nga, username: $0) }
        }
        sort()
        persist()
    }

    func isBlocked(source: ForumSource, username: String) -> Bool {
        let key = username.normalizedForumUsername
        return blockedUsers.contains {
            $0.source == source && $0.username.normalizedForumUsername == key
        }
    }

    func block(source: ForumSource, username: String) {
        let cleaned = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isBlockableForumUsername,
              !isBlocked(source: source, username: cleaned)
        else { return }

        blockedUsers.append(BlockedForumUser(source: source, username: cleaned))
        sort()
        persist()
    }

    func unblock(_ user: BlockedForumUser) {
        blockedUsers.removeAll { $0.id == user.id }
        persist()
    }

    func removeAll() {
        blockedUsers = []
        persist()
    }

    func filtering(_ threads: [ForumThread]) -> [ForumThread] {
        threads.filter { !isBlocked(source: $0.source, username: $0.author) }
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(blockedUsers), forKey: storageKey)
    }

    private func sort() {
        blockedUsers.sort {
            if $0.source != $1.source { return $0.source.rawValue < $1.source.rawValue }
            return $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
        }
    }
}

extension String {
    var normalizedForumUsername: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    var isBlockableForumUsername: Bool {
        isUsefulForumValue && normalizedForumUsername != "未知作者"
    }
}

private extension Array where Element == String {
    func uniquedCaseInsensitive() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.normalizedForumUsername).inserted }
    }
}
