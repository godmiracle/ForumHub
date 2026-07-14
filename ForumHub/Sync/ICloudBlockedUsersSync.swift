import CryptoKit
import Foundation

@MainActor
protocol ICloudKeyValueStoring: AnyObject {
    var dictionaryRepresentation: [String: Any] { get }
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult
    func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: ICloudKeyValueStoring {}

enum ICloudBlockedUsersSyncState: Equatable {
    case syncing
    case synced
    case failed(String)

    var message: String {
        switch self {
        case .syncing:
            return "正在与 iCloud 合并屏蔽名单"
        case .synced:
            return "屏蔽名单已连接 iCloud"
        case let .failed(message):
            return message
        }
    }
}

struct BlockedUserSyncRecord: Codable, Equatable, Identifiable {
    let source: ForumSource
    let username: String
    let isBlocked: Bool
    let updatedAt: Date

    var id: String {
        "\(source.rawValue):\(username.normalizedForumUsername)"
    }
}

enum BlockedUserCloudCodec {
    static let keyPrefix = "blocked-forum-user-v2."
    static let maximumRecordCount = 900

    static func key(for recordID: String) -> String {
        let digest = SHA256.hash(data: Data(recordID.utf8))
        return keyPrefix + digest.map { String(format: "%02x", $0) }.joined()
    }

    static func records(in values: [String: Any]) -> [BlockedUserSyncRecord] {
        values.compactMap { key, value in
            guard key.hasPrefix(keyPrefix), let data = value as? Data else { return nil }
            return try? JSONDecoder().decode(BlockedUserSyncRecord.self, from: data)
        }
    }

    static func encode(_ record: BlockedUserSyncRecord) -> Data? {
        try? JSONEncoder().encode(record)
    }
}

enum BlockedUserSyncMerge {
    static func merge(
        _ local: [BlockedUserSyncRecord],
        _ remote: [BlockedUserSyncRecord]
    ) -> [BlockedUserSyncRecord] {
        var recordsByID: [String: BlockedUserSyncRecord] = [:]
        for record in local + remote {
            guard let current = recordsByID[record.id] else {
                recordsByID[record.id] = record
                continue
            }
            if record.updatedAt > current.updatedAt {
                recordsByID[record.id] = record
            } else if record.updatedAt == current.updatedAt, !record.isBlocked {
                recordsByID[record.id] = record
            }
        }
        return recordsByID.values.sorted { $0.id < $1.id }
    }
}
