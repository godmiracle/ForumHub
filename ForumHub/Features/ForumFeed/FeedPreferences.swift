import Foundation
import Observation

struct FeedFilterState: Equatable {
    var selectedChildChannelIDs: Set<Int> = []
    var showsPinnedThreads = true

    var activeCount: Int {
        selectedChildChannelIDs.count + (showsPinnedThreads ? 0 : 1)
    }

    var isActive: Bool { activeCount > 0 }
}

@MainActor
@Observable
final class FeedPreferencesStore {
    private struct Payload: Codable {
        let version: Int
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
        var selectedChildChannelIDs: [Int]
    }

    private let defaults: UserDefaults
    private let storageKey = "forum-feed-preferences-v2"
    private var payload: Payload

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        payload = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
            .flatMap { $0.version == 2 ? $0 : nil }
            ?? Payload(version: 2, sourceRecords: [], childRecords: [])
    }

    func preference(
        source: ForumSource,
        channelID: Int,
        validChildChannelIDs: Set<Int>
    ) -> (sortMode: FeedSortMode, filter: FeedFilterState) {
        let sourceRecord = payload.sourceRecords.first { $0.source == source }
        let childRecord = payload.childRecords.first { $0.source == source && $0.channelID == channelID }
        return (
            sourceRecord.flatMap { FeedSortMode(rawValue: $0.sortMode) } ?? .lastReply,
            FeedFilterState(
                selectedChildChannelIDs: Set(childRecord?.selectedChildChannelIDs ?? []).intersection(validChildChannelIDs),
                showsPinnedThreads: sourceRecord?.showsPinnedThreads ?? true
            )
        )
    }

    func save(
        source: ForumSource,
        channelID: Int,
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
            channelID: channelID,
            selectedChildChannelIDs: filter.selectedChildChannelIDs.sorted()
        )
        payload.sourceRecords.removeAll { $0.source == source }
        payload.sourceRecords.append(sourceRecord)
        payload.childRecords.removeAll { $0.source == source && $0.channelID == channelID }
        payload.childRecords.append(childRecord)
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
