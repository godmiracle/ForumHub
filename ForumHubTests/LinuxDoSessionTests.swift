import Foundation
import Testing
@testable import ForumHub

@MainActor
struct LinuxDoSessionTests {
    @Test func verificationErrorMapsToAccessDenied() {
        #expect(ForumError.resolve(LinuxDoRequestError.verificationRequired) == .accessDenied)
        #expect(LinuxDoRequestError.verificationRequired.errorDescription?.contains("浏览器验证") == true)
    }

    @Test func parserReadsAuthenticatedLinuxDoSession() throws {
        let data = Data(#"{"current_user":{"id":42,"username":"codex","name":" Codex User ","avatar_template":"/user_avatar/{size}/1.png","trust_level":3}}"#.utf8)

        let account = try LinuxDoSessionResponseParser.account(from: data)

        #expect(account == LinuxDoAccount(
            id: 42,
            username: "codex",
            name: " Codex User ",
            avatarTemplate: "/user_avatar/{size}/1.png",
            trustLevel: 3
        ))
        #expect(account.displayName == "Codex User")
        #expect(account.subtitle == "@codex · TL3")
    }

    @Test func parserTreatsMissingCurrentUserAsExpiredSession() {
        let data = Data(#"{"current_user":null}"#.utf8)

        #expect(throws: LinuxDoAuthError.self) {
            try LinuxDoSessionResponseParser.account(from: data)
        }
    }

    @Test func parserRejectsMalformedSessionPayload() {
        #expect(throws: (any Error).self) {
            try LinuxDoSessionResponseParser.account(from: Data("not-json".utf8))
        }
    }
}
