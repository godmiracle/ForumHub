import Foundation
import Observation
import Security
import WebKit

struct V2EXAccount: Equatable {
    let id: Int
    let username: String
}

protocol V2EXAuthenticating {
    func validate(token: String) async throws -> V2EXAccount
}

struct V2EXAuthService: V2EXAuthenticating {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(token: String) async throws -> V2EXAccount {
        let request = try V2EXRequestBuilder.authenticatedAPIRequest(
            url: URL(string: "https://www.v2ex.com/api/v2/member")!,
            token: token
        )

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw V2EXAuthError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw response.statusCode == 401 || response.statusCode == 403
                ? V2EXAuthError.invalidToken
                : V2EXAuthError.httpStatus(response.statusCode)
        }

        return try V2EXAuthResponseParser.account(from: data)
    }
}

@MainActor
@Observable
final class V2EXAuthStore {
    private(set) var account: V2EXAccount?
    private(set) var hasWebSession = false
    private(set) var webSessionSyncErrorMessage: String?
    private(set) var isValidating = false
    private(set) var errorMessage: String?

    private let service: any V2EXAuthenticating
    private let keychain: V2EXTokenKeychainStore

    var isAuthenticated: Bool { account != nil }
    var username: String? { account?.username }

    init() {
        service = V2EXAuthService()
        keychain = V2EXTokenKeychainStore()
    }

    init(service: any V2EXAuthenticating, keychain: V2EXTokenKeychainStore) {
        self.service = service
        self.keychain = keychain
    }

    func restoreSession() async {
        async let webSession = V2EXWebSession.restore()
        do {
            if let token = try keychain.loadToken() {
                await validateAndSave(token: token, savesToken: false)
                if account == nil {
                    try? keychain.deleteToken()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        let webResult = await webSession
        hasWebSession = webResult.isValid
        webSessionSyncErrorMessage = webResult.keychainErrorMessage
    }

    @discardableResult
    func login(token: String) async -> Bool {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            errorMessage = "请输入 V2EX Personal Access Token。"
            return false
        }

        await validateAndSave(token: normalizedToken, savesToken: true)
        return account != nil
    }

    func logout() {
        do {
            try keychain.deleteToken()
            account = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func syncWebSession(from cookieStore: WKHTTPCookieStore) async -> Bool {
        let result = await V2EXWebSession.syncCookies(from: cookieStore)
        hasWebSession = result.isValid
        webSessionSyncErrorMessage = result.keychainErrorMessage
        return hasWebSession
    }

    func refreshWebSession() async {
        let result = await V2EXWebSession.restore()
        hasWebSession = result.isValid
        webSessionSyncErrorMessage = result.keychainErrorMessage
    }

    func logoutWebSession() async {
        webSessionSyncErrorMessage = await V2EXWebSession.clearCookies()
        hasWebSession = false
    }

    func clearError() {
        errorMessage = nil
    }

    private func validateAndSave(token: String, savesToken: Bool) async {
        isValidating = true
        errorMessage = nil
        defer { isValidating = false }

        do {
            account = try await service.validate(token: token)
            if savesToken {
                try keychain.saveToken(token)
            }
        } catch {
            account = nil
            errorMessage = error.localizedDescription
        }
    }
}

enum V2EXAuthResponseParser {
    static func account(from data: Data) throws -> V2EXAccount {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(V2EXMemberEnvelope.self, from: data),
           let member = envelope.result {
            return V2EXAccount(id: member.id, username: member.username)
        }
        if let member = try? decoder.decode(V2EXMemberResponse.self, from: data) {
            return V2EXAccount(id: member.id, username: member.username)
        }
        throw V2EXAuthError.invalidResponse
    }
}

private struct V2EXMemberEnvelope: Decodable {
    let result: V2EXMemberResponse?
}

private struct V2EXMemberResponse: Decodable {
    let id: Int
    let username: String
}

enum V2EXAuthError: LocalizedError {
    case invalidToken
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Token 无效或已过期，请重新生成。"
        case .invalidResponse:
            return "V2EX 返回了无法识别的账号信息。"
        case let .httpStatus(code):
            return "V2EX 验证失败（\(code)），请稍后重试。"
        }
    }
}

struct V2EXTokenKeychainStore {
    private let service = "com.godmiracle.forumhub.v2ex-token"
    private let legacyService = "com.godmiracle.nga.v2ex-token"
    private let account = "v2ex-personal-access-token"

    func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw V2EXAuthError.invalidToken
        }
        try itemStore(for: service).save(data)
    }

    func loadToken() throws -> String? {
        guard let data = try itemStore(for: service).load() ?? itemStore(for: legacyService).load() else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken() throws {
        try itemStore(for: service).delete()
        try itemStore(for: legacyService).delete()
    }

    private func itemStore(for service: String) -> SynchronizableKeychainStore {
        SynchronizableKeychainStore(service: service, account: account)
    }
}
