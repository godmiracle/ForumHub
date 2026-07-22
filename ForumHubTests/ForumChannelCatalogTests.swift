import Foundation
import Testing
@testable import ForumHub

@MainActor
struct ForumChannelCatalogTests {
    @Test func canonicalKeysPreserveNGAForumTargetKind() {
        let legacyFID = ForumChannel(id: 42, title: "普通 fid")
        let explicitFID = ForumChannel(id: 42, title: "权威 fid", nativeKey: "fid:42")
        let explicitSTID = ForumChannel(id: 42, title: "权威 stid", nativeKey: "stid:42")
        let v2ex = ForumChannel(id: 42, title: "V2EX", source: .v2ex, nativeKey: "swift")

        #expect(legacyFID.canonicalKey == "nga:fid:42")
        #expect(explicitFID.canonicalKey == legacyFID.canonicalKey)
        #expect(explicitSTID.canonicalKey == "nga:stid:42")
        #expect(explicitSTID.canonicalKey != explicitFID.canonicalKey)
        #expect(v2ex.canonicalKey == "v2ex:swift")
    }

    @Test func catalogCombinesAndDeduplicatesOrdinaryChannelsWithAuthoritativeChildren() {
        let ordinary = [
            ForumChannel.defaultForum,
            ForumChannel(id: 570, title: "旧标题")
        ]
        let directory = AuthoritativeChildForumDirectory(
            parent: .defaultForum,
            children: [
                AuthoritativeChildForum(
                    stableKey: "fid:570",
                    title: "优惠信息 购物指南",
                    channel: ForumChannel(id: 570, title: "优惠信息 购物指南", nativeKey: "fid:570")
                ),
                AuthoritativeChildForum(
                    stableKey: "stid:47206901",
                    title: "[股市]技术分析",
                    channel: ForumChannel(id: 47_206_901, title: "[股市]技术分析", nativeKey: "stid:47206901")
                )
            ]
        )

        let catalog = ForumChannelCatalog.build(
            source: .nga,
            channels: ordinary,
            authoritativeDirectory: directory
        )

        #expect(catalog.items.count == 3)
        #expect(catalog.items.filter { $0.id == "nga:fid:570" }.count == 1)
        #expect(catalog.items.first { $0.id == "nga:fid:570" }?.title == "优惠信息 购物指南")
        #expect(catalog.items.first { $0.id == "nga:stid:47206901" }?.contextTitle == "网事杂谈 › 子版")
        #expect(catalog.items.first { $0.id == "nga:stid:47206901" }?.matches("技术分析") == true)
        #expect(catalog.items.first { $0.id == "nga:stid:47206901" }?.matches("stid:47206901") == true)
    }

    @Test func catalogKeepsOtherSourcesIsolatedWithoutInventedHierarchy() {
        let v2ex = ForumChannel(id: 1, title: "Swift", source: .v2ex, nativeKey: "swift")
        let ngaDirectory = AuthoritativeChildForumDirectory(
            parent: .defaultForum,
            children: [
                AuthoritativeChildForum(
                    stableKey: "stid:1",
                    title: "NGA 子版",
                    channel: ForumChannel(id: 1, title: "NGA 子版", nativeKey: "stid:1")
                )
            ]
        )

        let catalog = ForumChannelCatalog.build(
            source: .v2ex,
            channels: [v2ex],
            authoritativeDirectory: ngaDirectory
        )

        #expect(catalog.items == [ForumChannelCatalogItem(channel: v2ex, kind: .standard)])
        #expect(!catalog.hasConfirmedAuthoritativeChildren)
        #expect(catalog.authoritativeChildren.isEmpty)
    }

    @Test func subscriptionMigrationUsesNewKeysWithoutOverwritingRollbackSnapshot() throws {
        let suiteName = "ForumChannelCatalogTests-migration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyKeys = ["nga:-7", "nga:706", "v2ex:swift", "nga:bad"]
        let legacyOrder = ["v2ex:swift", "nga:706", "nga:-7"]
        defaults.set(legacyKeys, forKey: "subscribed-forum-channel-keys-v3")
        defaults.set(legacyOrder, forKey: "subscribed-forum-channel-order-v1")

        let store = ForumSubscriptionStore(defaults: defaults)

        #expect(store.subscribedChannelKeys == ["nga:fid:-7", "nga:fid:706", "v2ex:swift"])
        #expect(store.orderedChannelKeys == ["v2ex:swift", "nga:fid:706", "nga:fid:-7"])
        #expect(defaults.stringArray(forKey: "subscribed-forum-channel-keys-v3") == legacyKeys)
        #expect(defaults.stringArray(forKey: "subscribed-forum-channel-order-v1") == legacyOrder)
        #expect(defaults.stringArray(forKey: "subscribed-forum-channel-keys-v4") != nil)
        #expect(defaults.integer(forKey: "forum-subscriptions-schema-version") == 2)
    }

    @Test func defaultSubscriptionDoesNotConfuseSameValueSTIDWithFID() throws {
        let suiteName = "ForumChannelCatalogTests-default-kind-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fid = ForumChannel(id: 706, title: "大时代")
        let stid = ForumChannel(id: 706, title: "同值主题子版", nativeKey: "stid:706")
        let store = ForumSubscriptionStore(defaults: defaults)

        store.restoreDefaults(for: [fid, stid])

        #expect(store.isSubscribed(fid))
        #expect(!store.isSubscribed(stid))
    }

    @Test func authoritativeChildSubscriptionRestoresAndCancellationRemovesOnlyHomeState() throws {
        let suiteName = "ForumChannelCatalogTests-child-subscription-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let child = ForumChannel(
            id: 47_206_901,
            title: "[股市]技术分析",
            nativeKey: "stid:47206901"
        )
        let allChannels = [ForumChannel.defaultForum, child]

        let store = ForumSubscriptionStore(defaults: defaults)
        store.setSubscribed(true, for: child)
        let restored = ForumSubscriptionStore(defaults: defaults)

        #expect(restored.isSubscribed(child))
        #expect(restored.visibleChannels(from: allChannels).contains { $0.canonicalKey == child.canonicalKey })
        #expect(restored.subscribedChannelKeys.contains("nga:stid:47206901"))

        let removed = restored.removeCancelledAuthoritativeChannels([child])
        #expect(removed == [child])
        #expect(!restored.isSubscribed(child))
        #expect(restored.isSubscribed(.defaultForum))
    }

    @Test func completeDirectoryCancellationReturnsRemovedBrowseTargetsForIndependentConsumers() throws {
        let suiteName = "ForumChannelCatalogTests-directory-cancellation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let child = AuthoritativeChildForum(
            stableKey: "stid:47206901",
            title: "[股市]技术分析",
            channel: ForumChannel(id: 47_206_901, title: "[股市]技术分析", nativeKey: "stid:47206901")
        )
        let store = AuthoritativeChildForumDirectoryStore(defaults: defaults)
        _ = try store.synchronize(
            AuthoritativeChildForumDirectory(parent: .defaultForum, children: [child]),
            selectedStableKeys: [child.stableKey]
        )

        let result = try store.synchronize(
            AuthoritativeChildForumDirectory(parent: .defaultForum, children: []),
            selectedStableKeys: [child.stableKey]
        )

        #expect(result.removedStableKeys == [child.stableKey])
        #expect(result.removedChildren == [child])
        #expect(result.selectedStableKeys.isEmpty)
    }

    @Test func homeSubscriptionAndWangshiFilterPreferencesRemainIndependent() throws {
        let suiteName = "ForumChannelCatalogTests-preference-isolation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let child = AuthoritativeChildForum(
            stableKey: "stid:47206901",
            title: "[股市]技术分析",
            channel: ForumChannel(id: 47_206_901, title: "[股市]技术分析", nativeKey: "stid:47206901")
        )
        let directory = AuthoritativeChildForumDirectory(parent: .defaultForum, children: [child])
        let subscriptions = ForumSubscriptionStore(defaults: defaults)
        let preferences = FeedPreferencesStore(defaults: defaults)
        preferences.save(
            source: .nga,
            parent: .defaultForum,
            sortMode: .lastReply,
            filter: FeedFilterState(selectedChildForumKeys: [child.stableKey], showsPinnedThreads: true)
        )

        subscriptions.setSubscribed(true, for: child.channel)
        #expect(
            preferences.preference(source: .nga, parent: .defaultForum, directory: directory)
                .filter.selectedChildForumKeys == [child.stableKey]
        )

        subscriptions.setSubscribed(false, for: child.channel)
        #expect(
            preferences.preference(source: .nga, parent: .defaultForum, directory: directory)
                .filter.selectedChildForumKeys == [child.stableKey]
        )

        preferences.removeCancelledAuthoritativeChildForumKeys(
            [child.stableKey],
            source: .nga,
            parent: .defaultForum
        )
        #expect(
            preferences.preference(source: .nga, parent: .defaultForum, directory: directory)
                .filter.selectedChildForumKeys.isEmpty
        )
    }
}
