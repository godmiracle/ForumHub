import Foundation
import Testing
@testable import ForumHub

@MainActor
struct ForumSemanticContentTests {
    @Test func ngaParserPreservesRepeatedParagraphAndImageOccurrencesInOrder() throws {
        let markup = """
        Same paragraph
        [img]https://img.nga.178.com/attachments/repeated.png[/img]
        Middle
        Same paragraph
        [img]https://img.nga.178.com/attachments/repeated.png[/img]
        """

        let document = NGABBCodeContentParser.parse(markup)

        #expect(document.blocks.map(\.kind) == [.paragraph, .image, .paragraph, .image])
        #expect(document.imageURLs.map(\.absoluteString) == [
            "https://img.nga.178.com/attachments/repeated.png",
            "https://img.nga.178.com/attachments/repeated.png"
        ])
        #expect(Set(document.blocks.map(\.id)).count == document.blocks.count)
        #expect(document.bodyText.components(separatedBy: "Same paragraph").count - 1 == 2)
        #expect(document.bodyText.contains("Middle\nSame paragraph"))
    }

    @Test func unknownMarkupRemainsVisibleAndProducesDegradedDiagnostic() {
        let document = NGABBCodeContentParser.parse("Before [future=Value]Case Sensitive[/future] After")

        #expect(document.quality == .degraded)
        #expect(document.bodyText.contains("Before"))
        #expect(document.bodyText.contains("[future=Value]Case Sensitive[/future]"))
        #expect(document.bodyText.contains("After"))
        #expect(document.diagnostics.contains { $0.code == .unsupportedMarkup })
    }

    @Test func parserLowersObservedURLBreakAndEmojiMarkupInsteadOfDisplayingTags() throws {
        let document = NGABBCodeContentParser.parse(
            "[url=https://example.com/story?id=1]曾经的快乐水[/url] [br][s:ac:哭笑]感觉卖不动"
        )

        #expect(document.quality == .valid)
        #expect(document.blocks.map(\.kind) == [.paragraph, .emoji, .paragraph])
        guard case let .link(label, destination) = try #require(document.blocks.first).content else {
            Issue.record("首个语义节点应为链接")
            return
        }
        #expect(label == "曾经的快乐水")
        #expect(destination.absoluteString == "https://example.com/story?id=1")
        #expect(document.bodyText.contains("[表情] 哭笑"))
        #expect(!document.bodyText.contains("[url="))
        #expect(!document.bodyText.contains("[br]"))
        #expect(!document.bodyText.contains("[s:ac:"))
    }

    @Test func parserLowersObservedTopicQuoteWithoutDisplayingSourceMarkup() throws {
        let bundle = Bundle(for: SemanticFixtureLocator.self)
        let url = try #require(
            bundle.url(forResource: "nga-bbcode-topic-quote", withExtension: "txt", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "nga-bbcode-topic-quote", withExtension: "txt")
        )
        let markup = try String(contentsOf: url, encoding: .utf8)

        let document = NGABBCodeContentParser.parse(markup)

        #expect(document.quality == .valid)
        #expect(document.blocks.map(\.kind) == [.quote, .paragraph])
        guard case let .quote(quote) = try #require(document.blocks.first).content else {
            Issue.record("首个语义节点应为引用")
            return
        }
        #expect(quote.author == "脱敏引用作者")
        #expect(quote.createdAt == "2026-07-16 19:46")
        #expect(quote.body == "引用第一行\n引用第二行")
        #expect(document.blocks.last?.content == .text("引用后的回复正文"))
        #expect(!document.bodyText.contains("[quote]"))
        #expect(!document.bodyText.contains("[tid="))
        #expect(!document.bodyText.contains("[uid="))
        #expect(!document.bodyText.contains("[br]"))
        #expect(!document.bodyText.contains("<b>"))
    }

    @Test func parserSeparatesObservedReplyToHeaderFromReplyBodyAndEmoji() throws {
        let bundle = Bundle(for: SemanticFixtureLocator.self)
        let url = try #require(
            bundle.url(forResource: "nga-bbcode-reply-to-header", withExtension: "txt", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "nga-bbcode-reply-to-header", withExtension: "txt")
        )
        let markup = try String(contentsOf: url, encoding: .utf8)

        let document = NGABBCodeContentParser.parse(markup)

        #expect(document.quality == .valid)
        #expect(document.blocks.map(\.kind) == [.quote, .paragraph, .emoji])
        guard case let .quote(quote) = try #require(document.blocks.first).content else {
            Issue.record("首个语义节点应为回复目标引用")
            return
        }
        #expect(quote.author == "脱敏被回复用户")
        #expect(quote.createdAt == "2026-07-16 17:32")
        #expect(quote.body.isEmpty)
        #expect(document.blocks[1].content == .text("引用头后的回复正文"))
        #expect(document.blocks[2].kind == .emoji)
        for sourceTag in ["<b>", "</b>", "Reply to", "[pid=", "[uid=", "[br]"] {
            #expect(!document.bodyText.contains(sourceTag))
        }
    }

    @Test func parserPreservesObservedInlineHTMLAsSemanticStrikethrough() throws {
        let bundle = Bundle(for: SemanticFixtureLocator.self)
        let url = try #require(
            bundle.url(forResource: "nga-bbcode-inline-html-formatting", withExtension: "txt", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "nga-bbcode-inline-html-formatting", withExtension: "txt")
        )
        let markup = try String(contentsOf: url, encoding: .utf8)

        let documents = [
            NGABBCodeContentParser.parse(markup),
            NGAHTMLContentParser.parse(markup)
        ]

        for document in documents {
            #expect(document.quality == .valid)
            #expect(document.blocks.map(\.kind) == [.paragraph])
            #expect(document.blocks.first?.content == .inline([
                .strikethrough([.text("脱敏删除线文字")]),
                .text("后续正文")
            ]))
            #expect(document.bodyText == "脱敏删除线文字后续正文")
            #expect(!document.bodyText.contains("<del"))
            #expect(!document.bodyText.contains("</del>"))
        }
    }

    @Test func nga47185513ShapeMapsRootMetadataAndOrderedSemanticContent() throws {
        let bundle = Bundle(for: SemanticFixtureLocator.self)
        let url = try #require(
            bundle.url(forResource: "nga-thread-47185513-shape", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "nga-thread-47185513-shape", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        let thread = try #require(ThreadDetailParser.parse(
            data: data,
            fallbackText: String(decoding: data, as: UTF8.self),
            tid: 47185513
        ))
        let documents = [thread.contentDocument] + thread.replies.map(\.contentDocument)

        #expect(thread.title == "脱敏语义解析样本")
        #expect(thread.author == "脱敏楼主")
        #expect(thread.replyCount == 11)
        #expect(thread.replies.map(\.floorNumber) == Array(1...11))
        #expect(thread.sourceMetadata?.currentPage == 1)
        #expect(thread.sourceMetadata?.totalPage == 1)
        #expect(thread.sourceMetadata?.attachmentPrefix == "https://img.nga.178.com/attachments/")
        #expect(documents.flatMap(\.imageURLs).map(\.absoluteString) == [
            "https://img.nga.178.com/attachments/sample/first.jpg",
            "https://img.nga.178.com/attachments/sample/second.jpg"
        ])
        #expect(documents.flatMap(\.blocks).filter { $0.kind == .emoji }.count == 3)
        #expect(documents.flatMap(\.blocks).contains { $0.kind == .quote })
    }

    @Test func parserDiagnosticsNeverContainRawContentOrCredentials() {
        let sensitiveValues = ["正文秘密", "Cookie=secret", "Token=secret", "uid=12345"]
        let document = NGABBCodeContentParser.parse(
            "正文秘密 [future Cookie=secret Token=secret uid=12345]内容[/future]"
        )
        let diagnosticText = document.diagnostics
            .map { "\($0.code.rawValue)|\($0.safeMessage)" }
            .joined(separator: "\n")

        #expect(document.quality == .degraded)
        #expect(sensitiveValues.allSatisfy { !diagnosticText.contains($0) })
    }
}

private final class SemanticFixtureLocator {}
