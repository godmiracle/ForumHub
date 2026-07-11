import Foundation
import Testing
@testable import ForumHub

@MainActor
struct AuthSessionStateTests {
    @Test func guestNGAIdentityIsTreatedAsExpiredSession() {
        let expired = NGALoginState(
            uid: "guest_123",
            cid: nil,
            cookieNames: ["ngaPassportUid"]
        )

        #expect(!expired.isLoggedIn)
        #expect(expired.authSessionDescriptor.isAuthenticated == false)
        #expect(expired.authSessionDescriptor.action == .login)
    }

    @Test func restoredNGACookieRestoresAuthenticatedSessionDescriptor() {
        let restored = NGALoginState(
            uid: "123456",
            cid: "abcdef123456",
            cookieNames: ["ngaPassportUid", "ngaPassportCid"]
        )

        #expect(restored.isLoggedIn)
        #expect(restored.authSessionDescriptor.isAuthenticated)
        #expect(restored.authSessionDescriptor.statusText == "已连接")
        #expect(restored.cidPreview == "abcdef...3456")
    }
}
