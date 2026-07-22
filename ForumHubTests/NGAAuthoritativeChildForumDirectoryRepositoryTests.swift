import Foundation
import Testing
@testable import ForumHub

struct NGAAuthoritativeChildForumDirectoryRepositoryTests {
    @Test func returnsTheVerifiedDirectChildrenThroughTheSharedRepositorySeam() async throws {
        let data = try fixtureData()
        let repository = NGALiveThreadRepository(
            authoritativeChildForumDataLoader: { _ in data }
        )

        let result = try await repository.fetchAuthoritativeChildForumDirectory(parent: .defaultForum)
        let directory = try #require(result)

        #expect(directory.parent == .defaultForum)
        #expect(directory.children.count == 31)
        #expect(directory.children.first?.stableKey == "fid:570")
        #expect(directory.children.first?.channel == ForumChannel(
            id: 570,
            title: "优惠信息 购物指南",
            nativeKey: "fid:570"
        ))
        #expect(directory.children.first(where: { $0.stableKey == "stid:47206901" })?.channel == ForumChannel(
            id: 47_206_901,
            title: "[股市]技术分析",
            nativeKey: "stid:47206901"
        ))
    }

    @Test func makesTheVerifiedParentMetadataRequest() throws {
        let url = NGALiveThreadRepository.authoritativeChildForumDirectoryURL(parent: .defaultForum)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.host == "bbs.nga.cn")
        #expect(components.path == "/thread.php")
        #expect(components.queryItems == [
            URLQueryItem(name: "fid", value: "-7"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "lite", value: "xml"),
            URLQueryItem(name: "__inchst", value: "UTF8")
        ])
    }

    @Test func keepsFidAndStidCollisionSeparateAndNeverUsesFilterIDForBrowsing() throws {
        let directory = try NGAAuthoritativeChildForumParser.parse(
            data: Data("""
            <root><__F><fid>-7</fid><name>网事杂谈</name><sub_forums>
              <item><item>123</item><item>普通子版</item><item></item><item>900</item><item>4906</item></item>
              <t123><item>123</item><item>主题子版</item><item></item><item>901</item><item>2590</item></t123>
            </sub_forums></__F></root>
            """.utf8),
            expectedParent: .defaultForum
        )

        #expect(directory.children.map(\.stableKey) == ["fid:123", "stid:123"])
        #expect(directory.children.map(\.channel.id) == [123, 123])
        #expect(directory.children.map(\.filterID) == [900, 901])
    }

    @Test func propagatesInvalidAuthoritativeResponsesInsteadOfReturningAChildDirectory() async {
        let repository = NGALiveThreadRepository(
            authoritativeChildForumDataLoader: { _ in
                Data("""
                <root><__F><fid>570</fid><name>优惠信息 购物指南</name><sub_forums></sub_forums></__F></root>
                """.utf8)
            }
        )

        await #expect(throws: NGAAuthoritativeChildForumParserError.parentMismatch) {
            try await repository.fetchAuthoritativeChildForumDirectory(parent: .defaultForum)
        }
    }

    @Test func propagatesAuthoritativeRequestFailuresWithoutFabricatingAChildDirectory() async {
        let repository = NGALiveThreadRepository(
            authoritativeChildForumDataLoader: { _ in throw ChildDirectoryLoaderError.unavailable }
        )

        await #expect(throws: ChildDirectoryLoaderError.self) {
            try await repository.fetchAuthoritativeChildForumDirectory(parent: .defaultForum)
        }
    }

    @Test func sourcesWithoutTheCapabilityReturnNoFabricatedDirectory() async throws {
        let directory = try await MockThreadRepository(source: .v2ex)
            .fetchAuthoritativeChildForumDirectory(parent: .defaultForum)

        #expect(directory == nil)
    }

    private func fixtureData() throws -> Data {
        let bundle = Bundle(for: FixtureBundleToken.self)
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

private final class FixtureBundleToken {}

private enum ChildDirectoryLoaderError: Error {
    case unavailable
}
