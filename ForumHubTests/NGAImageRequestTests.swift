import Foundation
import Testing
@testable import ForumHub

struct NGAImageRequestTests {
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

    @Test func nonNGAImageRequestDoesNotLeakNGAHeaders() {
        let url = URL(string: "https://example.com/image.jpg")!
        let request = NGAImageLoader.makeRequest(url: url)

        #expect(request.value(forHTTPHeaderField: "Referer") == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }
}
