import Foundation
import Security
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

    @Test func cancellingReplySubmissionRestoresStateWithoutDiscardingDraft() async {
        let thread = ForumPayload.mock.threads[0]
        let viewModel = ThreadDetailViewModel(thread: thread)
        viewModel.actions.replyDocument = ReplyComposerDocument(text: "保留的回复草稿")
        viewModel.actions.showsReplyComposer = true

        let submission = Task {
            await viewModel.submitReply(
                thread: thread,
                repository: SuspendedReplyRepository(),
                refreshDetail: {}
            )
        }

        while !viewModel.actions.isSubmittingReply {
            await Task.yield()
        }
        submission.cancel()
        await submission.value

        #expect(!viewModel.actions.isSubmittingReply)
        #expect(viewModel.actions.replyErrorMessage == nil)
        #expect(viewModel.actions.replyDocument.markup == "保留的回复草稿")
        #expect(viewModel.actions.showsReplyComposer)
    }

    @Test func ngaReplyEmojiCatalogIncludesConfirmedResourceRanges() {
        let groups: [(NGAForumEmojiGroup, String, String, Int)] = [
            (.pt, "pt00.png", "pt64.png", 65),
            (.dt, "dt01.png", "dt33.png", 33),
            (.pg, "pg01.png", "pg15.png", 15)
        ]

        for (group, firstFilename, lastFilename, expectedCount) in groups {
            let items = group.items
            #expect(items.first?.filename == firstFilename)
            #expect(items.last?.filename == lastFilename)
            #expect(items.count == expectedCount)
            #expect(Set(items.map(\.filename)).count == expectedCount)
            #expect(items.first?.imageURL.absoluteString == "https://img4.nga.178.com/ngabbs/post/smile/\(firstFilename)")
        }
    }

    @Test func ngaReplyEmojiCatalogRecognizesAllGroupsAndRejectsUnknownImages() {
        let knownItems: [(String, NGAForumEmojiGroup)] = [
            ("ng_1.png", .ng),
            ("ac1.png", .ac),
            ("a2_01.png", .a2),
            ("pt00.png", .pt),
            ("dt01.png", .dt),
            ("pg01.png", .pg)
        ]

        for (filename, expectedGroup) in knownItems {
            #expect(NGAReplyEmojiCatalog.item(filename: filename)?.group == expectedGroup)
        }

        #expect(NGAReplyEmojiCatalog.item(filename: "pt65.png") == nil)
        #expect(NGAReplyEmojiCatalog.item(filename: "ordinary.png") == nil)
        #expect(ReplyComposerEmoji(markup: "[img]https://example.com/pt00.png[/img]") == nil)
        #expect(ReplyComposerEmoji(markup: "[img]https://img4.nga.178.com/ngabbs/post/smile/ordinary.png[/img]") == nil)
    }

    @Test func replyComposerDocumentRoundTripsNewEmojiGroupsAtCurrentSelection() throws {
        let items = try ["pt64.png", "dt33.png", "pg15.png"].map { filename in
            try #require(NGAReplyEmojiCatalog.item(filename: filename))
        }
        var document = ReplyComposerDocument(text: "前后")
        document.updateSelection(NSRange(location: 1, length: 0))

        for item in items {
            document.insert(emoji: ReplyComposerEmoji(item))
        }

        let expectedMiddle = items.map(\.markup).joined()
        #expect(document.markup == "前\(expectedMiddle)后")
        #expect(document.displayCharacterCount == 5)

        let restored = try items.map { item in
            try #require(ReplyComposerEmoji(markup: item.markup))
        }
        #expect(restored == items.map(ReplyComposerEmoji.init))
    }

    @Test func replyComposerDocumentInsertsToolbarTextAtCurrentSelection() {
        var document = ReplyComposerDocument(text: "前后")
        document.updateSelection(NSRange(location: 1, length: 0))

        document.insert(text: "@")

        #expect(document.markup == "前@后")
        #expect(document.selection == NSRange(location: 2, length: 0))
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
        #expect(thread.contentDocument.blocks.contains {
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
        #expect(NGAImageURLResolver.isForumEmoji(
            testURL("https://img4.nga.178.com/ngabbs/post/smile/ng_1.png")
        ))
        #expect(!NGAImageURLResolver.isForumEmoji(
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

        let blocks = NGABBCodeContentParser.parse(content).blocks

        #expect(blocks.count == 4)
        #expect(blocks[0].content == .text("第一段正文"))
        #expect(blocks[1].content == .image(testURL("https://img.nga.178.com/attachments/mon_202606/18/example-a.jpg")))
        #expect(blocks[2].content == .text("第二段正文"))
        #expect(blocks[3].content == .image(testURL("https://img.nga.178.com/attachments/mon_202606/18/example-b.webp")))
    }

    @Test func contentParserSupportsInlineBBCodeAndNGAImageURLVariants() throws {
        let content = "文字 [img]//img.nga.178.com/a.gif[/img] 说明 [图片] /attachments/mon_202607/b.jpg?name=a&amp;size=full"

        let blocks = NGABBCodeContentParser.parse(content).blocks

        #expect(blocks.count == 4)
        #expect(blocks[0].content == .text("文字"))
        #expect(blocks[1].content == .image(testURL("https://img.nga.178.com/a.gif")))
        #expect(blocks[2].content == .text("说明"))
        #expect(blocks[3].content == .image(testURL("https://img.nga.178.com/attachments/mon_202607/b.jpg?name=a&size=full")))
    }

    @Test func semanticParserPreservesSizedNGAImageTags() throws {
        let content = "正文[img=800x600]./mon_202607/10/k2Q66-4vjkZeT1kShs-13m.jpg[/img]结尾"

        let blocks = NGABBCodeContentParser.parse(content).blocks

        #expect(blocks.contains {
            if case let .image(url) = $0.content {
                return url.absoluteString == "https://img.nga.178.com/attachments/mon_202607/10/k2Q66-4vjkZeT1kShs-13m.jpg"
            }
            return false
        })
    }

    @Test func semanticParserRendersNGAEmojiMarkupWithoutDroppingContent() throws {
        let content = "好看吗[s:ac:哭笑] 来杯[s:ac:茶] [s:ac:未知表情]"
        let blocks = NGABBCodeContentParser.parse(content).blocks

        #expect(blocks[0].content == .text("好看吗"))
        #expect(blocks[1].content == .emoji(try #require(NGAForumEmojiResolver.resolve(markup: "[s:ac:哭笑]"))))
        #expect(blocks[2].content == .text("来杯"))
        #expect(blocks[3].content == .emoji(try #require(NGAForumEmojiResolver.resolve(markup: "[s:ac:茶]"))))
        #expect(blocks[4].content == .unsupported("[s:ac:未知表情]"))
    }

    @Test func contentParserPreservesNGARelativeMainPostImage() {
        let content = "主贴正文[img]./mon_202607/10/k2Q66-4vjkZeT1kShs-13m.jpg[/img]结尾"
        let blocks = NGABBCodeContentParser.parse(content).blocks

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
        #expect(thread.contentDocument.blocks.contains {
            if case let .image(url) = $0.content {
                return url.absoluteString == "https://img.nga.178.com/attachments/mon_202607/10/k2Q66-4vjkZeT1kShs-13m.jpg"
            }
            return false
        })
        #expect(thread.replies.count == 1)
    }

    @Test func ngaWebFallbackSelectsWholeDocumentWithoutCreatingWebReplies() throws {
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

        let unusableAPIThread = ForumThread(
            id: apiThread.id,
            title: apiThread.title,
            summary: "",
            author: apiThread.author,
            authorAvatarURL: apiThread.authorAvatarURL,
            createdAt: apiThread.createdAt,
            lastReplyAt: apiThread.lastReplyAt,
            replyCount: apiThread.replyCount,
            viewCount: apiThread.viewCount,
            body: "",
            replies: apiThread.replies,
            source: apiThread.source
        )
        let merged = try NGAThreadWebFallbackAssembler.assemble(
            apiThread: unusableAPIThread,
            webThread: webThread
        )

        #expect(merged.body.contains("网页补全第二段"))
        #expect(merged.body == webThread.body)
        #expect(merged.contentDocument.blocks.map(\.content) == webThread.contentDocument.blocks.map(\.content))
        #expect(merged.contentDocument.blocks.allSatisfy { block in
            guard let provenance = block.provenance else { return false }
            return merged.contentDocument.representations[provenance.representationIndex].origin == .ngaWeb
        })
        #expect(merged.replies.map(\.id) == apiThread.replies.map(\.id))
        #expect(merged.replies.map(\.body) == apiThread.replies.map(\.body))
        #expect(merged.replies.first?.contentDocument.diagnostics.contains {
            $0.code == .sourceConflict
        } == true)
        #expect(merged.contentDocument.markupFormat == .html)
        #expect(merged.contentDocument.representations.count == 2)
    }

    @Test func ngaSourcePolicyDoesNotCompareEquivalentImageRepresentationsWhenAPIIsValid() async throws {
        let apiDocument = NGABBCodeContentParser.parse(
            "API 正文\n[img]https://img.nga.178.com/attachments/mon_202607/10/shared.jpg[/img]"
        )
        let apiThread = ForumThread(
            id: 47151166,
            title: "图片去重测试",
            summary: "API 正文",
            author: "楼主",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: apiDocument.bodyText,
            contentDocument: apiDocument,
            replies: []
        )
        let webThread = ForumThread(
            id: 47151166,
            title: "图片去重测试",
            summary: "API 正文",
            author: "楼主",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "API 正文\n[图片] ./mon_202607/10/shared.jpg\n网页补全正文",
            replies: []
        )

        var webRequests = 0
        let resolved = try await NGAThreadContentSourcePolicy.resolve(apiThread: apiThread) {
            webRequests += 1
            return webThread
        }

        #expect(webRequests == 0)
        #expect(resolved.contentDocument.imageURLs.map(\.absoluteString) == [
            "https://img.nga.178.com/attachments/mon_202607/10/shared.jpg"
        ])
        #expect(!resolved.body.contains("网页补全正文"))
    }

    @Test func ngaThreadSourcePolicyPreservesValidAPIContentWithoutWebRequest() async throws {
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

        var webRequests = 0
        let resolved = try await NGAThreadContentSourcePolicy.resolve(apiThread: apiThread) {
            webRequests += 1
            return nil
        }

        #expect(resolved == apiThread)
        #expect(webRequests == 0)
        #expect(resolved.contentDocument.rawMarkup == apiThread.contentDocument.rawMarkup)
        #expect(resolved.replies == apiThread.replies)
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
        #expect(thread.contentDocument.imageURLs.count == 2)
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
        #expect(thread.contentDocument.imageURLs.count == 3)
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
            contentDocument: NGABBCodeContentParser.parse("权威回复正文")
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
            contentDocument: NGABBCodeContentParser.parse("主楼正文"),
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
            NGAImageURLResolver.resolve("http://img.nga.178.com/a.jpg")
                == testURL("https://img.nga.178.com/a.jpg")
        )
        #expect(
            NGAImageURLResolver.resolve("http://example.com/a.jpg")
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
        defaults.set(try JSONEncoder().encode([favorite]), forKey: "favorite-forum-threads-v1")
        defaults.set(try JSONEncoder().encode([history]), forKey: "forum-browsing-history-v1")

        #expect(FavoriteThreadsStore(defaults: defaults).entries == [favorite])
        #expect(BrowsingHistoryStore(defaults: defaults).entries == [history])

        let favoriteSnapshot = try JSONDecoder().decode(
            VersionedLocalSnapshot<[SavedForumThread]>.self,
            from: try #require(defaults.data(forKey: "favorite-forum-threads-v1"))
        )
        let historySnapshot = try JSONDecoder().decode(
            VersionedLocalSnapshot<[BrowsingHistoryEntry]>.self,
            from: try #require(defaults.data(forKey: "forum-browsing-history-v1"))
        )
        #expect(favoriteSnapshot.version == 1)
        #expect(historySnapshot.version == 1)
    }

    @Test func corruptedUserContentSnapshotsDegradeToEmptyState() throws {
        let suiteName = "ForumHubTests.corrupted-user-content.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corrupted = Data("not-json".utf8)
        defaults.set(corrupted, forKey: "favorite-forum-threads-v1")
        defaults.set(corrupted, forKey: "forum-browsing-history-v1")
        defaults.set(corrupted, forKey: "blocked-forum-users-v3")

        #expect(FavoriteThreadsStore(defaults: defaults).entries.isEmpty)
        #expect(BrowsingHistoryStore(defaults: defaults).entries.isEmpty)
        #expect(
            BlockedUsersStore(
                defaults: defaults,
                cloudStore: TestICloudKeyValueStore()
            ).blockedUsers.isEmpty
        )
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

        let cloudStore = TestICloudKeyValueStore()
        let store = BlockedUsersStore(defaults: defaults, cloudStore: cloudStore)
        store.block(source: .nga, username: "CJ")

        #expect(store.isBlocked(source: .nga, username: "cj"))
        #expect(!store.isBlocked(source: .v2ex, username: "cj"))
        #expect(store.filtering(ForumPayload.mock.threads).contains { $0.author == "CJ" } == false)

        let restored = BlockedUsersStore(defaults: defaults, cloudStore: cloudStore)
        #expect(restored.blockedUsers == [BlockedForumUser(source: .nga, username: "CJ")])

        restored.unblock(try #require(restored.blockedUsers.first))
        #expect(restored.blockedUsers.isEmpty)
    }

    @Test func blockedUsersMergeAcrossICloudStoresWithoutLosingIndependentChanges() throws {
        let firstSuite = "ForumHubTests.blocked-users.first.\(UUID().uuidString)"
        let secondSuite = "ForumHubTests.blocked-users.second.\(UUID().uuidString)"
        let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
        let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }
        let cloudStore = TestICloudKeyValueStore()
        let first = BlockedUsersStore(defaults: firstDefaults, cloudStore: cloudStore)
        #expect(cloudStore.setCount == 0)
        first.block(source: .nga, username: "Alice")

        let second = BlockedUsersStore(defaults: secondDefaults, cloudStore: cloudStore)
        #expect(second.isBlocked(source: .nga, username: "alice"))

        second.block(source: .v2ex, username: "Bob")
        first.refreshFromICloud()
        #expect(first.isBlocked(source: .nga, username: "Alice"))
        #expect(first.isBlocked(source: .v2ex, username: "Bob"))

        second.unblock(BlockedForumUser(source: .nga, username: "Alice"))
        first.refreshFromICloud()
        #expect(!first.isBlocked(source: .nga, username: "Alice"))
        #expect(first.isBlocked(source: .v2ex, username: "Bob"))
    }

    @Test func blockedUsersInitializationNeverWritesWholeLocalSnapshotBackToICloud() throws {
        let suiteName = "ForumHubTests.blocked-users-stale.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cloudStore = TestICloudKeyValueStore()
        let first = BlockedUsersStore(defaults: defaults, cloudStore: cloudStore)
        first.block(source: .nga, username: "Local")
        cloudStore.seed(BlockedUserSyncRecord(
            source: .v2ex,
            username: "Remote",
            isBlocked: true,
            updatedAt: .now
        ))
        let writesBeforeRestore = cloudStore.setCount

        let restored = BlockedUsersStore(defaults: defaults, cloudStore: cloudStore)

        #expect(cloudStore.setCount == writesBeforeRestore)
        #expect(restored.isBlocked(source: .nga, username: "Local"))
        #expect(restored.isBlocked(source: .v2ex, username: "Remote"))
    }

    @Test func blockedUsersAccountChangeDiscardsPreviousAccountCache() throws {
        let suiteName = "ForumHubTests.blocked-users-account.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cloudStore = TestICloudKeyValueStore()
        let store = BlockedUsersStore(defaults: defaults, cloudStore: cloudStore)
        store.block(source: .nga, username: "OldAccount")
        cloudStore.removeAllValues()
        cloudStore.seed(BlockedUserSyncRecord(
            source: .v2ex,
            username: "NewAccount",
            isBlocked: true,
            updatedAt: .now
        ))

        store.handleICloudChange(reason: NSUbiquitousKeyValueStoreAccountChange)

        #expect(!store.isBlocked(source: .nga, username: "OldAccount"))
        #expect(store.isBlocked(source: .v2ex, username: "NewAccount"))
    }

    @Test func blockedUsersSurfacesQuotaViolationWithoutLosingLocalChange() throws {
        let suiteName = "ForumHubTests.blocked-users-quota.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BlockedUsersStore(defaults: defaults, cloudStore: TestICloudKeyValueStore())
        store.block(source: .nga, username: "Local")

        store.handleICloudChange(reason: NSUbiquitousKeyValueStoreQuotaViolationChange)

        #expect(store.isBlocked(source: .nga, username: "Local"))
        #expect(store.iCloudSyncState == .failed("iCloud 屏蔽名单已达到同步容量上限，新修改仅保存在本机。"))
    }

    @Test func synchronizableKeychainStoreUpdatesWithoutDeletingExistingItem() throws {
        let access = TestKeychainDataAccess()
        access.storedData = Data("old".utf8)
        let store = SynchronizableKeychainStore(service: "test", account: "account", access: access)

        try store.save(Data("new".utf8))

        #expect(access.updateCount == 1)
        #expect(access.addCount == 0)
        #expect(access.deleteCount == 0)
        #expect(access.storedData == Data("new".utf8))
    }

    @Test func synchronizableKeychainStoreAddsOnlyWhenItemDoesNotExist() throws {
        let access = TestKeychainDataAccess()
        let store = SynchronizableKeychainStore(service: "test", account: "account", access: access)

        try store.save(Data("new".utf8))

        #expect(access.updateCount == 1)
        #expect(access.addCount == 1)
        #expect(access.deleteCount == 0)
        #expect(access.storedData == Data("new".utf8))
    }

    @Test func synchronizableKeychainStorePreservesExistingItemWhenUpdateFails() {
        let access = TestKeychainDataAccess()
        access.storedData = Data("old".utf8)
        access.updateStatus = errSecInteractionNotAllowed
        let store = SynchronizableKeychainStore(service: "test", account: "account", access: access)

        #expect(throws: SynchronizableKeychainError.operationFailed(errSecInteractionNotAllowed)) {
            try store.save(Data("new".utf8))
        }
        #expect(access.addCount == 0)
        #expect(access.deleteCount == 0)
        #expect(access.storedData == Data("old".utf8))
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
        let linuxDoThread = ForumThread(
            id: ngaThread.id,
            title: "LINUX DO 不支持远端收藏",
            summary: "",
            author: "linuxdo-user",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "",
            replies: [],
            source: .linuxDo
        )

        let store = FavoriteThreadsStore(defaults: defaults)
        store.save(ngaThread)
        store.save(v2exThread)
        store.save(linuxDoThread)

        #expect(store.contains(ngaThread))
        #expect(store.contains(v2exThread))
        #expect(store.entries.count == 2)
        #expect(!store.contains(linuxDoThread))

        let restored = FavoriteThreadsStore(defaults: defaults)
        #expect(restored.entries.count == 2)
        #expect(restored.entries.map(\.source) == [.v2ex, .nga])
        #expect(restored.entries.allSatisfy { $0.thread.body.isEmpty })
        #expect(restored.entries.allSatisfy { $0.thread.contentDocument.bodyText.isEmpty })

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
        let imageURLs = mediaReply.contentDocument.imageURLs
        #expect(imageURLs.map(\.absoluteString) == [
            "https://img.nga.178.com/attachments/page-2.gif",
            "https://img.nga.178.com/attachments/mon_202607/page-2.jpg?name=a&size=full"
        ])

        let quotedReply = try #require(page.replies.last)
        #expect(quotedReply.contentDocument.rawMarkup.contains("./mon_202607/quoted-image.jpg"))
        #expect(quotedReply.contentDocument.bodyText.contains("quoted-image.jpg"))
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
                Reply(id: 101, sourcePostID: 1001, author: "用户 A", createdAt: "10:00", body: "已有回复"),
                Reply(id: 102, sourcePostID: 1002, author: "用户 B", createdAt: "10:01", body: "最后一条旧回复")
            ],
            replyCount: 4
        )
        let continuationThread = paginationThread(
            replies: [
                Reply(id: 0, author: "楼主", createdAt: "09:00", body: "首楼内容"),
                Reply(id: 102, sourcePostID: 1002, author: "用户 B", createdAt: "10:01", body: "最后一条旧回复"),
                Reply(id: 202, sourcePostID: 1001, author: "用户 A", createdAt: "10:00", body: "已有回复"),
                Reply(id: 203, sourcePostID: 1003, author: "用户 C", createdAt: "10:02", body: "新的回复")
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

    @Test func paginationMergerPreservesEqualContentWithDifferentStablePostIdentity() {
        let currentThread = paginationThread(
            replies: [
                Reply(id: 101, sourcePostID: 1001, author: "同一用户", createdAt: "10:00", body: "重复内容")
            ],
            replyCount: 2
        )
        let continuationThread = paginationThread(
            replies: [
                Reply(id: 102, sourcePostID: 1002, author: "同一用户", createdAt: "10:00", body: "重复内容")
            ],
            replyCount: 2
        )

        let result = ThreadDetailPaginationMerger.merge(
            currentThread: currentThread,
            continuationThread: continuationThread,
            replyTotalCount: 2
        )

        #expect(result.thread.replies.map(\.sourcePostID) == [1001, 1002])
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
            contentDocument: NGABBCodeContentParser.parse("权威主楼正文"),
            replies: []
        )
        let repeatedMainPost = Reply(
            id: 0,
            author: "楼主",
            createdAt: "",
            body: "不同的旧回复投影",
            contentDocument: NGABBCodeContentParser.parse("权威主楼正文")
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
        #expect(topic.channelID == 17)
        #expect(topic.channelTitle == "分享创造")
        #expect(topic.replyCount == 12)
        #expect(topic.createdAtDate != nil)
        #expect(topic.lastReplyAtDate != nil)
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

    @Test func v2exThreadDetailMapsRenderedImagesToSemanticContentBlocks() throws {
        let topic = V2EXTopicDTO(
            id: 42,
            title: "测试主题",
            content: "首楼原文",
            contentRendered: #"<p>首楼正文</p><img src="//i.imgur.com/topic.png">"#,
            replies: 1,
            created: nil,
            lastTouched: nil,
            member: V2EXMemberDTO(id: 1, username: "alice", avatarNormal: nil)
        )
        let replies = [
            V2EXReplyDTO(
                id: 7,
                content: "回复原文",
                contentRendered: #"<p>图片之前</p><img src="https://i.imgur.com/reply.png"><p>图片之后</p>"#,
                created: nil,
                member: V2EXMemberDTO(id: 2, username: "bob", avatarNormal: nil)
            )
        ]

        let thread = V2EXMapper.threadDetail(topic: topic, replies: replies)
        let reply = try #require(thread.replies.first)

        #expect(thread.contentDocument.markupFormat == .html)
        #expect(thread.contentDocument.imageURLs.map(\.absoluteString) == ["https://i.imgur.com/topic.png"])
        #expect(reply.contentDocument.markupFormat == .html)
        #expect(reply.contentDocument.blocks.map(\.kind) == [.paragraph, .image, .paragraph])
        #expect(reply.contentDocument.imageURLs.map(\.absoluteString) == ["https://i.imgur.com/reply.png"])
        #expect(reply.body.contains("图片之前"))
        #expect(reply.body.contains("[图片] https://i.imgur.com/reply.png"))
        #expect(reply.body.contains("图片之后"))
    }

    @Test func v2exThreadDetailResolvesExplicitFloorAndAuthorReference() throws {
        let topic = V2EXTopicDTO(
            id: 42,
            title: "测试主题",
            content: "主楼",
            contentRendered: nil,
            replies: 2,
            created: nil,
            lastTouched: nil,
            member: V2EXMemberDTO(id: 1, username: "owner", avatarNormal: nil)
        )
        let replies = [
            V2EXReplyDTO(
                id: 101,
                content: "根回复",
                contentRendered: nil,
                created: nil,
                member: V2EXMemberDTO(id: 2, username: "alice", avatarNormal: nil)
            ),
            V2EXReplyDTO(
                id: 102,
                content: "@alice #1 回复内容",
                contentRendered: "<p><a href=\"/member/alice\">@alice</a> #1 <strong>回复内容</strong></p>",
                created: nil,
                member: V2EXMemberDTO(id: 3, username: "bob", avatarNormal: nil)
            )
        ]

        let thread = V2EXMapper.threadDetail(topic: topic, replies: replies)
        let child = try #require(thread.replies.last)

        #expect(thread.replies.map(\.floorNumber) == [1, 2])
        #expect(child.conversation?.parentReplyID == 101)
        #expect(child.conversation?.resolution == .explicitFloorAndAuthor)
        #expect(child.conversation?.referencedUsername == "alice")
        #expect(child.conversation?.referencedFloor == 1)
        #expect(child.conversation?.verifiedLeadingPrefix == "@alice #1")
        #expect(child.body.contains("回复内容"))
    }

    @Test func v2exThreadDetailInfersNearestPreviousAuthor() throws {
        let topic = V2EXTopicDTO(
            id: 43,
            title: "测试主题",
            content: "主楼",
            contentRendered: nil,
            replies: 5,
            created: nil,
            lastTouched: nil,
            member: V2EXMemberDTO(id: 1, username: "owner", avatarNormal: nil)
        )
        let replies = [
            (201, "alice", "第一条"),
            (202, "bob", "普通回复"),
            (203, "alice", "第二条"),
            (204, "carol", "@alice 最近回复"),
            (205, "alice", "@alice 自己补充")
        ].map { id, author, content in
            V2EXReplyDTO(
                id: id,
                content: content,
                contentRendered: nil,
                created: nil,
                member: V2EXMemberDTO(id: id, username: author, avatarNormal: nil)
            )
        }

        let mapped = V2EXMapper.threadDetail(topic: topic, replies: replies).replies

        #expect(mapped[3].conversation?.parentReplyID == 203)
        #expect(mapped[3].conversation?.resolution == .nearestPreviousAuthor)
        #expect(mapped[4].conversation?.parentReplyID == 203)
        #expect(mapped[4].conversation?.resolution == .nearestPreviousAuthor)
    }

    @Test func v2exThreadDetailHandlesConflictingAmbiguousAndMissingReferences() throws {
        let topic = V2EXTopicDTO(
            id: 44,
            title: "测试主题",
            content: "主楼",
            contentRendered: nil,
            replies: 8,
            created: nil,
            lastTouched: nil,
            member: V2EXMemberDTO(id: 1, username: "owner", avatarNormal: nil)
        )
        let inputs = [
            (301, "alice", "根回复"),
            (302, "bob", "另一回复"),
            (303, "carol", "@alice #2 冲突楼层"),
            (304, "dave", "@alice @bob 多用户歧义"),
            (305, "erin", "@alice @bob #2 唯一显式目标"),
            (306, "frank", "@missing 无匹配"),
            (307, "grace", "@alice #99 未来或缺失楼层"),
            (308, "alice", "@alice 自己回复之前的消息")
        ]
        let replies = inputs.map { id, author, content in
            V2EXReplyDTO(
                id: id,
                content: content,
                contentRendered: nil,
                created: nil,
                member: V2EXMemberDTO(id: id, username: author, avatarNormal: nil)
            )
        }

        let mapped = V2EXMapper.threadDetail(topic: topic, replies: replies).replies

        #expect(mapped[2].conversation?.parentReplyID == 301)
        #expect(mapped[2].conversation?.resolution == .floorAuthorMismatchFallback)
        #expect(mapped[2].conversation?.verifiedLeadingPrefix == nil)
        #expect(mapped[3].conversation == nil)
        #expect(mapped[4].conversation?.parentReplyID == 302)
        #expect(mapped[4].conversation?.resolution == .explicitFloorAndAuthor)
        #expect(mapped[5].conversation == nil)
        #expect(mapped[6].conversation == nil)
        #expect(mapped[7].conversation?.parentReplyID == 301)
    }

    @Test func v2exReplyForestPreservesRepresentativeBranchesAndIdentity() throws {
        func reply(_ id: Int, parent: Int? = nil) -> Reply {
            Reply(
                id: id,
                sourcePostID: id,
                author: "user\(id)",
                createdAt: "",
                body: "reply\(id)",
                floorNumber: id,
                conversation: parent.map {
                    ReplyConversation(
                        parentReplyID: $0,
                        referencedUsername: "user\($0)",
                        referencedFloor: $0,
                        resolution: .explicitFloorAndAuthor,
                        verifiedLeadingPrefix: "@user\($0) #\($0)"
                    )
                }
            )
        }

        let replies = [
            reply(7), reply(24, parent: 7), reply(32, parent: 24),
            reply(35, parent: 32), reply(38, parent: 35),
            reply(42, parent: 7), reply(112, parent: 42), reply(115, parent: 42),
            reply(200, parent: 999)
        ]

        let roots = ThreadDetailReplyForestBuilder.build(from: replies)
        let flattened = ThreadDetailReplyForestBuilder.flatten(roots)

        #expect(roots.map(\.reply.id) == [7, 200])
        #expect(roots[0].children.map(\.reply.id) == [24, 42])
        #expect(roots[0].children[0].children[0].reply.id == 32)
        #expect(roots[0].children[1].children.map(\.reply.id) == [112, 115])
        #expect(flattened.map(\.reply.id) == [7, 24, 32, 35, 38, 42, 112, 115, 200])
        #expect(Set(flattened.map(\.reply.id)).count == replies.count)
        #expect(flattened.first(where: { $0.reply.id == 38 })?.depth == 4)
        #expect(flattened.first(where: { $0.reply.id == 38 })?.visualDepth == 3)
    }

    @Test func threadDetailPresentationCombinesV2EXTreeFlatFilterAndReverseModes() {
        let rootOne = Reply(id: 1, author: "owner", createdAt: "", body: "root", floorNumber: 1)
        let childOne = Reply(
            id: 2,
            author: "other",
            createdAt: "",
            body: "@owner #1 child",
            floorNumber: 2,
            conversation: ReplyConversation(
                parentReplyID: 1,
                referencedUsername: "owner",
                referencedFloor: 1,
                resolution: .explicitFloorAndAuthor,
                verifiedLeadingPrefix: "@owner #1"
            )
        )
        let rootTwo = Reply(id: 3, author: "owner", createdAt: "", body: "root two", floorNumber: 3)
        let thread = ForumThread(
            id: 99,
            title: "V2EX tree",
            summary: "",
            author: "owner",
            lastReplyAt: "",
            replyCount: 3,
            viewCount: 0,
            body: "main",
            replies: [rootOne, childOne, rootTwo],
            source: .v2ex
        )

        let tree = ThreadDetailPresentationBuilder.displayedReplies(
            thread: thread,
            showsOnlyThreadAuthor: false,
            showsRepliesInReverseOrder: false,
            source: .v2ex,
            usesThreadedV2EXPresentation: true,
            isBlocked: { _, _ in false }
        )
        let reverseTree = ThreadDetailPresentationBuilder.displayedReplies(
            thread: thread,
            showsOnlyThreadAuthor: false,
            showsRepliesInReverseOrder: true,
            source: .v2ex,
            usesThreadedV2EXPresentation: true,
            isBlocked: { _, _ in false }
        )
        let onlyAuthor = ThreadDetailPresentationBuilder.displayedReplies(
            thread: thread,
            showsOnlyThreadAuthor: true,
            showsRepliesInReverseOrder: false,
            source: .v2ex,
            usesThreadedV2EXPresentation: true,
            isBlocked: { _, _ in false }
        )
        let entries = ThreadDetailPresentationBuilder.displayedReplyEntries(
            displayedReplies: tree,
            allReplies: thread.replies,
            pageStartReplyIndices: [1: 0],
            supportsDirectPagination: false,
            pageSize: 20,
            prefetchReplyDistance: 3,
            usesThreadedPresentation: true
        )

        #expect(tree.map(\.id) == [1, 2, 3])
        #expect(reverseTree.map(\.id) == [3, 1, 2])
        #expect(onlyAuthor.map(\.id) == [1, 3])
        #expect(entries.map(\.visualDepth) == [0, 1, 0])
        #expect(entries[1].displayedContentDocument.bodyText == "child")
        #expect(entries[1].reply.body == "@owner #1 child")

        let ngaReplies = ThreadDetailPresentationBuilder.displayedReplies(
            thread: thread,
            showsOnlyThreadAuthor: false,
            showsRepliesInReverseOrder: false,
            source: .nga,
            usesThreadedV2EXPresentation: true,
            isBlocked: { _, _ in false }
        )
        #expect(ngaReplies.map(\.id) == [1, 2, 3])
    }

    @Test func v2exThreadedReplyFixtureBuildsDocumentedConversation() throws {
        struct Fixture: Decodable {
            struct Item: Decodable {
                let floor: Int
                let id: Int
                let author: String
                let content: String
            }
            let replies: [Item]
        }

        let bundle = Bundle(for: FixtureLocator.self)
        let fixtureURL = try #require(
            bundle.url(
                forResource: "v2ex-threaded-replies-1227563-shape",
                withExtension: "json",
                subdirectory: "Fixtures"
            ) ?? bundle.url(
                forResource: "v2ex-threaded-replies-1227563-shape",
                withExtension: "json"
            )
        )
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL))
        let candidates = fixture.replies.map { item in
            V2EXMappedReplyCandidate(
                reply: Reply(
                    id: item.id,
                    sourcePostID: item.id,
                    author: item.author,
                    createdAt: "",
                    body: item.content,
                    floorNumber: item.floor
                ),
                reference: V2EXReplyReferenceExtractor.extract(from: item.content)
            )
        }
        let resolved = V2EXReplyRelationshipResolver.resolve(candidates)
        let byFloor = Dictionary(uniqueKeysWithValues: resolved.compactMap { reply in
            reply.floorNumber.map { ($0, reply) }
        })
        let flattened = ThreadDetailReplyForestBuilder.flatten(
            ThreadDetailReplyForestBuilder.build(from: resolved)
        )

        #expect(byFloor[24]?.conversation?.parentReplyID == byFloor[7]?.id)
        #expect(byFloor[32]?.conversation?.parentReplyID == byFloor[24]?.id)
        #expect(byFloor[35]?.conversation?.parentReplyID == byFloor[32]?.id)
        #expect(byFloor[38]?.conversation?.parentReplyID == byFloor[35]?.id)
        #expect(byFloor[42]?.conversation?.parentReplyID == byFloor[7]?.id)
        #expect(byFloor[112]?.conversation?.parentReplyID == byFloor[42]?.id)
        #expect(byFloor[115]?.conversation?.parentReplyID == byFloor[42]?.id)
        #expect(byFloor[116]?.conversation?.resolution == .floorAuthorMismatchFallback)
        #expect(byFloor[117]?.conversation == nil)
        #expect(byFloor[118]?.conversation == nil)
        #expect(Set(flattened.map(\.reply.id)).count == resolved.count)
    }

    @Test func v2exRenderedContentFallbackAndContentReplacementPreserveConversation() throws {
        let topic = V2EXTopicDTO(
            id: 45,
            title: "测试主题",
            content: "主楼",
            contentRendered: nil,
            replies: 2,
            created: nil,
            lastTouched: nil,
            member: V2EXMemberDTO(id: 1, username: "owner", avatarNormal: nil)
        )
        let replies = [
            V2EXReplyDTO(
                id: 401,
                content: "根回复",
                contentRendered: nil,
                created: nil,
                member: V2EXMemberDTO(id: 2, username: "alice", avatarNormal: nil)
            ),
            V2EXReplyDTO(
                id: 402,
                content: nil,
                contentRendered: "<p>@alice #1 <strong>HTML 回退</strong></p>",
                created: nil,
                member: V2EXMemberDTO(id: 3, username: "bob", avatarNormal: nil)
            )
        ]

        let child = try #require(V2EXMapper.threadDetail(topic: topic, replies: replies).replies.last)
        let replaced = child.replacingContent(with: .plainText("替换后的正文"))

        #expect(child.conversation?.parentReplyID == 401)
        #expect(child.body.contains("HTML 回退"))
        #expect(replaced.conversation == child.conversation)
        #expect(replaced.body == "替换后的正文")
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
        <a href="/go/qna">问与答</a>
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
        #expect(page.topics.first?.node?.name == "qna")
        #expect(page.topics.first?.node?.title == "问与答")
        #expect(page.hasNextPage)
    }

    @Test func v2exNodePageParserAcceptsRealQnaAndAll4allShapes() throws {
        let qna = V2EXRecentPageParser.parse(data: try fixtureData("v2ex-node-qna-shape", fileExtension: "html"))
        let all4all = V2EXRecentPageParser.parse(data: try fixtureData("v2ex-node-all4all-shape", fileExtension: "html"))

        #expect(qna.topics.map(\.id) == [810_001])
        #expect(qna.topics.first?.title == "如何安全地测试节点页？")
        #expect(qna.topics.first?.member?.username == "qna_author")
        #expect(qna.topics.first?.replies == 12)
        #expect(qna.hasNextPage)

        #expect(all4all.topics.map(\.id) == [820_002])
        #expect(all4all.topics.first?.title == "出一个脱敏测试物品 & 配件")
        #expect(all4all.topics.first?.member?.username == "trader")
        #expect(all4all.topics.first?.replies == 3)
        #expect(all4all.hasNextPage)
    }

    @Test func v2exNodePageParserIgnoresTopicLinksOutsideItems() {
        let html = Data(#"<html><body><a href="/t/10686">节点说明主题</a><div id="TopicsNode"><div class="cell from_1 t_123456"></div></div><a href="/t/999999">列表后的导航主题</a></body></html>"#.utf8)

        let page = V2EXRecentPageParser.parse(data: html)

        #expect(page.topics.isEmpty)
        #expect(!page.hasNextPage)
    }

    private func fixtureData(_ name: String, fileExtension: String) throws -> Data {
        let bundle = Bundle(for: FixtureLocator.self)
        let url = try #require(
            bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: fileExtension)
        )
        return try Data(contentsOf: url)
    }

    @Test func v2exFavoriteActionParserAcceptsOnlyMatchingSameOriginAction() throws {
        let html = Data("""
        <a href="/favorite/topic/1226835?once=71692">加入收藏</a>
        <a href="https://example.com/favorite/topic/1226835?once=stolen">外部链接</a>
        <a href="/favorite/topic/9?once=wrong-topic">其他主题</a>
        """.utf8)

        let actionURL = try #require(
            V2EXFavoriteActionParser.actionURL(.add, threadID: 1_226_835, data: html)
        )

        #expect(actionURL.absoluteString == "https://www.v2ex.com/favorite/topic/1226835?once=71692")
        #expect(V2EXFavoriteActionParser.actionURL(.remove, threadID: 1_226_835, data: html) == nil)
        #expect(!V2EXFavoriteActionParser.isAlreadyApplied(.add, threadID: 1_226_835, data: html))
        #expect(V2EXFavoriteActionParser.isAlreadyApplied(.remove, threadID: 1_226_835, data: html))
    }

    @Test func v2exFavoriteActionParserRecognizesAppliedFavoriteState() {
        let html = Data(#"<a href='/unfavorite/topic/42?once=123&amp;next=/my/topics'>取消收藏</a>"#.utf8)

        #expect(V2EXFavoriteActionParser.isAlreadyApplied(.add, threadID: 42, data: html))
        #expect(
            V2EXFavoriteActionParser.actionURL(.remove, threadID: 42, data: html)?.absoluteString
                == "https://www.v2ex.com/unfavorite/topic/42?once=123&next=/my/topics"
        )
    }

    @Test func v2exFavoritePageParserExtractsTopicsAndPagination() {
        let html = Data("""
        <html><body>
        <div class="cell item"><img class="avatar" alt="alice" />
        <a href="/t/42#reply3" class="topic-link">收藏主题</a>
        <a class="count_livid">3</a></div>
        <a href="/my/topics?p=2">2</a>
        </body></html>
        """.utf8)

        let page = V2EXFavoritePageParser.parse(data: html, page: 1)

        #expect(page.topics.map(\.id) == [42])
        #expect(page.topics.first?.member?.username == "alice")
        #expect(page.hasNextPage)
    }

}

private final class FixtureLocator {}

private struct SuspendedReplyRepository: ThreadRepository {
    private let base = MockThreadRepository(source: .v2ex)

    var source: ForumSource { base.source }
    var capabilities: ForumCapabilities { base.capabilities }
    var defaultChannel: ForumChannel { base.defaultChannel }

    func fetchChannels() async throws -> [ForumChannel] { try await base.fetchChannels() }
    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        try await base.fetchForum(channel: channel, page: page)
    }
    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult { try await base.fetchHotThreads(page: page) }
    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult { try await base.fetchFavoriteThreads(page: page) }
    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult {
        try await base.searchThreads(query: query, page: page)
    }
    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult {
        try await base.fetchThread(tid: tid, page: page)
    }
    func addFavoriteThread(tid: Int) async throws { try await base.addFavoriteThread(tid: tid) }
    func removeFavoriteThread(tid: Int) async throws { try await base.removeFavoriteThread(tid: tid) }
    func replyThread(
        tid: Int,
        target: ThreadReplyTarget,
        content: String,
        attachments: [ReplyAttachmentUpload]
    ) async throws {
        try await Task.sleep(for: .seconds(60))
    }
}

@MainActor
private final class TestICloudKeyValueStore: ICloudKeyValueStoring {
    private var values: [String: Any] = [:]
    private(set) var setCount = 0

    var dictionaryRepresentation: [String: Any] { values }

    func data(forKey key: String) -> Data? {
        values[key] as? Data
    }

    func set(_ value: Any?, forKey key: String) {
        setCount += 1
        values[key] = value
    }

    func removeObject(forKey key: String) {
        values.removeValue(forKey: key)
    }

    func seed(_ record: BlockedUserSyncRecord) {
        values[BlockedUserCloudCodec.key(for: record.id)] = BlockedUserCloudCodec.encode(record)
    }

    func removeAllValues() {
        values = [:]
    }

    func synchronize() -> Bool {
        true
    }
}

private final class TestKeychainDataAccess: KeychainDataAccessing {
    var storedData: Data?
    var updateStatus: OSStatus = errSecSuccess
    private(set) var updateCount = 0
    private(set) var addCount = 0
    private(set) var deleteCount = 0

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        updateCount += 1
        guard updateStatus == errSecSuccess else { return updateStatus }
        guard storedData != nil else { return errSecItemNotFound }
        storedData = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func add(attributes: [String: Any]) -> OSStatus {
        addCount += 1
        storedData = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func loadData(query: [String: Any]) -> (OSStatus, Data?) {
        storedData.map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
    }

    func delete(query: [String: Any]) -> OSStatus {
        deleteCount += 1
        storedData = nil
        return errSecSuccess
    }
}
