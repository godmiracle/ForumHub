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

    @Test func replyComposerDocumentInsertsEmojiAsStructuredContentAndSerializesForNGA() {
        var document = ReplyComposerDocument(text: "前后")
        document.updateSelection(NSRange(location: 1, length: 0))
        let emoji = ReplyComposerEmoji(
            NGAForumEmojiItem(group: .ng, displayName: "1", filename: "ng_1.png")
        )

        document.insert(emoji: emoji)

        #expect(document.markup == "前[img]https://img4.nga.178.com/ngabbs/post/smile/ng_1.png[/img]后")
        #expect(document.displayCharacterCount == 3)
        #expect(document.selection == NSRange(location: 3, length: 0))
        #expect(!document.isEmpty)
    }

    @Test func ngaReplySubmissionFormIncludesServerIssuedAuthToken() {
        let form = NGAReplySubmissionForm.make(
            action: "reply",
            tid: 1001,
            fid: -7,
            content: "[img]https://img4.nga.178.com/ngabbs/post/smile/ng_1.png[/img]",
            auth: "server-issued-auth"
        )

        #expect(form["auth"] == "server-issued-auth")
        #expect(form["post_content"] == "[img]https://img4.nga.178.com/ngabbs/post/smile/ng_1.png[/img]")
        #expect(form["__output"] == "14")
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

    @Test func threadDetailParserUsesZeroFloorAsMainPostWhenAPIArrayIsUnordered() throws {
        let json = """
        {
          "result": [
            {
              "pid": 8801,
              "tid": 47170004,
              "lou": 1,
              "author": { "username": "回复者" },
              "content": "不应成为主楼的回复"
            },
            {
              "pid": 0,
              "tid": 47170004,
              "lou": 0,
              "subject": "乱序 API 主楼测试",
              "author": { "username": "楼主" },
              "content": "完整的零楼主贴"
            }
          ]
        }
        """
        let data = try #require(json.data(using: .utf8))

        let thread = try #require(ThreadDetailParser.parse(
            data: data,
            fallbackText: json,
            tid: 47170004
        ))

        #expect(thread.author == "楼主")
        #expect(thread.body == "完整的零楼主贴")
        #expect(thread.replies.map(\.body) == ["不应成为主楼的回复"])
        #expect(thread.replies.first?.floorNumber == 1)
    }

    @Test func threadDetailParserResolvesContinuationAuthorFromUserDirectory() throws {
        let json = """
        {
          "result": [
            {
              "pid": 3002,
              "tid": 3001,
              "lou": 29,
              "authorid": 7788,
              "postdate": "2026-07-11 23:07",
              "content": "后续楼层"
            }
          ],
          "__U": {
            "7788": { "uid": 7788, "username": "后续作者" }
          }
        }
        """.data(using: .utf8)!

        let continuation = try #require(ThreadDetailParser.parse(
            data: json,
            fallbackText: String(decoding: json, as: UTF8.self),
            tid: 3001,
            page: 2
        ))

        #expect(continuation.replies.first?.author == "后续作者")
    }

    @Test func threadDetailParserResolvesContinuationAuthorFromNestedUserProfile() throws {
        let json = """
        {
          "result": [
            {
              "pid": 3102,
              "tid": 3101,
              "lou": 29,
              "postdate": "2026-07-11 23:07",
              "user": { "uid": 8899, "nickname": "嵌套作者" },
              "content": "后续楼层"
            }
          ]
        }
        """.data(using: .utf8)!

        let continuation = try #require(ThreadDetailParser.parse(
            data: json,
            fallbackText: String(decoding: json, as: UTF8.self),
            tid: 3101,
            page: 2
        ))

        #expect(continuation.replies.first?.author == "嵌套作者")
    }

    @Test func forumImageURLResolverRecognizesNGASmileAssets() {
        #expect(ForumImageURLResolver.isNGAForumEmoji(
            testURL("https://img4.nga.178.com/ngabbs/post/smile/ng_1.png")
        ))
        #expect(!ForumImageURLResolver.isNGAForumEmoji(
            testURL("https://img.nga.178.com/attachments/mon_202607/example.jpg")
        ))
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

    @Test func structuredForumTextRendersNGAEmojiMarkupWithoutDroppingContent() throws {
        let content = "好看吗[s:ac:哭笑] 来杯[s:ac:茶] [s:ac:未知表情]"
        let blocks = ForumContentParser.parse(content.structuredForumText)

        #expect(blocks[0].content == .text("好看吗"))
        #expect(blocks[1].content == .smile(try #require(NGAForumSmile(markup: "[s:ac:哭笑]"))))
        #expect(blocks[2].content == .text("来杯"))
        #expect(blocks[3].content == .smile(try #require(NGAForumSmile(markup: "[s:ac:茶]"))))
        #expect(blocks[4].content == .text("[s:ac:未知表情]"))
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

    @Test func ngaThreadMergerSupplementsAPIContentWithoutCreatingWebReplies() throws {
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
        #expect(merged.replies.map(\.body) == ["API 已有回复\n网页补充回复"])
        #expect(merged.contentDocument.markupFormat == .html)
    }

    @Test func ngaThreadResolverPreservesAPIContentWhenWebEnrichmentFails() throws {
        let bundle = Bundle(for: FixtureLocator.self)
        let apiURL = try #require(
            bundle.url(forResource: "nga-thread-api-incomplete", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "nga-thread-api-incomplete", withExtension: "json")
        )
        let apiData = try Data(contentsOf: apiURL)
        let apiThread = try #require(ThreadDetailParser.parse(
            data: apiData,
            fallbackText: String(decoding: apiData, as: UTF8.self),
            tid: 47151166
        ))

        let resolved = NGAThreadDetailMerger.resolve(apiThread: apiThread, webThread: nil)

        #expect(resolved == apiThread)
        #expect(resolved?.contentDocument.rawMarkup == apiThread.contentDocument.rawMarkup)
        #expect(resolved?.replies == apiThread.replies)
    }

    @Test func webThreadParserRejectsAccessDeniedPage() {
        let html = """
        <html><head><title>访客不能直接访问</title></head>
        <body>(ERROR:15) 访客不能直接访问，请登录。</body></html>
        """

        #expect(WebForumParser.parseThreadHTML(html, tid: 47151166) == nil)
    }

    @Test func webThreadParserUsesExactPostContentNodeInsteadOfWrapper() throws {
        let html = """
        <html><head><title>带图片的主贴 NGA玩家社区</title></head><body>
        <span id='postcontentandsubject0'>
          <p id='postcontent0' class='postcontent ubbcode'>[img]./mon_202607/12/main-one.jpg[/img]<br/>[img]./mon_202607/12/main-two.jpg[/img]<br/><br/>主贴后续文字</p>
        </span>
        <span id='postcontentandsubject1'><span id='postcontent1' class='postcontent ubbcode'>第一条回复</span></span>
        </body></html>
        """

        let thread = try #require(WebForumParser.parseThreadHTML(html, tid: 47162747))
        #expect(thread.body.contains("主贴后续文字"))
        #expect(thread.replies.map(\.body) == ["第一条回复"])
        #expect(ForumContentParser.parse(thread.body).compactMap { block -> URL? in
            if case let .image(url) = block.content { return url }
            return nil
        }.count == 2)
    }

    @Test func webThreadParserKeepsNestedContainersInsideMainPost() throws {
        let html = """
        <html><head><title>嵌套正文 - NGA玩家社区</title></head><body>
        <div id="postcontent0">主楼开头<div class="quote">引用开头<div>引用内层</div>引用结尾</div>主楼结尾</div>
        <div id="postcontent1">第一条回复</div>
        </body></html>
        """

        let thread = try #require(WebForumParser.parseThreadHTML(html, tid: 47170003))
        #expect(thread.body.contains("主楼开头"))
        #expect(thread.body.contains("引用内层"))
        #expect(thread.body.contains("主楼结尾"))
        #expect(thread.replies.map(\.body) == ["第一条回复"])
    }

    @Test func threadDetailParserPreservesAllImagesFromRealNGAAPIShape() throws {
        let json = """
        {
          "code": 0,
          "result": [
            {
              "pid": 0,
              "tid": 47164535,
              "lou": 0,
              "postdate": "2026-07-12 16:03",
              "content": "[img]https://img.nga.178.com/attachments/mon_202607/12/first.jpg[/img]<br/>第一段正文<br/>[img]https://img.nga.178.com/attachments/mon_202607/12/second.jpg[/img][img]https://img.nga.178.com/attachments/mon_202607/12/third.jpg[/img]<br/>后续正文",
              "author": { "username": "楼主" }
            },
            {
              "pid": 874846760,
              "tid": 47164535,
              "lou": 1,
              "content": "第一条回复",
              "author": { "username": "回复者" }
            }
          ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let thread = try #require(ThreadDetailParser.parse(
            data: data,
            fallbackText: json,
            tid: 47164535
        ))

        #expect(thread.body.contains("后续正文"))
        #expect(ForumContentParser.parse(thread.body).compactMap { block -> URL? in
            if case let .image(url) = block.content { return url }
            return nil
        }.count == 3)
        #expect(!NGAThreadParseQuality.needsWebEnrichment(thread: thread, rawText: json))
    }

    @Test func ngaNonemptyAPIContentDoesNotRequireWebEnrichment() {
        let thread = ForumThread(
            id: 47151166,
            title: "可能截断的主贴",
            summary: "前半段正文",
            author: "楼主",
            lastReplyAt: "",
            replyCount: 1,
            viewCount: 0,
            body: "前半段正文\n[图片] https://img.nga.178.com/attachments/first.jpg",
            replies: [Reply(id: 1, author: "回复作者", createdAt: "", body: "回复")]
        )
        let rawText = """
        {"content":"前半段正文[图片] https://img.nga.178.com/attachments/first.jpg"}
        """

        #expect(!NGAThreadParseQuality.needsWebEnrichment(thread: thread, rawText: rawText))
    }

    @Test func ngaContentQualityUsesDocumentInsteadOfLegacyBody() {
        let thread = ForumThread(
            id: 47151166,
            title: "正文权威来源",
            summary: "列表摘要",
            author: "楼主",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "兼容字段中的旧正文",
            contentDocument: .plainText(""),
            replies: []
        )

        #expect(NGAThreadParseQuality.needsWebEnrichment(thread: thread, rawText: ""))
        #expect(thread.body.isEmpty)
    }

    @Test func replyBodyIsAReadOnlyContentDocumentProjection() {
        let reply = Reply(
            id: 1,
            author: "回复者",
            createdAt: "",
            body: "旧兼容正文",
            contentDocument: .ngaBBCode("权威回复正文")
        )

        #expect(reply.body == "权威回复正文")
    }

    @Test func ngaReplyImagesDoNotMakeACompleteMainPostUseWebEnrichment() {
        let thread = ForumThread(
            id: 47170001,
            title: "主楼完整性判断",
            summary: "主楼正文",
            author: "楼主",
            lastReplyAt: "",
            replyCount: 1,
            viewCount: 0,
            body: "主楼正文",
            contentDocument: .ngaBBCode("主楼正文"),
            replies: [
                Reply(
                    id: 1,
                    author: "回复者",
                    createdAt: "",
                    body: "[图片] https://img.nga.178.com/attachments/reply.jpg"
                )
            ]
        )
        let rawText = """
        {"result":[
          {"pid":0,"content":"主楼正文"},
          {"pid":1,"content":"[img]https://img.nga.178.com/attachments/reply.jpg[/img]"}
        ]}
        """

        #expect(!NGAThreadParseQuality.needsWebEnrichment(thread: thread, rawText: rawText))
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
        #expect(defaults.integer(forKey: "forum-subscriptions-schema-version") == 1)
    }

    @Test func forumSubscriptionsDiscardMalformedSourceKeys() throws {
        let suiteName = "ForumHubTests.forum-subscriptions-corrupt.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["unknown:42", "nga:", "v2ex:swift"], forKey: "subscribed-forum-channel-keys-v3")
        defaults.set(["unknown:42", "v2ex:swift", "v2ex:swift"], forKey: "subscribed-forum-channel-order-v1")

        let subscriptions = ForumSubscriptionStore(defaults: defaults)

        #expect(subscriptions.subscribedChannelKeys == ["v2ex:swift"])
        #expect(subscriptions.orderedChannelKeys == ["v2ex:swift"])
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

    @Test func userContentStoresMigrateLegacyArraySnapshots() throws {
        let suiteName = "ForumHubTests.versioned-user-content.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let thread = try #require(ForumPayload.mock.threads.first)
        let favorite = SavedForumThread(thread: thread)
        let history = BrowsingHistoryEntry(thread: thread)
        let blocked = BlockedForumUser(source: .nga, username: "CJ")
        defaults.set(try JSONEncoder().encode([favorite]), forKey: "favorite-forum-threads-v1")
        defaults.set(try JSONEncoder().encode([history]), forKey: "forum-browsing-history-v1")
        defaults.set(try JSONEncoder().encode([blocked]), forKey: "blocked-forum-users-v2")

        #expect(FavoriteThreadsStore(defaults: defaults).entries == [favorite])
        #expect(BrowsingHistoryStore(defaults: defaults).entries == [history])
        #expect(BlockedUsersStore(defaults: defaults).blockedUsers == [blocked])

        let favoriteSnapshot = try JSONDecoder().decode(
            VersionedLocalSnapshot<[SavedForumThread]>.self,
            from: try #require(defaults.data(forKey: "favorite-forum-threads-v1"))
        )
        let historySnapshot = try JSONDecoder().decode(
            VersionedLocalSnapshot<[BrowsingHistoryEntry]>.self,
            from: try #require(defaults.data(forKey: "forum-browsing-history-v1"))
        )
        let blockedSnapshot = try JSONDecoder().decode(
            VersionedLocalSnapshot<[BlockedForumUser]>.self,
            from: try #require(defaults.data(forKey: "blocked-forum-users-v2"))
        )
        #expect(favoriteSnapshot.version == 1)
        #expect(historySnapshot.version == 1)
        #expect(blockedSnapshot.version == 1)
    }

    @Test func corruptedUserContentSnapshotsDegradeToEmptyState() throws {
        let suiteName = "ForumHubTests.corrupted-user-content.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corrupted = Data("not-json".utf8)
        defaults.set(corrupted, forKey: "favorite-forum-threads-v1")
        defaults.set(corrupted, forKey: "forum-browsing-history-v1")
        defaults.set(corrupted, forKey: "blocked-forum-users-v2")
        defaults.set(["legacy-user"], forKey: "blocked-forum-usernames")

        #expect(FavoriteThreadsStore(defaults: defaults).entries.isEmpty)
        #expect(BrowsingHistoryStore(defaults: defaults).entries.isEmpty)
        #expect(BlockedUsersStore(defaults: defaults).blockedUsers.isEmpty)
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
        #expect(restored.entries.allSatisfy { $0.thread.body.isEmpty })
        #expect(restored.entries.allSatisfy { $0.thread.contentDocument.normalizedText.isEmpty })

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

    @Test func threadDetailParserPreservesMediaAndQuotedMarkupOnLaterPages() throws {
        let bundle = Bundle(for: FixtureLocator.self)
        let fixtureURL = try #require(
            bundle.url(forResource: "nga-thread-page2-media", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "nga-thread-page2-media", withExtension: "json")
        )
        let data = try Data(contentsOf: fixtureURL)
        let page = try #require(ThreadDetailParser.parse(
            data: data,
            fallbackText: String(decoding: data, as: UTF8.self),
            tid: 47151166,
            page: 2
        ))

        #expect(page.replies.map(\.id) == [201, 202])
        let mediaReply = try #require(page.replies.first)
        let imageURLs = ForumContentParser.parse(mediaReply.contentDocument.normalizedText).compactMap { block -> URL? in
            if case let .image(url) = block.content { return url }
            return nil
        }
        #expect(imageURLs.map(\.absoluteString) == [
            "https://img.nga.178.com/attachments/page-2.gif",
            "https://img.nga.178.com/attachments/mon_202607/page-2.jpg?name=a&size=full"
        ])

        let quotedReply = try #require(page.replies.last)
        #expect(quotedReply.contentDocument.rawMarkup.contains("./mon_202607/quoted-image.jpg"))
        #expect(quotedReply.contentDocument.normalizedText.contains("quoted-image.jpg"))
    }

    @Test func threadDetailParserDoesNotTurnQuoteMetadataIntoAReply() throws {
        let json = """
        {
          "code": 0,
          "result": {
            "0": {
              "pid": 401,
              "tid": 100,
              "lou": 32,
              "author": { "username": "真实回复者" },
              "content": "实际的第 32 楼"
            },
            "__R": {
              "lou": 28,
              "content": "这是引用元数据，不是独立楼层"
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

        #expect(page.replies.map(\.id) == [401])
        #expect(page.replies.map(\.author) == ["真实回复者"])
        #expect(page.replies.map(\.body) == ["实际的第 32 楼"])
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

    @Test func paginationMergerUsesContentDocumentToIdentifyRepeatedMainPost() {
        let currentThread = ForumThread(
            id: 100,
            title: "分页测试主题",
            summary: "",
            author: "楼主",
            lastReplyAt: "",
            replyCount: 1,
            viewCount: 0,
            body: "旧主楼投影",
            contentDocument: .ngaBBCode("权威主楼正文"),
            replies: []
        )
        let repeatedMainPost = Reply(
            id: 0,
            author: "楼主",
            createdAt: "",
            body: "不同的旧回复投影",
            contentDocument: .ngaBBCode("权威主楼正文")
        )
        let continuationThread = currentThread.replacingReplies([repeatedMainPost])

        let result = ThreadDetailPaginationMerger.merge(
            currentThread: currentThread,
            continuationThread: continuationThread,
            replyTotalCount: 1
        )

        #expect(result.continuationReplies.isEmpty)
        #expect(result.thread.replies.isEmpty)
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

    @Test func snapshotFooterDescribesItsActualScope() {
        let reply = Reply(
            id: 12,
            author: "用户",
            createdAt: "",
            body: "回复",
            floorNumber: 12
        )

        #expect(ThreadSnapshotRenderer.footerText(scope: .mainPost, replyCount: 0) == "由汇坛生成 · 主楼")
        #expect(ThreadSnapshotRenderer.footerText(scope: .singleReply(reply), replyCount: 1) == "由汇坛生成 · 12楼")
        #expect(ThreadSnapshotRenderer.footerText(scope: .loadedContent, replyCount: 40) == "由汇坛生成 · 当前已加载 40 条回复")
    }

    @Test func threadShareContentBuildsSourceSpecificOriginalURLs() {
        func thread(id: Int, source: ForumSource) -> ForumThread {
            ForumThread(
                id: id,
                title: "测试主题",
                summary: "",
                author: "作者",
                lastReplyAt: "",
                replyCount: 0,
                viewCount: 0,
                body: "",
                replies: [],
                source: source
            )
        }

        let ngaThread = thread(id: 123, source: .nga)
        let v2exThread = thread(id: 456, source: .v2ex)
        let linuxDoThread = thread(id: 789, source: .linuxDo)

        #expect(ThreadShareContent.originalURL(for: ngaThread)?.absoluteString == "https://bbs.nga.cn/read.php?tid=123")
        #expect(ThreadShareContent.originalURL(for: v2exThread)?.absoluteString == "https://www.v2ex.com/t/456")
        #expect(ThreadShareContent.originalURL(for: linuxDoThread)?.absoluteString == "https://linux.do/t/789")
        let shareItems = ThreadShareContent.activityItems(for: ngaThread)
        #expect(shareItems.count == 1)
        #expect(shareItems.first as? String == "测试主题\nhttps://bbs.nga.cn/read.php?tid=123")
    }

    @Test func threadDetailScrollStateResetsOnlyPresentationTracking() {
        let state = ThreadDetailScrollState()
        state.visiblePage = 3
        state.pendingPageSelection = 4
        state.deferredTargetPage = 4
        state.lastAutoLoadedPage = 5

        state.resetPageTracking()

        #expect(state.visiblePage == 1)
        #expect(state.pendingPageSelection == 1)
        #expect(state.deferredTargetPage == nil)
        #expect(state.lastAutoLoadedPage == nil)
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
