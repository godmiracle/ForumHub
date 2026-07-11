import Foundation
import Testing
import UIKit
@testable import ForumHub

@MainActor
struct ForumHubTests {

    private func testURL(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            fatalError("测试 URL 无效：\(value)")
        }
        return url
    }

    @Test func forumErrorClassifiesTransportAndProviderFailures() {
        #expect(ForumError.resolve(URLError(.notConnectedToInternet)) == .offline)
        #expect(ForumError.resolve(URLError(.timedOut)) == .timeout)
        #expect(ForumError.resolve(ForumProviderError.httpStatus(401)) == .authenticationExpired)
        #expect(ForumError.resolve(ForumProviderError.httpStatus(429)) == .rateLimited)
        #expect(ForumError.resolve(ForumProviderError.invalidResponse) == .malformedResponse)
        #expect(ForumError.resolve(CancellationError()) == nil)
    }

    private func paginationThread(
        replies: [Reply],
        replyCount: Int
    ) -> ForumThread {
        ForumThread(
            id: 100,
            title: "分页测试主题",
            summary: "",
            author: "楼主",
            createdAt: "09:00",
            lastReplyAt: replies.last?.createdAt ?? "09:00",
            replyCount: replyCount,
            viewCount: 0,
            body: "首楼内容",
            replies: replies
        )
    }

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

    @Test func forumListDoesNotGenerateAvatarURLFromAuthorID() throws {
        let json = """
        {
          "items": [
            {
              "tid": 1001,
              "subject": "头像归属测试",
              "author": "楼主",
              "authorid": 60459868,
              "lastposter": "最后回复用户",
              "avatar": "https://example.com/last-replier.png"
            }
          ]
        }
        """.data(using: .utf8)!

        let thread = try #require(ForumPayloadParser.parse(
            data: json,
            fallbackText: "",
            fid: 722
        )?.threads.first)

        #expect(thread.author == "楼主")
        #expect(thread.authorAvatarURL == nil)
    }

    @Test func forumListUsesAuthorAvatarFromUserDictionary() throws {
        let json = """
        {
          "data": {
            "__T": {
              "1001": {
                "tid": 1001,
                "subject": "头像映射测试",
                "author": "一剑霜寒 NGA",
                "authorid": 60459868
              }
            },
            "__U": {
              "60459868": {
                "uid": 60459868,
                "username": "一剑霜寒 NGA",
                "avatar": "https://img.nga.178.com/avatars/60459868.jpg"
              }
            }
          }
        }
        """.data(using: .utf8)!

        let thread = try #require(ForumPayloadParser.parse(
            data: json,
            fallbackText: "",
            fid: 722
        )?.threads.first)

        #expect(thread.author == "一剑霜寒 NGA")
        #expect(thread.authorAvatarURL?.absoluteString == "https://img.nga.178.com/avatars/60459868.jpg")
    }

    @Test func ngaPostnumExcludesTheMainPostBeforePagination() throws {
        let listJSON = """
        {
          "items": [
            {
              "tid": 1001,
              "subject": "共 60 楼的主题",
              "author": "CJ",
              "postnum": 60
            }
          ]
        }
        """.data(using: .utf8)!
        let detailJSON = """
        {
          "result": [
            {
              "pid": 1,
              "subject": "共 60 楼的主题",
              "postnum": 60,
              "author": { "username": "CJ" },
              "content": "主楼"
            }
          ]
        }
        """.data(using: .utf8)!

        let listThread = try #require(ForumPayloadParser.parse(
            data: listJSON,
            fallbackText: "",
            fid: 722
        )?.threads.first)
        let detailThread = try #require(ThreadDetailParser.parse(
            data: detailJSON,
            fallbackText: String(decoding: detailJSON, as: UTF8.self),
            tid: 1001
        ))
        let capabilities = ForumCapabilities(
            supportsSearch: false,
            supportsFavorites: false,
            supportsReply: false,
            supportsReplyTargeting: false,
            supportsAuthentication: false,
            supportsFeedPagination: true,
            threadPaginationStyle: .numbered(pageSize: 20)
        )

        #expect(listThread.replyCount == 59)
        #expect(detailThread.replyCount == 59)
        #expect(ThreadPaginationPolicy.totalPageCount(
            replyCount: detailThread.replyCount,
            fallbackReplyCount: listThread.replyCount,
            capabilities: capabilities
        ) == 3)
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

    @Test func parserPreservesHTMLImagesInMainPost() throws {
        let json = """
        {
          "result": [
            {
              "pid": 0,
              "tid": 2001,
              "subject": "带图片的主贴",
              "author": { "username": "楼主" },
              "content": "主贴正文<img src=\\"https://img.nga.178.com/attachments/main-post.jpg\\"/>结尾"
            }
          ]
        }
        """.data(using: .utf8)!

        let thread = try #require(ThreadDetailParser.parse(
            data: json,
            fallbackText: String(decoding: json, as: UTF8.self),
            tid: 2001
        ))

        #expect(thread.body.contains("[图片] https://img.nga.178.com/attachments/main-post.jpg"))
        let expectedURL = testURL("https://img.nga.178.com/attachments/main-post.jpg")
        #expect(ForumContentParser.parse(thread.body).contains {
            $0.content == .image(expectedURL)
        })
    }

    @Test func ngaAvatarResolverUpgradesKnownHTTPAvatarHost() {
        let url = ForumAvatarResolver.ngaAvatarURL(
            from: "http://img.nga.178.com/avatars/example.jpg?size=small"
        )

        #expect(url?.absoluteString == "https://img.nga.178.com/avatars/example.jpg?size=small")
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
        #expect(blocks[1].content == .image(testURL("https://img.nga.178.com/attachments/mon_202606/18/example-a.jpg")))
        #expect(blocks[2].content == .text("第二段正文"))
        #expect(blocks[3].content == .image(testURL("https://img.nga.178.com/attachments/mon_202606/18/example-b.webp")))
    }

    @Test func contentParserSupportsInlineBBCodeAndNGAImageURLVariants() throws {
        let content = "文字 [img]//img.nga.178.com/a.gif[/img] 说明 [图片] /attachments/mon_202607/b.jpg?name=a&amp;size=full"

        let blocks = ForumContentParser.parse(content)

        #expect(blocks.count == 4)
        #expect(blocks[0].content == .text("文字"))
        #expect(blocks[1].content == .image(testURL("https://img.nga.178.com/a.gif")))
        #expect(blocks[2].content == .text("说明"))
        #expect(blocks[3].content == .image(testURL("https://img.nga.178.com/attachments/mon_202607/b.jpg?name=a&size=full")))
    }

    @Test func structuredForumTextPreservesSizedNGAImageTags() throws {
        let content = "正文[img=800x600]./mon_202607/10/k2Q66-4vjkZeT1kShs-13m.jpg[/img]结尾"

        let blocks = ForumContentParser.parse(content.structuredForumText)

        #expect(blocks.contains {
            if case let .image(url) = $0.content {
                return url.absoluteString == "https://img.nga.178.com/attachments/mon_202607/10/k2Q66-4vjkZeT1kShs-13m.jpg"
            }
            return false
        })
    }

    @Test func contentParserPreservesNGARelativeMainPostImage() {
        let content = "主贴正文[img]./mon_202607/10/k2Q66-4vjkZeT1kShs-13m.jpg[/img]结尾"
        let blocks = ForumContentParser.parse(content.structuredForumText)

        #expect(blocks.contains {
            if case let .image(url) = $0.content {
                return url.absoluteString == "https://img.nga.178.com/attachments/mon_202607/10/k2Q66-4vjkZeT1kShs-13m.jpg"
            }
            return false
        })
    }

    @Test func webThreadParserPreservesMainPostParagraphAndImage() throws {
        let html = """
        <html><head><title>测试主贴 - NGA玩家社区</title></head><body>
        <p id='postcontent0' class='postcontent ubbcode'>[img]./mon_202607/10/k2Q66-4vjkZeT1kShs-13m.jpg[/img]l<br/>来源:数码闲聊站<br/>完整正文</p>
        <span id='postcontent1' class='postcontent ubbcode'>第一条回复</span>
        </body></html>
        """

        let thread = try #require(WebForumParser.parseThreadHTML(html, tid: 47151166))
        #expect(thread.body.contains("来源:数码闲聊站"))
        #expect(thread.body.contains("完整正文"))
        #expect(ForumContentParser.parse(thread.body).contains {
            if case let .image(url) = $0.content {
                return url.absoluteString == "https://img.nga.178.com/attachments/mon_202607/10/k2Q66-4vjkZeT1kShs-13m.jpg"
            }
            return false
        })
        #expect(thread.replies.count == 1)
    }

    @Test func ngaThreadMergerSupplementsAPIContentWithoutReplacingOrDuplicating() throws {
        let bundle = Bundle(for: FixtureLocator.self)
        let apiURL = try #require(
            bundle.url(forResource: "nga-thread-api-incomplete", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "nga-thread-api-incomplete", withExtension: "json")
        )
        let webURL = try #require(
            bundle.url(forResource: "nga-thread-web-enrichment", withExtension: "html", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "nga-thread-web-enrichment", withExtension: "html")
        )
        let apiData = try Data(contentsOf: apiURL)
        let apiThread = try #require(ThreadDetailParser.parse(
            data: apiData,
            fallbackText: String(decoding: apiData, as: UTF8.self),
            tid: 47151166
        ))
        let webThread = try #require(WebForumParser.parseThreadHTML(
            String(decoding: try Data(contentsOf: webURL), as: UTF8.self),
            tid: 47151166
        ))

        let merged = NGAThreadDetailMerger.merge(apiThread: apiThread, webThread: webThread)

        #expect(merged.body.contains("API 正文第一段"))
        #expect(merged.body.contains("网页补全第二段"))
        #expect(ForumContentParser.parse(merged.body).compactMap { block -> URL? in
            if case let .image(url) = block.content { return url }
            return nil
        }.count == 2)
        #expect(merged.replies.map(\.body) == ["API 已有回复", "网页补充回复"])
    }

    @Test func forumImageURLResolverUpgradesTrustedNGAHTTPOnly() throws {
        #expect(
            ForumImageURLResolver.resolve("http://img.nga.178.com/a.jpg")
                == testURL("https://img.nga.178.com/a.jpg")
        )
        #expect(
            ForumImageURLResolver.resolve("http://example.com/a.jpg")
                == testURL("http://example.com/a.jpg")
        )
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

    @Test func tabReselectionRoutesFeedRefreshSeparatelyFromOtherScreens() {
        #expect(TabReselectionPolicy.behavior(for: .home) == .scrollToTopAndRefresh)
        #expect(TabReselectionPolicy.behavior(for: .hot) == .scrollToTopAndRefresh)
        #expect(TabReselectionPolicy.behavior(for: .community) == .scrollToTop)
        #expect(TabReselectionPolicy.behavior(for: .history) == .scrollToTop)
        #expect(TabReselectionPolicy.behavior(for: .user) == .scrollToTop)
    }

    @Test func tabScrollRequestTargetsOnlyItsOwnTab() {
        let request = TabScrollRequest(id: 3, target: .hot)

        #expect(request.targets(.hot))
        #expect(!request.targets(.home))
        #expect(!request.targets(.community))
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

    @Test func mockPagedThreadRepositoryBuildsFinalPartialPageWithoutCrashing() async throws {
        let finalPage = try await MockPagedThreadRepository().fetchThread(tid: 991001, page: 7)

        #expect(finalPage.thread.replies.count == 19)
        #expect(finalPage.thread.replies.first?.floorNumber == 122)
        #expect(finalPage.thread.replies.last?.floorNumber == 140)
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

    @Test func paginationMergerDropsRepeatedMainPostAndDuplicateReplies() {
        let currentThread = paginationThread(
            replies: [
                Reply(id: 101, author: "用户 A", createdAt: "10:00", body: "已有回复"),
                Reply(id: 102, author: "用户 B", createdAt: "10:01", body: "最后一条旧回复")
            ],
            replyCount: 4
        )
        let continuationThread = paginationThread(
            replies: [
                Reply(id: 0, author: "楼主", createdAt: "09:00", body: "首楼内容"),
                Reply(id: 102, author: "用户 B", createdAt: "10:01", body: "最后一条旧回复"),
                Reply(id: 202, author: "用户 A", createdAt: "10:00", body: "已有回复"),
                Reply(id: 203, author: "用户 C", createdAt: "10:02", body: "新的回复")
            ],
            replyCount: 4
        )

        let result = ThreadDetailPaginationMerger.merge(
            currentThread: currentThread,
            continuationThread: continuationThread,
            replyTotalCount: 4
        )

        #expect(result.pageStartReplyIndex == 2)
        #expect(result.continuationReplies.map(\.id) == [102, 202, 203])
        #expect(result.appendedReplies.map(\.id) == [203])
        #expect(result.thread.replies.map(\.id) == [101, 102, 203])
        #expect(result.thread.lastReplyAt == "10:02")
    }

    @Test func paginationMergerPreservesPageOrderAcrossMultiPageJump() {
        let firstPage = paginationThread(
            replies: [Reply(id: 101, author: "用户 A", createdAt: "10:00", body: "第一页")],
            replyCount: 3
        )
        let secondPage = paginationThread(
            replies: [Reply(id: 201, author: "用户 B", createdAt: "10:01", body: "第二页")],
            replyCount: 3
        )
        let thirdPage = paginationThread(
            replies: [Reply(id: 301, author: "用户 C", createdAt: "10:02", body: "第三页")],
            replyCount: 3
        )

        let secondPageResult = ThreadDetailPaginationMerger.merge(
            currentThread: firstPage,
            continuationThread: secondPage,
            replyTotalCount: 3
        )
        let thirdPageResult = ThreadDetailPaginationMerger.merge(
            currentThread: secondPageResult.thread,
            continuationThread: thirdPage,
            replyTotalCount: 3
        )

        #expect(secondPageResult.pageStartReplyIndex == 1)
        #expect(thirdPageResult.pageStartReplyIndex == 2)
        #expect(thirdPageResult.thread.replies.map(\.id) == [101, 201, 301])
    }

    @Test func paginationMergerDoesNotAppendAnEmptyOrDuplicateContinuationPage() {
        let currentThread = paginationThread(
            replies: [Reply(id: 101, author: "用户 A", createdAt: "10:00", body: "已有回复")],
            replyCount: 1
        )
        let continuationThread = paginationThread(
            replies: [
                Reply(id: 0, author: "楼主", createdAt: "09:00", body: "首楼内容"),
                Reply(id: 101, author: "用户 A", createdAt: "10:00", body: "已有回复")
            ],
            replyCount: 1
        )

        let result = ThreadDetailPaginationMerger.merge(
            currentThread: currentThread,
            continuationThread: continuationThread,
            replyTotalCount: 1
        )

        #expect(result.continuationReplies.map(\.id) == [101])
        #expect(!result.didAppendReplies)
        #expect(result.thread.replies == currentThread.replies)
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

    @Test func directPaginationPreloadsNearEndReplyEntries() {
        let replies = (1...20).map {
            Reply(id: $0, author: "用户 \($0)", createdAt: "", body: "回复 \($0)")
        }

        let entries = ThreadDetailPresentationBuilder.displayedReplyEntries(
            displayedReplies: replies,
            allReplies: replies,
            pageStartReplyIndices: [1: 0],
            supportsDirectPagination: true,
            pageSize: 20,
            prefetchReplyDistance: 3
        )

        #expect(entries.filter(\.loadsNextPageWhenAppearing).map(\.reply.id) == [18, 19, 20])
        #expect(entries.first?.showsPageAnchor == true)
        #expect(entries.dropFirst().allSatisfy { !$0.showsPageAnchor })
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
