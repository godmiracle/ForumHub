import Foundation
import Testing
@testable import ForumHub

struct NGAAuthoritativeChildForumParserTests {
    @Test func parsesSanitizedWangshiFixtureAsCompleteDirectChildDirectory() throws {
        let directory = try NGAAuthoritativeChildForumParser.parse(
            data: fixtureData(),
            expectedParent: .defaultForum
        )

        #expect(directory.parentFID == -7)
        #expect(directory.parentName == "网事杂谈")
        #expect(directory.children.count == 31)
        #expect(directory.children.first?.stableKey == "fid:570")
        #expect(directory.children.first?.channel.nativeKey == "fid:570")
        #expect(directory.children.first?.filterID == 12_700_430)
        #expect(directory.children.first?.attributes == 4_906)
        #expect(directory.children.first(where: { $0.stableKey == "stid:47206901" })?.channel.id == 47_206_901)
    }

    @Test func acceptsAnExplicitlyEmptyChildForumDirectory() throws {
        let directory = try parse("""
        <root><__F><fid>-7</fid><name>网事杂谈</name><sub_forums></sub_forums></__F></root>
        """)

        #expect(directory.children.isEmpty)
    }

    @Test func rejectsMissingOrMismatchedParentIdentity() {
        #expect(throws: NGAAuthoritativeChildForumParserError.missingParentIdentity) {
            try parse("""
            <root><__F><name>网事杂谈</name><sub_forums></sub_forums></__F></root>
            """)
        }
        #expect(throws: NGAAuthoritativeChildForumParserError.parentMismatch) {
            try parse("""
            <root><__F><fid>570</fid><name>优惠信息 购物指南</name><sub_forums></sub_forums></__F></root>
            """)
        }
    }

    @Test func rejectsTruncatedOrExtendedPositionalRecords() {
        #expect(throws: NGAAuthoritativeChildForumParserError.invalidChildForumRecord) {
            try parse("""
            <root><__F><fid>-7</fid><name>网事杂谈</name><sub_forums>
              <item><item>570</item><item>优惠信息 购物指南</item><item></item><item>12700430</item></item>
            </sub_forums></__F></root>
            """)
        }
        #expect(throws: NGAAuthoritativeChildForumParserError.invalidChildForumRecord) {
            try parse("""
            <root><__F><fid>-7</fid><name>网事杂谈</name><sub_forums>
              <item><item>570</item><item>优惠信息 购物指南</item><item></item><item>12700430</item><item>4906</item><item>unexpected</item></item>
            </sub_forums></__F></root>
            """)
        }
    }

    @Test func rejectsUnknownDirectNodesAndMismatchedStidTags() {
        #expect(throws: NGAAuthoritativeChildForumParserError.unknownChildForumNode("forum")) {
            try parse("""
            <root><__F><fid>-7</fid><name>网事杂谈</name><sub_forums><forum></forum></sub_forums></__F></root>
            """)
        }
        #expect(throws: NGAAuthoritativeChildForumParserError.invalidChildForumRecord) {
            try parse("""
            <root><__F><fid>-7</fid><name>网事杂谈</name><sub_forums>
              <t47206901><item>44618580</item><item>期货交易</item><item></item><item>44618580</item><item>2590</item></t47206901>
            </sub_forums></__F></root>
            """)
        }
    }

    @Test func ignoresUnrelatedResponseAndForumMetadataFields() throws {
        let directory = try parse("""
        <root>
          <__F>
            <fid>-7</fid><name>网事杂谈</name><page>1</page>
            <sub_forums><item><item>570</item><item>优惠信息 购物指南</item><item></item><item>12700430</item><item>4906</item></item></sub_forums>
          </__F>
          <__T><item>未参与目录解析</item></__T>
        </root>
        """)

        #expect(directory.children.map(\.stableKey) == ["fid:570"])
    }

    private func parse(_ xml: String) throws -> NGAAuthoritativeChildForumDirectory {
        try NGAAuthoritativeChildForumParser.parse(
            data: Data(xml.utf8),
            expectedParent: .defaultForum
        )
    }

    private func fixtureData() throws -> Data {
        let bundle = Bundle(for: FixtureMarker.self)
        let url = try #require(
            bundle.url(
                forResource: "nga-wangshi-authoritative-child-forums",
                withExtension: "xml",
                subdirectory: "Fixtures"
            ) ?? bundle.url(
                forResource: "nga-wangshi-authoritative-child-forums",
                withExtension: "xml"
            )
        )
        return try Data(contentsOf: url)
    }
}

private final class FixtureMarker {}
