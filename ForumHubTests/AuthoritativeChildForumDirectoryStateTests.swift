import Foundation
import Testing
@testable import ForumHub

@MainActor
struct AuthoritativeChildForumDirectoryStateTests {
    @Test func firstCompleteSyncEstablishesAPersistedBaselineWithoutMarkingExistingChildrenAsNew() throws {
        let suiteName = "AuthoritativeChildForumDirectoryStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let parent = ForumChannel.defaultForum
        let directory = makeDirectory(
            parent: parent,
            children: [
                child(stableKey: "fid:570", title: "优惠信息", id: 570),
                child(stableKey: "stid:47206901", title: "技术分析", id: 47_206_901)
            ]
        )
        let store = AuthoritativeChildForumDirectoryStore(defaults: defaults)

        let result = try store.synchronize(directory, selectedStableKeys: ["fid:570"])

        #expect(result.isFirstBaseline)
        #expect(result.addedStableKeys.isEmpty)
        #expect(result.renamedStableKeys.isEmpty)
        #expect(result.removedStableKeys.isEmpty)
        #expect(result.selectedStableKeys == ["fid:570"])
        #expect(store.latestDirectory(for: parent) == directory)
        #expect(store.pendingNewStableKeys(for: parent).isEmpty)

        let restoredStore = AuthoritativeChildForumDirectoryStore(defaults: defaults)
        #expect(restoredStore.latestDirectory(for: parent) == directory)
    }

    @Test func laterCompleteSyncTracksAddRenameAndCancellationWithoutChangingDefaults() throws {
        let suiteName = "AuthoritativeChildForumDirectoryStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let parent = ForumChannel.defaultForum
        let kept = child(stableKey: "fid:570", title: "优惠信息", id: 570)
        let cancelled = child(stableKey: "fid:706", title: "旧子版", id: 706)
        let store = AuthoritativeChildForumDirectoryStore(defaults: defaults)
        _ = try store.synchronize(
            makeDirectory(parent: parent, children: [kept, cancelled]),
            selectedStableKeys: [kept.stableKey, cancelled.stableKey]
        )

        let renamed = child(stableKey: "fid:570", title: "优惠活动", id: 570)
        let added = child(stableKey: "stid:47206901", title: "技术分析", id: 47_206_901)
        let result = try store.synchronize(
            makeDirectory(parent: parent, children: [renamed, added]),
            selectedStableKeys: [kept.stableKey, cancelled.stableKey]
        )

        #expect(!result.isFirstBaseline)
        #expect(result.addedStableKeys == [added.stableKey])
        #expect(result.renamedStableKeys == [renamed.stableKey])
        #expect(result.removedStableKeys == [cancelled.stableKey])
        #expect(result.selectedStableKeys == [renamed.stableKey])
        #expect(store.pendingNewStableKeys(for: parent) == [added.stableKey])
        #expect(store.consumeCancelledSelectedChildren(for: parent) == [cancelled])
        #expect(store.consumeCancelledSelectedChildren(for: parent).isEmpty)

        store.markPendingNewChildrenAsSeen(for: parent)
        #expect(store.pendingNewStableKeys(for: parent).isEmpty)
    }

    @Test func rejectsIncompleteDirectoryWithoutReplacingTheLastConfirmedSnapshot() throws {
        let suiteName = "AuthoritativeChildForumDirectoryStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let parent = ForumChannel.defaultForum
        let confirmed = makeDirectory(
            parent: parent,
            children: [child(stableKey: "fid:570", title: "优惠信息", id: 570)]
        )
        let incomplete = makeDirectory(
            parent: parent,
            children: [
                child(stableKey: "fid:570", title: "优惠信息", id: 570),
                AuthoritativeChildForum(
                    stableKey: "fid:570",
                    title: "重复且不完整的记录",
                    channel: ForumChannel(id: 571, title: "重复且不完整的记录", nativeKey: "fid:570")
                )
            ]
        )
        let store = AuthoritativeChildForumDirectoryStore(defaults: defaults)
        _ = try store.synchronize(confirmed, selectedStableKeys: ["fid:570"])

        #expect(throws: AuthoritativeChildForumDirectoryStoreError.invalidDirectory) {
            try store.synchronize(incomplete, selectedStableKeys: ["fid:570"])
        }

        #expect(store.latestDirectory(for: parent) == confirmed)
    }

    @Test func snapshotsAreIsolatedBySourceAndParentForum() throws {
        let suiteName = "AuthoritativeChildForumDirectoryStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let wangshi = ForumChannel.defaultForum
        let otherParent = ForumChannel(id: 706, title: "大时代")
        let sameIDFromAnotherSource = ForumChannel(
            id: -7,
            title: "其他来源的同 ID 父版",
            source: .v2ex,
            nativeKey: "other-source-parent"
        )
        let store = AuthoritativeChildForumDirectoryStore(defaults: defaults)
        let wangshiDirectory = makeDirectory(
            parent: wangshi,
            children: [child(stableKey: "fid:570", title: "优惠信息", id: 570)]
        )
        let otherDirectory = makeDirectory(
            parent: otherParent,
            children: [child(stableKey: "fid:571", title: "另一个父版的子版", id: 571)]
        )
        let otherSourceDirectory = makeDirectory(
            parent: sameIDFromAnotherSource,
            children: [child(
                stableKey: "node:570",
                title: "其他来源的同 ID 子版",
                id: 570,
                source: .v2ex
            )]
        )

        _ = try store.synchronize(wangshiDirectory, selectedStableKeys: [])
        _ = try store.synchronize(otherDirectory, selectedStableKeys: [])
        _ = try store.synchronize(otherSourceDirectory, selectedStableKeys: [])

        #expect(store.latestDirectory(for: wangshi) == wangshiDirectory)
        #expect(store.latestDirectory(for: otherParent) == otherDirectory)
        #expect(store.latestDirectory(for: sameIDFromAnotherSource) == otherSourceDirectory)
    }

    @Test func legacyIDSelectionWaitsForAnAuthoritativeDirectoryAndMigratesOnlyUniqueTargets() throws {
        let suiteName = "AuthoritativeChildForumDirectoryStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyPayload = #"""
        {
          "version": 2,
          "sourceRecords": [{ "source": "nga", "sortMode": "latestPost", "showsPinnedThreads": true }],
          "childRecords": [{ "source": "nga", "channelID": -7, "selectedChildChannelIDs": [10, 20, 999] }]
        }
        """#
        defaults.set(Data(legacyPayload.utf8), forKey: "forum-feed-preferences-v2")

        let parent = ForumChannel.defaultForum
        let preferences = FeedPreferencesStore(defaults: defaults)
        #expect(preferences.hasDeferredChildForumSelectionMigration(source: .nga, parent: parent))

        let directory = makeDirectory(
            parent: parent,
            children: [
                child(stableKey: "fid:10", title: "普通子版", id: 10),
                child(stableKey: "stid:10", title: "主题子版", id: 10),
                child(stableKey: "fid:20", title: "唯一可迁移子版", id: 20)
            ]
        )
        let selectedKeys = preferences.authoritativeChildForumKeys(
            source: .nga,
            parent: parent,
            directory: directory
        )

        #expect(selectedKeys == ["fid:20"])
        #expect(!preferences.hasDeferredChildForumSelectionMigration(source: .nga, parent: parent))

        let restoredPreferences = FeedPreferencesStore(defaults: defaults)
        #expect(restoredPreferences.authoritativeChildForumKeys(
            source: .nga,
            parent: parent,
            directory: directory
        ) == ["fid:20"])
    }

    private func makeDirectory(
        parent: ForumChannel,
        children: [AuthoritativeChildForum]
    ) -> AuthoritativeChildForumDirectory {
        AuthoritativeChildForumDirectory(parent: parent, children: children)
    }

    private func child(
        stableKey: String,
        title: String,
        id: Int,
        source: ForumSource = .nga
    ) -> AuthoritativeChildForum {
        AuthoritativeChildForum(
            stableKey: stableKey,
            title: title,
            channel: ForumChannel(id: id, title: title, source: source, nativeKey: stableKey)
        )
    }
}
