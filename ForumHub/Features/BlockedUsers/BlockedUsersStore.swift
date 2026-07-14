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
    private(set) var iCloudSyncState: ICloudBlockedUsersSyncState = .syncing
    private var syncRecords: [BlockedUserSyncRecord]
    private let defaults: UserDefaults
    private let cloudStore: any ICloudKeyValueStoring
    private let storageKey = "blocked-forum-users-v3"
    private let schemaVersion = 1

    init(
        defaults: UserDefaults = .standard,
        cloudStore: any ICloudKeyValueStoring = NSUbiquitousKeyValueStore.default
    ) {
        self.defaults = defaults
        self.cloudStore = cloudStore
        syncRecords = Self.decodeRecords(defaults.data(forKey: storageKey), version: schemaVersion)
        blockedUsers = []
        rebuildBlockedUsers()
        refreshFromICloud()
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

        upsert(source: source, username: cleaned, isBlocked: true)
    }

    func unblock(_ user: BlockedForumUser) {
        upsert(source: user.source, username: user.username, isBlocked: false)
    }

    func removeAll() {
        let timestamp = Date.now
        let changedRecords = syncRecords.compactMap { record -> BlockedUserSyncRecord? in
            guard record.isBlocked else { return nil }
            return BlockedUserSyncRecord(
                source: record.source,
                username: record.username,
                isBlocked: false,
                updatedAt: timestamp
            )
        }
        guard !changedRecords.isEmpty else { return }
        for record in changedRecords {
            replaceLocalRecord(record)
        }
        rebuildBlockedUsers()
        persistLocal()
        changedRecords.forEach(upload)
    }

    func refreshFromICloud(reconcilesConflicts: Bool = false) {
        guard cloudStore.synchronize() else {
            iCloudSyncState = .failed("iCloud 暂时不可用，屏蔽操作仍会保存在本机。")
            return
        }
        let remoteRecords = BlockedUserCloudCodec.records(in: cloudStore.dictionaryRepresentation)
        let localRecords = syncRecords
        let mergedRecords = BlockedUserSyncMerge.merge(localRecords, remoteRecords)
        syncRecords = mergedRecords
        rebuildBlockedUsers()
        persistLocal()
        iCloudSyncState = .synced

        guard reconcilesConflicts else { return }
        var remoteByID: [String: BlockedUserSyncRecord] = [:]
        for record in remoteRecords {
            remoteByID[record.id] = BlockedUserSyncMerge.merge(
                remoteByID[record.id].map { [$0] } ?? [],
                [record]
            ).first
        }
        for record in mergedRecords {
            guard let remoteRecord = remoteByID[record.id], remoteRecord != record else { continue }
            upload(record)
        }
    }

    func handleICloudChange(reason: Int) {
        switch reason {
        case NSUbiquitousKeyValueStoreAccountChange:
            syncRecords = []
            blockedUsers = []
            defaults.removeObject(forKey: storageKey)
            refreshFromICloud()
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            iCloudSyncState = .failed("iCloud 屏蔽名单已达到同步容量上限，新修改仅保存在本机。")
        case NSUbiquitousKeyValueStoreInitialSyncChange,
             NSUbiquitousKeyValueStoreServerChange:
            refreshFromICloud(
                reconcilesConflicts: reason == NSUbiquitousKeyValueStoreServerChange
            )
        default:
            iCloudSyncState = .failed("iCloud 返回了无法识别的同步状态，屏蔽操作仍会保存在本机。")
        }
    }

    func filtering(_ threads: [ForumThread]) -> [ForumThread] {
        threads.filter { !isBlocked(source: $0.source, username: $0.author) }
    }

    private func upsert(source: ForumSource, username: String, isBlocked: Bool) {
        let record = BlockedUserSyncRecord(
            source: source,
            username: username,
            isBlocked: isBlocked,
            updatedAt: .now
        )
        replaceLocalRecord(record)
        rebuildBlockedUsers()
        persistLocal()
        upload(record)
    }

    private func upload(_ record: BlockedUserSyncRecord) {
        guard let data = BlockedUserCloudCodec.encode(record) else {
            iCloudSyncState = .failed("屏蔽记录编码失败，新修改仅保存在本机。")
            return
        }
        let key = BlockedUserCloudCodec.key(for: record.id)
        let cloudRecordCount = cloudStore.dictionaryRepresentation.keys.lazy
            .filter { $0.hasPrefix(BlockedUserCloudCodec.keyPrefix) }
            .count
        guard cloudStore.data(forKey: key) != nil
                || cloudRecordCount < BlockedUserCloudCodec.maximumRecordCount else {
            iCloudSyncState = .failed("iCloud 屏蔽记录已达到安全上限，新修改仅保存在本机。")
            return
        }
        cloudStore.set(data, forKey: key)
        iCloudSyncState = .synced
    }

    private func replaceLocalRecord(_ record: BlockedUserSyncRecord) {
        syncRecords.removeAll { $0.id == record.id }
        syncRecords.append(record)
    }

    private func persistLocal() {
        guard let data = VersionedLocalSnapshotCodec.encode(syncRecords, version: schemaVersion) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private func rebuildBlockedUsers() {
        blockedUsers = syncRecords
            .filter(\.isBlocked)
            .map { BlockedForumUser(source: $0.source, username: $0.username) }
        sort()
    }

    private static func decodeRecords(_ data: Data?, version: Int) -> [BlockedUserSyncRecord] {
        guard case let .current(records) = VersionedLocalSnapshotCodec.decode(
            [BlockedUserSyncRecord].self,
            data: data,
            currentVersion: version
        ) else { return [] }
        return records
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
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    var isBlockableForumUsername: Bool {
        isUsefulForumValue && normalizedForumUsername != "未知作者"
    }
}
