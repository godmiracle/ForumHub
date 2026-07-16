import Foundation
import Testing
@testable import ForumHub

@MainActor
struct NGAThreadContentSourcePolicyTests {
    @Test func validAPIThreadDoesNotRequestWeb() async throws {
        let apiThread = ForumThread(
            id: 47,
            title: "API 标题",
            summary: "API 正文",
            author: "作者",
            lastReplyAt: "",
            replyCount: 0,
            viewCount: 0,
            body: "API 正文",
            replies: []
        )
        var webRequestCount = 0

        let resolved = try await NGAThreadContentSourcePolicy.resolve(apiThread: apiThread) {
            webRequestCount += 1
            return nil
        }

        #expect(resolved == apiThread)
        #expect(webRequestCount == 0)
    }

    @Test func degradedAPIThreadDoesNotRequestWeb() async throws {
        let document = NGABBCodeContentParser.parse("可读正文 [future]保留[/future]")
        let apiThread = makeThread(document: document)
        var webRequestCount = 0

        let resolved = try await NGAThreadContentSourcePolicy.resolve(apiThread: apiThread) {
            webRequestCount += 1
            return nil
        }

        #expect(document.quality == .degraded)
        #expect(resolved == apiThread)
        #expect(webRequestCount == 0)
    }

    @Test func continuationPageWithUsableRepliesDoesNotTreatMissingMainPostAsUnusable() async throws {
        let reply = Reply(
            id: 7001,
            sourcePostID: 7001,
            author: "回复作者",
            createdAt: "回复时间",
            body: "第二页正文",
            floorNumber: 20
        )
        let apiThread = makeThread(document: .plainText(""), replies: [reply], replyCount: 23)
        var webRequestCount = 0

        let resolved = try await NGAThreadContentSourcePolicy.resolve(
            apiThread: apiThread,
            requestedPage: 2
        ) {
            webRequestCount += 1
            return nil
        }

        #expect(resolved == apiThread)
        #expect(webRequestCount == 0)
    }

    @Test func unusableAPIThreadRequestsWebOnceAndSelectsWholeWebDocument() async throws {
        let apiThread = makeThread(document: .plainText(""), title: "API 标题", author: "API 作者")
        let webDocument = NGAHTMLContentParser.parse("网页第一段<br>网页第二段")
        let webThread = makeThread(document: webDocument, title: "Web 标题", author: "Web 作者")
        var webRequestCount = 0

        let resolved = try await NGAThreadContentSourcePolicy.resolve(apiThread: apiThread) {
            webRequestCount += 1
            return webThread
        }

        #expect(webRequestCount == 1)
        #expect(resolved.title == "API 标题")
        #expect(resolved.author == "API 作者")
        #expect(resolved.body == webDocument.bodyText)
        #expect(resolved.contentDocument.representations.count == 2)
        for block in resolved.contentDocument.blocks {
            let provenance = try #require(block.provenance)
            #expect(resolved.contentDocument.representations[provenance.representationIndex].origin == .ngaWeb)
        }
    }

    @Test func productionParsersCarryUnusableMainPostIntoWholeDocumentFallback() async throws {
        let apiData = try fixtureData(named: "nga-thread-api-content-unusable", extension: "json")
        let apiThread = try #require(ThreadDetailParser.parse(
            data: apiData,
            fallbackText: String(decoding: apiData, as: UTF8.self),
            tid: 9001
        ))
        let webHTML = String(
            decoding: try fixtureData(named: "nga-thread-web-valid-fallback", extension: "html"),
            as: UTF8.self
        )
        let webThread = try #require(WebForumParser.parseThreadHTML(webHTML, tid: 9001))
        var webRequestCount = 0

        #expect(apiThread.contentDocument.quality == .unusable)
        let resolved = try await NGAThreadContentSourcePolicy.resolve(apiThread: apiThread) {
            webRequestCount += 1
            return webThread
        }

        #expect(webRequestCount == 1)
        #expect(resolved.id == 9001)
        #expect(resolved.title == "API 空正文样本")
        #expect(resolved.author == "楼主")
        #expect(resolved.body == webThread.body)
    }

    @Test func productionParsersCarryUnusableReplyIdentityIntoSameFloorFallback() async throws {
        let apiData = try fixtureData(named: "nga-thread-api-unusable-reply", extension: "json")
        let apiThread = try #require(ThreadDetailParser.parse(
            data: apiData,
            fallbackText: String(decoding: apiData, as: UTF8.self),
            tid: 9002
        ))
        let apiReply = try #require(apiThread.replies.first)
        let webHTML = String(
            decoding: try fixtureData(named: "nga-thread-web-valid-reply-fallback", extension: "html"),
            as: UTF8.self
        )
        let webThread = try #require(WebForumParser.parseThreadHTML(webHTML, tid: 9002))

        #expect(apiReply.contentDocument.quality == .unusable)
        let resolved = try await NGAThreadContentSourcePolicy.resolve(apiThread: apiThread) { webThread }
        let resolvedReply = try #require(resolved.replies.first)

        #expect(resolvedReply.id == 9102)
        #expect(resolvedReply.sourcePostID == 9102)
        #expect(resolvedReply.author == "API 回复作者")
        #expect(resolvedReply.createdAt == "API 回复时间")
        #expect(resolvedReply.floorNumber == 1)
        #expect(resolvedReply.body == "Web 可读回复")
    }

    @Test func fetchedWebDifferencesKeepValidAPIContentAndRecordConflict() async throws {
        let validAPIReply = Reply(
            id: 7101,
            sourcePostID: 7101,
            author: "API 作者 1",
            createdAt: "API 时间 1",
            body: "API 有效回复",
            floorNumber: 1
        )
        let unusableAPIReply = Reply(
            id: 7102,
            sourcePostID: 7102,
            author: "API 作者 2",
            createdAt: "API 时间 2",
            body: "",
            contentDocument: .plainText(""),
            floorNumber: 2
        )
        let apiThread = makeThread(
            document: .plainText("API 有效主楼"),
            replies: [validAPIReply, unusableAPIReply]
        )
        let webThread = makeThread(
            document: .plainText("Web 不同主楼"),
            replies: [
                Reply(id: 8101, author: "Web 作者 1", createdAt: "Web 时间 1", body: "Web 不同回复", floorNumber: 1),
                Reply(id: 8102, author: "Web 作者 2", createdAt: "Web 时间 2", body: "Web 回退回复", floorNumber: 2)
            ]
        )

        let resolved = try await NGAThreadContentSourcePolicy.resolve(apiThread: apiThread) { webThread }
        let retainedReply = try #require(resolved.replies.first)
        let fallbackReply = try #require(resolved.replies.last)

        #expect(resolved.body == "API 有效主楼")
        #expect(resolved.contentDocument.diagnostics.contains { $0.code == .sourceConflict })
        #expect(retainedReply.body == "API 有效回复")
        #expect(retainedReply.contentDocument.diagnostics.contains { $0.code == .sourceConflict })
        #expect(fallbackReply.body == "Web 回退回复")
        let diagnosticMessages = (
            resolved.contentDocument.diagnostics + retainedReply.contentDocument.diagnostics
        ).map(\.safeMessage).joined()
        #expect(!diagnosticMessages.contains("API 有效主楼"))
        #expect(!diagnosticMessages.contains("Web 不同主楼"))
    }

    @Test func unusableAPIAndWebReturnTypedContentError() async {
        let apiThread = makeThread(document: .plainText(""))

        await #expect(throws: NGAThreadSourceError.contentUnavailable) {
            try await NGAThreadContentSourcePolicy.resolve(apiThread: apiThread) {
                self.makeThread(document: .plainText(""))
            }
        }
    }

    @Test func sameFloorFallbackKeepsAPIIdentityAndIgnoresWebOnlyReplies() async throws {
        let apiReply = Reply(
            id: 7001,
            sourcePostID: 7001,
            author: "API 回复作者",
            createdAt: "API 时间",
            body: "",
            contentDocument: .plainText(""),
            floorNumber: 1
        )
        let apiThread = makeThread(
            document: .plainText("API 主楼"),
            replies: [apiReply],
            replyCount: 8
        )
        let webReply = Reply(
            id: 9001,
            author: "Web 回复作者",
            createdAt: "Web 时间",
            body: "Web 完整回复",
            floorNumber: 1
        )
        let webOnlyReply = Reply(
            id: 9002,
            author: "Web 独有作者",
            createdAt: "Web 时间",
            body: "Web 独有楼层",
            floorNumber: 2
        )
        let webThread = makeThread(
            document: .plainText("Web 主楼"),
            replies: [webReply, webOnlyReply],
            replyCount: 2
        )

        let resolved = try await NGAThreadContentSourcePolicy.resolve(apiThread: apiThread) { webThread }
        let resolvedReply = try #require(resolved.replies.first)

        #expect(resolved.replies.count == 1)
        #expect(resolvedReply.id == 7001)
        #expect(resolvedReply.sourcePostID == 7001)
        #expect(resolvedReply.author == "API 回复作者")
        #expect(resolvedReply.createdAt == "API 时间")
        #expect(resolvedReply.floorNumber == 1)
        #expect(resolvedReply.body == "Web 完整回复")
        #expect(resolvedReply.contentDocument.representations.count == 2)
        #expect(resolved.replyCount == 8)
        #expect(resolved.contentDocument.diagnostics.contains { $0.code == .webOnlyFloorIgnored })
    }

    @Test func cancelledWebFallbackPropagatesCancellation() async {
        let apiThread = makeThread(document: .plainText(""))
        let task = Task { @MainActor in
            try await NGAThreadContentSourcePolicy.resolve(apiThread: apiThread) {
                try await Task.sleep(for: .seconds(5))
                return self.makeThread(document: .plainText("Web 正文"))
            }
        }
        await Task.yield()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    private func makeThread(
        document: ForumPostDocument,
        title: String = "标题",
        author: String = "作者",
        replies: [Reply] = [],
        replyCount: Int = 0
    ) -> ForumThread {
        ForumThread(
            id: 47,
            title: title,
            summary: document.bodyText,
            author: author,
            lastReplyAt: "",
            replyCount: replyCount,
            viewCount: 0,
            body: document.bodyText,
            contentDocument: document,
            replies: replies
        )
    }

    private func fixtureData(named name: String, extension fileExtension: String) throws -> Data {
        let bundle = Bundle(for: SourcePolicyFixtureLocator.self)
        let url = try #require(
            bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: fileExtension)
        )
        return try Data(contentsOf: url)
    }
}

private final class SourcePolicyFixtureLocator {}
