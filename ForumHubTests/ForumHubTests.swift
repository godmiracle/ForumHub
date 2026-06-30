import Foundation
import Testing
import UIKit
@testable import ForumHub

@MainActor
struct ForumHubTests {

    @Test func parserExtractsSimpleThreadList() async throws {
        let json = """
        {
          "items": [
            {
              "tid": 1001,
              "subject": "第一条主题",
              "author": "CJ",
              "replies": 12,
              "views": 233,
              "lastpost": "2026-06-17 12:00"
            }
          ]
        }
        """.data(using: .utf8)!

        let payload = ForumPayloadParser.parse(data: json, fallbackText: "", fid: 722)

        #expect(payload?.forum.id == 722)
        #expect(payload?.threads.count == 1)
        #expect(payload?.threads.first?.title == "第一条主题")
        #expect(payload?.threads.first?.replyCount == 12)
    }

    @Test func parserExtractsRealPostListShape() throws {
        let bundle = Bundle(for: FixtureLocator.self)
        let fixtureURL = try #require(
            bundle.url(forResource: "post-list", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "post-list", withExtension: "json")
        )
        let data = try Data(contentsOf: fixtureURL)

        let thread = try #require(ThreadDetailParser.parse(
            data: data,
            fallbackText: String(decoding: data, as: UTF8.self),
            tid: 47004582
        ))

        #expect(thread.title == "真实帖子标题")
        #expect(thread.author == "首楼作者")
        #expect(thread.body == "首楼内容\n第二行")
        #expect(thread.replies.count == 1)
        #expect(thread.replies.first?.author == "回复作者")
        #expect(thread.authorAvatarURL?.absoluteString.contains("uid=60459868") == true)
        #expect(thread.replies.first?.avatarURL?.absoluteString.contains("uid=66728361") == true)
    }

    @Test func contentParserSeparatesTextAndImages() throws {
        let content = """
        第一段正文
        [图片] https://img.nga.178.com/attachments/mon_202606/18/example-a.jpg
        第二段正文
        [图片] https://img.nga.178.com/attachments/mon_202606/18/example-b.webp
        """

        let blocks = ForumContentParser.parse(content)

        #expect(blocks.count == 4)
        #expect(blocks[0].content == .text("第一段正文"))
        #expect(blocks[1].content == .image(try #require(URL(string: "https://img.nga.178.com/attachments/mon_202606/18/example-a.jpg"))))
        #expect(blocks[2].content == .text("第二段正文"))
        #expect(blocks[3].content == .image(try #require(URL(string: "https://img.nga.178.com/attachments/mon_202606/18/example-b.webp"))))
    }

    @Test func forumSubscriptionsDefaultFilterAndPersist() throws {
        let suiteName = "ForumHubTests.forum-subscriptions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let channels = [
            ForumChannel(id: -7_955_747, title: "晴风村"),
            ForumChannel(id: -7, title: "网事杂谈"),
            ForumChannel(id: 436, title: "消费电子"),
            ForumChannel(id: 706, title: "大时代")
        ]
        let subscriptions = ForumSubscriptionStore(defaults: defaults)

        #expect(subscriptions.visibleChannels(from: channels).map(\.id) == [-7, 706, -7_955_747])

        subscriptions.setSubscribed(true, for: channels[2])
        let restored = ForumSubscriptionStore(defaults: defaults)

        #expect(restored.visibleChannels(from: channels).map(\.id) == [-7, 706, -7_955_747, 436])
    }

    @Test func forumSubscriptionsMigrateLegacyDefaults() throws {
        let suiteName = "ForumHubTests.forum-subscriptions-migration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([722, 7, 510, 436], forKey: "subscribed-forum-channel-ids")

        let subscriptions = ForumSubscriptionStore(defaults: defaults)

        #expect(subscriptions.subscribedIDs == [-7, 706, -7_955_747, 436])
    }

    @Test func forumSubscriptionsAreScopedBySource() throws {
        let suiteName = "ForumHubTests.forum-subscriptions-sources.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let ngaChannel = ForumChannel(id: 42, title: "NGA 42")
        let v2exChannel = ForumChannel(id: 42, title: "V2EX 42", source: .v2ex, nativeKey: "swift")
        let store = ForumSubscriptionStore(defaults: defaults)

        store.setSubscribed(true, for: ngaChannel)
        #expect(store.isSubscribed(ngaChannel))
        #expect(!store.isSubscribed(v2exChannel))

        store.prepareDefaults(for: [v2exChannel])
        #expect(store.isSubscribed(v2exChannel))
    }

    @Test func browsingHistoryDeduplicatesAndPersistsRecentThreads() throws {
        let suiteName = "ForumHubTests.browsing-history.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BrowsingHistoryStore(defaults: defaults)
        let ngaThread = try #require(ForumPayload.mock.threads.first)
        let v2exThread = ForumThread(
            id: ngaThread.id,
            title: "V2EX 同 ID 主题",
            summary: "",
            author: "v2ex-user",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "",
            replies: [],
            source: .v2ex
        )

        store.record(ngaThread)
        store.record(v2exThread)
        store.record(ngaThread)

        #expect(store.entries.count == 2)
        #expect(store.entries.first?.source == .nga)
        #expect(BrowsingHistoryStore(defaults: defaults).entries.count == 2)
    }

    @Test func channelPagingCyclesInBothDirections() throws {
        let channels = [
            ForumChannel(id: -7, title: "网事杂谈"),
            ForumChannel(id: 706, title: "大时代"),
            ForumChannel(id: -7_955_747, title: "晴风村")
        ]

        #expect(ChannelPagingPolicy.destination(currentID: -7, channels: channels, direction: .next)?.id == 706)
        #expect(ChannelPagingPolicy.destination(currentID: 706, channels: channels, direction: .next)?.id == -7_955_747)
        #expect(ChannelPagingPolicy.destination(currentID: -7_955_747, channels: channels, direction: .next)?.id == -7)
        #expect(ChannelPagingPolicy.destination(currentID: -7, channels: channels, direction: .previous)?.id == -7_955_747)
    }

    @Test func channelPagingDistinguishesSwipesFromTapsAndScrolling() {
        #expect(!ChannelPagingPolicy.isHorizontalIntent(CGSize(width: 6, height: 2)))
        #expect(!ChannelPagingPolicy.isHorizontalIntent(CGSize(width: 25, height: 80)))
        #expect(ChannelPagingPolicy.isHorizontalIntent(CGSize(width: 18, height: 4)))
        #expect(ChannelPagingPolicy.direction(for: CGSize(width: -80, height: 12)) == .next)
        #expect(ChannelPagingPolicy.direction(for: CGSize(width: 80, height: 12)) == .previous)
        #expect(ChannelPagingPolicy.direction(for: CGSize(width: 45, height: 5)) == nil)
    }

    @Test func feedPaginationPrefetchesAtThirdItemFromEnd() {
        #expect(!FeedPaginationPolicy.shouldPrefetch(itemIndex: 16, itemCount: 20, canLoadMore: true))
        #expect(FeedPaginationPolicy.shouldPrefetch(itemIndex: 17, itemCount: 20, canLoadMore: true))
        #expect(!FeedPaginationPolicy.shouldPrefetch(itemIndex: 17, itemCount: 20, canLoadMore: false))
        #expect(FeedPaginationPolicy.shouldPrefetch(itemIndex: 0, itemCount: 1, canLoadMore: true))
    }

    @Test func guestCanLoadPublicForum() async {
        let viewModel = ForumViewModel(repository: MockThreadRepository())

        await viewModel.reload()

        #expect(viewModel.isAuthenticated == false)
        #expect(!viewModel.threads.isEmpty)
    }

    @Test func mockRepositoryLoadsFavoriteThreads() async throws {
        let result = try await MockThreadRepository().fetchFavoriteThreads(page: 1)

        #expect(result.payload?.forum.title == "我的收藏")
        #expect(result.payload?.threads.isEmpty == false)
    }

    @Test func mockRepositorySearchesThreads() async throws {
        let result = try await MockThreadRepository().searchThreads(query: "SwiftUI", page: 1)

        #expect(result.payload?.forum.title == "搜索：SwiftUI")
        #expect(result.payload?.threads.first?.title.contains("SwiftUI") == true)
    }

    @Test func blockedUsersFilterPersistAndRestore() throws {
        let suiteName = "ForumHubTests.blocked-users.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = BlockedUsersStore(defaults: defaults)
        store.block(source: .nga, username: "CJ")

        #expect(store.isBlocked(source: .nga, username: "cj"))
        #expect(!store.isBlocked(source: .v2ex, username: "cj"))
        #expect(store.filtering(ForumPayload.mock.threads).contains { $0.author == "CJ" } == false)

        let restored = BlockedUsersStore(defaults: defaults)
        #expect(restored.blockedUsers == [BlockedForumUser(source: .nga, username: "CJ")])

        restored.unblock(try #require(restored.blockedUsers.first))
        #expect(restored.blockedUsers.isEmpty)
    }

    @Test func favoriteThreadsPersistAndToggleBySource() throws {
        let suiteName = "ForumHubTests.favorite-threads.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let ngaThread = try #require(ForumPayload.mock.threads.first)
        let v2exThread = ForumThread(
            id: ngaThread.id,
            title: "V2EX 同 ID 主题",
            summary: "",
            author: "v2ex-user",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "",
            replies: [],
            source: .v2ex
        )

        let store = FavoriteThreadsStore(defaults: defaults)
        store.save(ngaThread)
        store.save(v2exThread)

        #expect(store.contains(ngaThread))
        #expect(store.contains(v2exThread))
        #expect(store.entries.count == 2)

        let restored = FavoriteThreadsStore(defaults: defaults)
        #expect(restored.entries.count == 2)
        #expect(restored.entries.map(\.source) == [.v2ex, .nga])

        restored.toggle(ngaThread)
        #expect(!restored.contains(ngaThread))
        #expect(restored.contains(v2exThread))
    }

    @Test func threadFiltersRepliesByOriginalAuthor() {
        let thread = ForumThread(
            id: 1,
            title: "测试主题",
            summary: "",
            author: "楼主 Alice",
            lastReplyAt: "",
            replyCount: 3,
            viewCount: 0,
            body: "首楼",
            replies: [
                Reply(id: 1, author: "路人", createdAt: "", body: "普通回复"),
                Reply(id: 2, author: "楼主 Alice", createdAt: "", body: "楼主回复"),
                Reply(id: 3, author: "楼主 alice", createdAt: "", body: "大小写不同")
            ]
        )

        #expect(thread.authorReplies.map(\.id) == [2, 3])
    }

    @Test func threadDetailParserKeepsEveryReplyOnLaterPages() throws {
        let json = """
        {
          "code": 0,
          "result": [
            {
              "pid": 201,
              "tid": 100,
              "author": { "username": "第二页作者 A" },
              "content": "第二页第一条"
            },
            {
              "pid": 202,
              "tid": 100,
              "author": { "username": "楼主" },
              "content": "第二页第二条"
            }
          ]
        }
        """.data(using: .utf8)!

        let page = try #require(ThreadDetailParser.parse(
            data: json,
            fallbackText: String(decoding: json, as: UTF8.self),
            tid: 100,
            page: 2
        ))

        #expect(page.replies.map(\.id) == [201, 202])
        #expect(page.replies.map(\.floorNumber) == [nil, nil])
    }

    @Test func threadDetailParserDropsRepeatedMainPostOnLaterPages() throws {
        let json = """
        {
          "code": 0,
          "result": {
            "0": {
              "pid": 0,
              "lou": 1,
              "tid": 100,
              "subject": "测试主题",
              "author": { "username": "楼主" },
              "content": "首楼内容"
            },
            "1": {
              "pid": 301,
              "lou": 21,
              "tid": 100,
              "author": { "username": "用户 A" },
              "content": "第二页第一条"
            },
            "2": {
              "pid": 302,
              "lou": 22,
              "tid": 100,
              "author": { "username": "用户 B" },
              "content": "第二页第二条"
            }
          }
        }
        """.data(using: .utf8)!

        let page = try #require(ThreadDetailParser.parse(
            data: json,
            fallbackText: String(decoding: json, as: UTF8.self),
            tid: 100,
            page: 2
        ))

        #expect(page.replies.map(\.id) == [301, 302])
        #expect(page.replies.map(\.body) == ["第二页第一条", "第二页第二条"])
        #expect(page.replies.map(\.floorNumber) == [21, 22])
    }

    @Test func onlyAuthorPaginationContinuesUntilVisibleReplyOrSafetyLimit() {
        #expect(ThreadDetailPaginationPolicy.shouldContinueAutomaticLoading(
            showsOnlyAuthor: true,
            authorReplyCountBeforeLoad: 1,
            authorReplyCountAfterLoad: 1,
            hasMoreReplies: true,
            scannedPageCount: 1
        ))
        #expect(!ThreadDetailPaginationPolicy.shouldContinueAutomaticLoading(
            showsOnlyAuthor: true,
            authorReplyCountBeforeLoad: 1,
            authorReplyCountAfterLoad: 1,
            hasMoreReplies: true,
            scannedPageCount: 5
        ))
    }

    @Test func directPaginationAutoAdvanceRequiresArmedCurrentPage() {
        #expect(ThreadDetailDirectPaginationAutoAdvancePolicy.scrolledDistance(
            baselineOffset: 0,
            currentOffset: -180
        ) == 180)
        #expect(ThreadDetailDirectPaginationAutoAdvancePolicy.isNearBottom(
            footerMinY: 540,
            viewportHeight: 520
        ))
        #expect(!ThreadDetailDirectPaginationAutoAdvancePolicy.isNearBottom(
            footerMinY: 620,
            viewportHeight: 520
        ))
        #expect(ThreadDetailDirectPaginationAutoAdvancePolicy.shouldArmCurrentPage(
            scrolledDistance: 180,
            isNearBottom: true,
            currentPage: 1,
            totalPageCount: 3
        ))
        #expect(!ThreadDetailDirectPaginationAutoAdvancePolicy.shouldArmCurrentPage(
            scrolledDistance: 80,
            isNearBottom: true,
            currentPage: 1,
            totalPageCount: 3
        ))
        #expect(ThreadDetailDirectPaginationAutoAdvancePolicy.shouldAutoAdvance(
            currentPage: 1,
            totalPageCount: 3,
            isLoadingMore: false,
            armedPage: 1,
            isNearBottom: true
        ))
        #expect(!ThreadDetailDirectPaginationAutoAdvancePolicy.shouldAutoAdvance(
            currentPage: 2,
            totalPageCount: 3,
            isLoadingMore: false,
            armedPage: 1,
            isNearBottom: true
        ))
        #expect(!ThreadDetailDirectPaginationAutoAdvancePolicy.shouldAutoAdvance(
            currentPage: 2,
            totalPageCount: 3,
            isLoadingMore: false,
            armedPage: nil,
            isNearBottom: true
        ))
        #expect(!ThreadDetailDirectPaginationAutoAdvancePolicy.shouldAutoAdvance(
            currentPage: 1,
            totalPageCount: 3,
            isLoadingMore: false,
            armedPage: 1,
            isNearBottom: false
        ))
    }

    @Test func snapshotRendererSplitsLoadedRepliesIntoSafeImages() {
        let replies = (1...13).map {
            Reply(id: $0, author: "用户\($0)", createdAt: "", body: "回复 \($0)")
        }

        #expect(ThreadSnapshotRenderer.replyChunks(replies).map(\.count) == [6, 6, 1])
        #expect(ThreadSnapshotRenderer.replyChunks([]).count == 1)
    }

    @Test func snapshotRendererProducesShareableImages() async throws {
        let source = try #require(ForumPayload.mock.threads.first)
        let replies = (1...7).map {
            Reply(id: $0, author: "用户\($0)", createdAt: "刚刚", body: "测试回复 \($0)")
        }

        let images = try await ThreadSnapshotRenderer.render(
            thread: source,
            replies: replies,
            scope: .loadedContent
        )

        #expect(images.count == 2)
        #expect(images.allSatisfy { $0.size.width > 0 && $0.size.height > 0 })
    }

    @Test func v2exMapperProducesSourceAwareTopics() throws {
        let bundle = Bundle(for: FixtureLocator.self)
        let fixtureURL = try #require(
            bundle.url(forResource: "v2ex-topics", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "v2ex-topics", withExtension: "json")
        )
        let topics = try V2EXMapper.decodeTopics(Data(contentsOf: fixtureURL))
        let topic = try #require(topics.first)

        #expect(topic.source == .v2ex)
        #expect(topic.id == 1_221_540)
        #expect(topic.author == "v2ex-user")
        #expect(topic.authorAvatarURL?.absoluteString == "https://cdn.v2ex.com/avatar/example.png")
        #expect(topic.replyCount == 12)
        #expect(topic.body.contains("第一段"))
        #expect(topic.body.contains("[图片] https://example.com/test.png"))
    }

    @Test func v2exThreadDetailMapsReplyAvatars() throws {
        let topic = V2EXTopicDTO(
            id: 42,
            title: "测试主题",
            content: "首楼",
            contentRendered: nil,
            replies: 1,
            created: 1_718_000_000,
            lastTouched: 1_718_000_300,
            member: V2EXMemberDTO(id: 1, username: "alice", avatarNormal: "//cdn.v2ex.com/alice.png")
        )
        let replies = [
            V2EXReplyDTO(
                id: 7,
                content: "回复内容",
                contentRendered: nil,
                created: 1_718_000_400,
                member: V2EXMemberDTO(id: 2, username: "bob", avatarNormal: "/avatar/bob.png")
            )
        ]

        let thread = V2EXMapper.threadDetail(topic: topic, replies: replies)

        #expect(thread.authorAvatarURL?.absoluteString == "https://cdn.v2ex.com/alice.png")
        #expect(thread.replies.first?.avatarURL?.absoluteString == "https://www.v2ex.com/avatar/bob.png")
    }

    @Test func v2exAuthParsesMemberEnvelopeAndDirectMember() throws {
        let envelope = Data(#"{"success":true,"result":{"id":42,"username":"codex-user"}}"#.utf8)
        let direct = Data(#"{"id":43,"username":"direct-user"}"#.utf8)

        #expect(try V2EXAuthResponseParser.account(from: envelope) == V2EXAccount(id: 42, username: "codex-user"))
        #expect(try V2EXAuthResponseParser.account(from: direct) == V2EXAccount(id: 43, username: "direct-user"))
    }

    @Test func v2exTopicParserAcceptsV1ArrayAndV2Envelope() throws {
        let topic = #"{"id":42,"title":"下一页主题","member":{"username":"codex-user"}}"#
        let direct = Data("[\(topic)]".utf8)
        let envelope = Data("{\"success\":true,\"result\":[\(topic)]}".utf8)

        #expect(try V2EXTopicResponseParser.topics(from: direct).map(\.id) == [42])
        #expect(try V2EXTopicResponseParser.topics(from: envelope).map(\.id) == [42])
    }

    @Test func v2exRecentPageParserExtractsTopicsAndNextPage() throws {
        let html = Data("""
        <html><head><link rel="next" title="Next Page" href="/recent?p=3" /></head><body>
        <div class="cell item"><img class="avatar" alt="alice" />
        <a href="/t/1221473#reply10" class="topic-link">Swift &amp; iOS</a>
        <a class="count_livid">10</a></div>
        <div class="cell item"><img class="avatar" alt="bob" />
        <a href="/t/1221489#reply1" class="topic-link">第二个主题</a></div>
        </body></html>
        """.utf8)

        let page = V2EXRecentPageParser.parse(data: html)

        #expect(page.topics.map(\.id) == [1_221_473, 1_221_489])
        #expect(page.topics.map { $0.member?.username } == ["alice", "bob"])
        #expect(page.topics.first?.title == "Swift & iOS")
        #expect(page.topics.first?.replies == 10)
        #expect(page.hasNextPage)
    }

}

private final class FixtureLocator {}
