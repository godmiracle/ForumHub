import Foundation
import Testing
@testable import ForumHub

struct NGAImageRequestTests {
    @Test func ngaEmojiLocalResourceUsesStableFilenameAcrossHosts() throws {
        let currentURL = URL(string: "https://img4.nga.cn/ngabbs/post/smile/ac0.png")!
        let legacyURL = URL(string: "https://img4.nga.178.com/ngabbs/post/smile/ac0.png")!

        #expect(NGAForumEmojiLocalStore.filename(for: currentURL) == "ac0.png")
        #expect(NGAForumEmojiLocalStore.filename(for: legacyURL) == "ac0.png")
        #expect(
            NGAForumEmojiLocalStore.cacheFileURL(for: currentURL)
                == NGAForumEmojiLocalStore.cacheFileURL(for: legacyURL)
        )
        #expect(NGAForumEmojiLocalStore.filename(for: URL(string: "https://example.com/ac0.png")!) == nil)
        #expect(NGAForumEmojiLocalStore.filename(for: URL(string: "https://img4.nga.cn/attachments/ac0.png")!) == nil)
        #expect(NGAForumEmojiLocalStore.filename(for: URL(string: "https://img4.nga.cn/ngabbs/post/smile/ordinary.png")!) == nil)
    }

    @Test func packagedNGAEmojiAssetIsAvailable() throws {
        let url = URL(string: "https://img4.nga.cn/ngabbs/post/smile/ac0.png")!
        let data = try #require(NGAForumEmojiLocalStore.data(for: url))

        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test @MainActor func pickerDoesNotOfferConfirmedMissingSmileFiles() {
        let unavailableFilenames = NGAReplyEmojiCatalog.confirmedUnavailableFilenames
        let selectableFilenames = Set(
            NGAForumEmojiGroup.allCases
                .flatMap(\.items)
                .map(\.filename)
        )

        #expect(selectableFilenames.isDisjoint(with: unavailableFilenames))
        #expect(NGAReplyEmojiCatalog.item(filename: "ng_39.png") != nil)
        #expect(NGAReplyEmojiCatalog.item(filename: "a2_35.png") != nil)
    }

    @Test @MainActor func imageLoaderUsesPackagedEmojiBeforeRemoteFallback() async throws {
        let url = URL(string: "https://img4.nga.cn:1/ngabbs/post/smile/ac0.png")!
        let asset = try await NGAImageLoader.loadAsset(url: url)

        #expect(asset.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func ngaEmojiCacheCanBeCleared() throws {
        let url = URL(string: "https://img4.nga.cn/ngabbs/post/smile/ng_39.png")!
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForumEmojiTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        NGAForumEmojiLocalStore.store(Data([1, 2, 3]), for: url, cacheDirectory: cacheDirectory)
        #expect(
            NGAForumEmojiLocalStore.data(
                for: url,
                cacheDirectory: cacheDirectory
            ) == Data([1, 2, 3])
        )

        NGAForumEmojiLocalStore.clear(cacheDirectory: cacheDirectory)
        #expect(
            NGAForumEmojiLocalStore.data(
                for: url,
                cacheDirectory: cacheDirectory
            ) == nil
        )
    }

    @Test func currentNGAForumEmojiUsesCurrentSmileHost() throws {
        let emoji = try #require(
            NGAForumEmojiResolver.resolve(markup: "[s:ac:blink]")
        )

        #expect(
            emoji.url.absoluteString
                == "https://img4.nga.cn/ngabbs/post/smile/ac0.png"
        )
        #expect(NGAImageURLResolver.isForumEmoji(emoji.url))
        #expect(
            NGAImageURLResolver.resolve(
                "https://img4.nga.178.com/ngabbs/post/smile/ng_1.png"
            )?.absoluteString
                == "https://img4.nga.cn/ngabbs/post/smile/ng_1.png"
        )
        #expect(
            NGAImageURLResolver.resolve(
                "https://img4.nga.178.com/attachments/example.jpg"
            )?.absoluteString
                == "https://img4.nga.178.com/attachments/example.jpg"
        )

        let legacyEmoji = try #require(
            ReplyComposerEmoji(
                markup: "[img]https://img4.nga.178.com/ngabbs/post/smile/ng_1.png[/img]"
            )
        )
        #expect(legacyEmoji.markup == "[img]https://img4.nga.cn/ngabbs/post/smile/ng_1.png[/img]")

        let request = NGAImageLoader.makeRequest(url: emoji.url)
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://bbs.nga.cn/")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("NGAPrototype") == true)
    }

    @Test func currentNGAImageURLUpgradesHTTPHost() {
        #expect(
            NGAImageURLResolver.resolve("http://img.nga.cn/a.jpg")?.absoluteString
                == "https://img.nga.cn/a.jpg"
        )
    }

    @Test func trustedNGAImageRequestCarriesRefererAndUserAgent() {
        let url = URL(string: "https://img.nga.178.com/attachments/example.jpg")!
        let request = NGAImageLoader.makeRequest(url: url)

        #expect(request.value(forHTTPHeaderField: "Referer") == "https://bbs.nga.cn/")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("NGAPrototype") == true)
        #expect(request.httpShouldHandleCookies)
    }

    @Test func directNGAAvatarRequestCarriesRefererAndUserAgent() {
        let url = URL(string: "https://img.nga.178.com/avatars/60459868.jpg")!
        let request = NGAImageLoader.makeRequest(url: url)

        #expect(request.value(forHTTPHeaderField: "Referer") == "https://bbs.nga.cn/")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("NGAPrototype") == true)
        #expect(request.httpShouldHandleCookies)
    }

    @Test func currentNGAImageHostCarriesRefererAndUserAgent() {
        let url = URL(string: "https://img.nga.cn/attachments/example.gif")!
        let request = NGAImageLoader.makeRequest(url: url)

        #expect(request.value(forHTTPHeaderField: "Referer") == "https://bbs.nga.cn/")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("NGAPrototype") == true)
        #expect(request.httpShouldHandleCookies)
    }

    @Test func nonNGAImageRequestDoesNotLeakNGAHeaders() {
        let url = URL(string: "https://example.com/image.jpg")!
        let request = NGAImageLoader.makeRequest(url: url)

        #expect(request.value(forHTTPHeaderField: "Referer") == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }
}
