import Foundation
import Observation

struct AuthoritativeChildForumDirectorySyncResult: Equatable {
    let isFirstBaseline: Bool
    let addedStableKeys: Set<String>
    let renamedStableKeys: Set<String>
    let removedStableKeys: Set<String>
    let removedChildren: [AuthoritativeChildForum]
    let selectedStableKeys: Set<String>
}

enum AuthoritativeChildForumDirectoryStoreError: Error, Equatable {
    case invalidDirectory
}

@MainActor
@Observable
final class AuthoritativeChildForumDirectoryStore {
    private struct Scope: Codable, Equatable {
        let source: ForumSource
        let parentID: Int
        let parentNativeKey: String

        init(parent: ForumChannel) {
            source = parent.source
            parentID = parent.id
            parentNativeKey = parent.nativeKey
        }
    }

    private struct PersistedChild: Codable, Equatable {
        let stableKey: String
        let title: String
        let channelID: Int
        let channelNativeKey: String

        init(_ child: AuthoritativeChildForum) {
            stableKey = child.stableKey
            title = child.title
            channelID = child.channel.id
            channelNativeKey = child.channel.nativeKey
        }

        func child(source: ForumSource) -> AuthoritativeChildForum {
            AuthoritativeChildForum(
                stableKey: stableKey,
                title: title,
                channel: ForumChannel(
                    id: channelID,
                    title: title,
                    source: source,
                    nativeKey: channelNativeKey
                )
            )
        }
    }

    private struct PersistedDirectory: Codable, Equatable {
        let parentTitle: String
        let children: [PersistedChild]

        init(_ directory: AuthoritativeChildForumDirectory) {
            parentTitle = directory.parent.title
            children = directory.children.map(PersistedChild.init)
        }

        func directory(for scope: Scope) -> AuthoritativeChildForumDirectory {
            AuthoritativeChildForumDirectory(
                parent: ForumChannel(
                    id: scope.parentID,
                    title: parentTitle,
                    source: scope.source,
                    nativeKey: scope.parentNativeKey
                ),
                children: children.map { $0.child(source: scope.source) }
            )
        }
    }

    private struct Record: Codable, Equatable {
        let scope: Scope
        var directory: PersistedDirectory
        var pendingNewStableKeys: [String]
        var pendingCancelledSelectedChildren: [PersistedChild]
    }

    private struct Payload: Codable {
        let version: Int
        var records: [Record]
    }

    private let defaults: UserDefaults
    private let storageKey = "nga-authoritative-child-forum-directories-v1"
    private var payload: Payload

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        payload = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
            .flatMap { $0.version == 1 ? $0 : nil }
            ?? Payload(version: 1, records: [])
    }

    func latestDirectory(for parent: ForumChannel) -> AuthoritativeChildForumDirectory? {
        let scope = Scope(parent: parent)
        return payload.records.first { $0.scope == scope }?.directory.directory(for: scope)
    }

    func pendingNewStableKeys(for parent: ForumChannel) -> Set<String> {
        let scope = Scope(parent: parent)
        return Set(payload.records.first { $0.scope == scope }?.pendingNewStableKeys ?? [])
    }

    func markPendingNewChildrenAsSeen(for parent: ForumChannel) {
        updateRecord(for: parent) { record in
            record.pendingNewStableKeys = []
        }
    }

    func consumeCancelledSelectedChildren(for parent: ForumChannel) -> [AuthoritativeChildForum] {
        let scope = Scope(parent: parent)
        guard let record = payload.records.first(where: { $0.scope == scope }) else { return [] }
        let cancelledChildren = record.pendingCancelledSelectedChildren.map { $0.child(source: scope.source) }
        updateRecord(for: parent) { record in
            record.pendingCancelledSelectedChildren = []
        }
        return cancelledChildren
    }

    func synchronize(
        _ directory: AuthoritativeChildForumDirectory,
        selectedStableKeys: Set<String>
    ) throws -> AuthoritativeChildForumDirectorySyncResult {
        let scope = Scope(parent: directory.parent)
        try validate(directory, for: scope)

        let updatedDirectory = PersistedDirectory(directory)
        let previousIndex = payload.records.firstIndex { $0.scope == scope }
        let previous = previousIndex.map { payload.records[$0] }
        let previousChildren = Dictionary(
            uniqueKeysWithValues: (previous?.directory.children ?? []).map { ($0.stableKey, $0) }
        )
        let currentChildren = Dictionary(
            uniqueKeysWithValues: updatedDirectory.children.map { ($0.stableKey, $0) }
        )
        let currentStableKeys = Set(currentChildren.keys)

        let isFirstBaseline = previous == nil
        let addedStableKeys = isFirstBaseline
            ? Set<String>()
            : currentStableKeys.subtracting(previousChildren.keys)
        let removedStableKeys = isFirstBaseline
            ? Set<String>()
            : Set(previousChildren.keys).subtracting(currentStableKeys)
        let renamedStableKeys = Set(currentChildren.keys).intersection(previousChildren.keys).filter {
            currentChildren[$0]?.title != previousChildren[$0]?.title
        }
        let pendingNewStableKeys = isFirstBaseline
            ? Set<String>()
            : Set(previous?.pendingNewStableKeys ?? [])
                .union(addedStableKeys)
                .intersection(currentStableKeys)
        let cancelledSelectedChildren = removedStableKeys
            .intersection(selectedStableKeys)
            .compactMap { previousChildren[$0] }
        var pendingCancelledSelectedChildren = previous?.pendingCancelledSelectedChildren ?? []
        pendingCancelledSelectedChildren.removeAll { currentStableKeys.contains($0.stableKey) }
        for child in cancelledSelectedChildren where !pendingCancelledSelectedChildren.contains(where: { $0.stableKey == child.stableKey }) {
            pendingCancelledSelectedChildren.append(child)
        }

        let updatedRecord = Record(
            scope: scope,
            directory: updatedDirectory,
            pendingNewStableKeys: pendingNewStableKeys.sorted(),
            pendingCancelledSelectedChildren: pendingCancelledSelectedChildren
        )
        var updatedPayload = payload
        if let previousIndex {
            updatedPayload.records[previousIndex] = updatedRecord
        } else {
            updatedPayload.records.append(updatedRecord)
        }
        persist(updatedPayload)
        payload = updatedPayload

        return AuthoritativeChildForumDirectorySyncResult(
            isFirstBaseline: isFirstBaseline,
            addedStableKeys: addedStableKeys,
            renamedStableKeys: renamedStableKeys,
            removedStableKeys: removedStableKeys,
            removedChildren: removedStableKeys
                .compactMap { previousChildren[$0]?.child(source: scope.source) }
                .sorted { $0.stableKey < $1.stableKey },
            selectedStableKeys: selectedStableKeys.intersection(currentStableKeys)
        )
    }

    private func validate(
        _ directory: AuthoritativeChildForumDirectory,
        for scope: Scope
    ) throws {
        guard directory.parent.source == scope.source,
              directory.parent.id == scope.parentID,
              directory.parent.nativeKey == scope.parentNativeKey,
              !scope.parentNativeKey.isEmpty
        else {
            throw AuthoritativeChildForumDirectoryStoreError.invalidDirectory
        }

        var stableKeys = Set<String>()
        for child in directory.children {
            guard child.channel.source == scope.source,
                  child.channel.nativeKey == child.stableKey,
                  !child.stableKey.isEmpty,
                  !child.title.isEmpty,
                  stableKeys.insert(child.stableKey).inserted
            else {
                throw AuthoritativeChildForumDirectoryStoreError.invalidDirectory
            }
        }
    }

    private func persist(_ payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func updateRecord(for parent: ForumChannel, update: (inout Record) -> Void) {
        let scope = Scope(parent: parent)
        guard let index = payload.records.firstIndex(where: { $0.scope == scope }) else { return }
        var updatedPayload = payload
        update(&updatedPayload.records[index])
        persist(updatedPayload)
        payload = updatedPayload
    }
}
