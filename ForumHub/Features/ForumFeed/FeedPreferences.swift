import Foundation
import Observation

struct FeedFilterState: Equatable {
    var selectedChildForumKeys: Set<String> = []
    var showsPinnedThreads = true

    var activeCount: Int {
        selectedChildForumKeys.count + (showsPinnedThreads ? 0 : 1)
    }

    var isActive: Bool { activeCount > 0 }
}

struct ChildForumFilterPresentation {
    static let searchThreshold = 12

    let children: [AuthoritativeChildForum]
    let selectedStableKeys: Set<String>
    let pendingNewStableKeys: Set<String>
    let searchText: String

    private var authoritativeStableKeys: Set<String> {
        Set(children.map(\.stableKey))
    }

    var selectedCount: Int {
        selectedStableKeys.intersection(authoritativeStableKeys).count
    }

    var pendingNewCount: Int {
        pendingNewStableKeys.intersection(authoritativeStableKeys).count
    }

    var needsSearch: Bool {
        children.count >= Self.searchThreshold
    }

    var filteredChildren: [AuthoritativeChildForum] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return children }
        return children.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.stableKey.localizedCaseInsensitiveContains(query)
        }
    }

    func isNew(_ stableKey: String) -> Bool {
        authoritativeStableKeys.contains(stableKey) && pendingNewStableKeys.contains(stableKey)
    }
}

struct FeedChildForumStatus: Equatable {
    var isApplicable = false
    var hasConfirmedDirectory = false
    var pendingNewStableKeys: Set<String> = []
    var cancelledSelectionNotice: String?
    var failedChildForumCount = 0

    var directoryUnavailableMessage: String? {
        guard isApplicable, !hasConfirmedDirectory else { return nil }
        return "子版目录暂不可用，请稍后重试。"
    }

    var partialFailureMessage: String? {
        guard failedChildForumCount > 0 else { return nil }
        return "部分子版暂未加载，可重试。"
    }

}

@MainActor
@Observable
final class FeedPreferencesStore {
    private struct Payload: Codable {
        var version: Int
        var sourceRecords: [SourceRecord]
        var childRecords: [ChildRecord]
    }

    private struct SourceRecord: Codable {
        let source: ForumSource
        var sortMode: String
        var showsPinnedThreads: Bool
    }

    private struct ChildRecord: Codable {
        let source: ForumSource
        let channelID: Int
        var parentNativeKey: String?
        var selectedChildForumKeys: [String]?
        var legacySelectedChildChannelIDs: [Int]?

        private enum CodingKeys: String, CodingKey {
            case source
            case channelID
            case parentNativeKey
            case selectedChildForumKeys
            case legacySelectedChildChannelIDs
            case selectedChildChannelIDs
        }

        init(
            source: ForumSource,
            channelID: Int,
            parentNativeKey: String? = nil,
            selectedChildForumKeys: [String]? = nil,
            legacySelectedChildChannelIDs: [Int]? = nil
        ) {
            self.source = source
            self.channelID = channelID
            self.parentNativeKey = parentNativeKey
            self.selectedChildForumKeys = selectedChildForumKeys
            self.legacySelectedChildChannelIDs = legacySelectedChildChannelIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            source = try container.decode(ForumSource.self, forKey: .source)
            channelID = try container.decode(Int.self, forKey: .channelID)
            parentNativeKey = try container.decodeIfPresent(String.self, forKey: .parentNativeKey)
            selectedChildForumKeys = try container.decodeIfPresent([String].self, forKey: .selectedChildForumKeys)
            legacySelectedChildChannelIDs = try container.decodeIfPresent([Int].self, forKey: .legacySelectedChildChannelIDs)
                ?? container.decodeIfPresent([Int].self, forKey: .selectedChildChannelIDs)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(source, forKey: .source)
            try container.encode(channelID, forKey: .channelID)
            try container.encodeIfPresent(parentNativeKey, forKey: .parentNativeKey)
            try container.encodeIfPresent(selectedChildForumKeys, forKey: .selectedChildForumKeys)
            try container.encodeIfPresent(legacySelectedChildChannelIDs, forKey: .legacySelectedChildChannelIDs)
        }
    }

    private let defaults: UserDefaults
    private let storageKey = "forum-feed-preferences-v2"
    private var payload: Payload

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedPayload = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
        if var savedPayload, savedPayload.version == 2 {
            savedPayload.version = 3
            payload = savedPayload
        } else if let savedPayload, savedPayload.version == 3 {
            payload = savedPayload
        } else {
            payload = Payload(version: 3, sourceRecords: [], childRecords: [])
        }
    }

    func preference(
        source: ForumSource,
        parent: ForumChannel,
        directory: AuthoritativeChildForumDirectory?
    ) -> (sortMode: FeedSortMode, filter: FeedFilterState) {
        let sourceRecord = payload.sourceRecords.first { $0.source == source }
        let selectedChildForumKeys = directory.map {
            authoritativeChildForumKeys(source: source, parent: parent, directory: $0)
        } ?? []
        return (
            sourceRecord.flatMap { FeedSortMode(rawValue: $0.sortMode) } ?? .lastReply,
            FeedFilterState(
                selectedChildForumKeys: selectedChildForumKeys,
                showsPinnedThreads: sourceRecord?.showsPinnedThreads ?? true
            )
        )
    }

    func hasDeferredChildForumSelectionMigration(source: ForumSource, parent: ForumChannel) -> Bool {
        guard let record = childRecord(source: source, parent: parent) else { return false }
        return record.selectedChildForumKeys == nil && !(record.legacySelectedChildChannelIDs ?? []).isEmpty
    }

    func authoritativeChildForumKeys(
        source: ForumSource,
        parent: ForumChannel,
        directory: AuthoritativeChildForumDirectory
    ) -> Set<String> {
        guard source == parent.source,
              directory.parent.source == parent.source,
              directory.parent.id == parent.id,
              directory.parent.nativeKey == parent.nativeKey,
              let index = childRecordIndex(source: source, parent: parent)
        else {
            return []
        }

        let validKeys = Set(directory.children.map(\.stableKey))
        var updatedPayload = payload
        var record = updatedPayload.childRecords[index]
        let selectedKeys: Set<String>
        if let savedKeys = record.selectedChildForumKeys {
            selectedKeys = Set(savedKeys).intersection(validKeys)
        } else {
            let childrenByID = Dictionary(grouping: directory.children, by: { $0.channel.id })
            selectedKeys = Set(record.legacySelectedChildChannelIDs?.compactMap { id in
                guard let matches = childrenByID[id], matches.count == 1 else { return nil }
                return matches[0].stableKey
            } ?? [])
        }

        record.parentNativeKey = parent.nativeKey
        record.selectedChildForumKeys = selectedKeys.sorted()
        record.legacySelectedChildChannelIDs = nil
        updatedPayload.childRecords[index] = record
        persist(updatedPayload)
        payload = updatedPayload
        return selectedKeys
    }

    func save(
        source: ForumSource,
        parent: ForumChannel,
        sortMode: FeedSortMode,
        filter: FeedFilterState
    ) {
        let sourceRecord = SourceRecord(
            source: source,
            sortMode: sortMode.rawValue,
            showsPinnedThreads: filter.showsPinnedThreads
        )
        let childRecord = ChildRecord(
            source: source,
            channelID: parent.id,
            parentNativeKey: parent.nativeKey,
            selectedChildForumKeys: filter.selectedChildForumKeys.sorted(),
            legacySelectedChildChannelIDs: nil
        )
        payload.sourceRecords.removeAll { $0.source == source }
        payload.sourceRecords.append(sourceRecord)
        payload.childRecords.removeAll {
            $0.source == source
                && $0.channelID == parent.id
                && ($0.parentNativeKey == nil || $0.parentNativeKey == parent.nativeKey)
        }
        payload.childRecords.append(childRecord)
        persist(payload)
    }

    func removeCancelledAuthoritativeChildForumKeys(
        _ stableKeys: Set<String>,
        source: ForumSource,
        parent: ForumChannel
    ) {
        guard !stableKeys.isEmpty,
              let index = childRecordIndex(source: source, parent: parent)
        else { return }

        var updatedPayload = payload
        var record = updatedPayload.childRecords[index]
        if let selectedKeys = record.selectedChildForumKeys {
            record.selectedChildForumKeys = Set(selectedKeys).subtracting(stableKeys).sorted()
        }
        if let legacyIDs = record.legacySelectedChildChannelIDs {
            let removedIDs = Set(stableKeys.compactMap { stableKey -> Int? in
                if stableKey.hasPrefix("fid:") { return Int(stableKey.dropFirst(4)) }
                if stableKey.hasPrefix("stid:") { return Int(stableKey.dropFirst(5)) }
                return nil
            })
            record.legacySelectedChildChannelIDs = legacyIDs.filter { !removedIDs.contains($0) }
        }
        updatedPayload.childRecords[index] = record
        persist(updatedPayload)
        payload = updatedPayload
    }

    private func childRecord(source: ForumSource, parent: ForumChannel) -> ChildRecord? {
        guard parent.source == source else { return nil }
        return payload.childRecords.first {
            $0.source == source
                && $0.channelID == parent.id
                && ($0.parentNativeKey == nil || $0.parentNativeKey == parent.nativeKey)
        }
    }

    private func childRecordIndex(source: ForumSource, parent: ForumChannel) -> Int? {
        guard parent.source == source else { return nil }
        return payload.childRecords.firstIndex {
            $0.source == source
                && $0.channelID == parent.id
                && ($0.parentNativeKey == nil || $0.parentNativeKey == parent.nativeKey)
        }
    }

    private func persist(_ payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
