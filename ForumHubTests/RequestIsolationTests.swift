import Foundation
import Testing
@testable import ForumHub

struct RequestIsolationTests {
    @Test func v2exPublicRequestNeverCarriesAuthorization() throws {
        let request = V2EXRequestBuilder.publicRequest(
            url: try #require(URL(string: "https://www.v2ex.com/recent")),
            accept: "text/html"
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Referer") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.httpShouldHandleCookies)
    }

    @Test func v2exTokenIsRestrictedToOfficialV2API() throws {
        let request = try V2EXRequestBuilder.authenticatedAPIRequest(
            url: try #require(URL(string: "https://www.v2ex.com/api/v2/member")),
            token: "secret-test-token"
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-test-token")
        #expect(!request.httpShouldHandleCookies)
        #expect(throws: (any Error).self) {
            try V2EXRequestBuilder.authenticatedAPIRequest(
                url: try #require(URL(string: "https://example.com/api/v2/member")),
                token: "secret-test-token"
            )
        }
        #expect(throws: (any Error).self) {
            try V2EXRequestBuilder.authenticatedAPIRequest(
                url: try #require(URL(string: "http://www.v2ex.com/api/v2/member")),
                token: "secret-test-token"
            )
        }
    }

    @Test func v2exPublicAPIRequestDoesNotAttachWebSessionCookies() throws {
        let request = V2EXRequestBuilder.publicRequest(
            url: try #require(URL(string: "https://www.v2ex.com/api/topics/hot.json")),
            accept: "application/json",
            handlesCookies: false
        )

        #expect(!request.httpShouldHandleCookies)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func linuxDoUsesBrowserFallbackOnlyForForbiddenResponses() {
        #expect(LinuxDoRequestPolicy.shouldUseBrowserFallback(statusCode: 403))
        #expect(!LinuxDoRequestPolicy.shouldUseBrowserFallback(statusCode: 401))
        #expect(!LinuxDoRequestPolicy.shouldUseBrowserFallback(statusCode: 404))
        #expect(!LinuxDoRequestPolicy.shouldUseBrowserFallback(statusCode: 500))
    }
}
