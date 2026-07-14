import Foundation
import Observation
import Security
import WebKit

struct LinuxDoAccount: Codable, Equatable {
    let id: Int
    let username: String
    let name: String?
    let avatarTemplate: String?
    let trustLevel: Int?

    var displayName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? username : trimmedName
    }

    var subtitle: String {
        if let trustLevel {
            return "@\(username) · TL\(trustLevel)"
        }
        return "@\(username)"
    }
}

enum LinuxDoAuthError: LocalizedError {
    case invalidResponse
    case notLoggedIn
    case blockedByVerification
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "LINUX DO 返回了无法识别的账号信息。"
        case .notLoggedIn:
            return "还没有检测到 LINUX DO 登录状态。"
        case .blockedByVerification:
            return "LINUX DO 仍在要求浏览器验证，请先在网页里完成验证后再试。"
        case let .httpStatus(code):
            return "LINUX DO 账号读取失败（\(code)）。"
        }
    }
}

@MainActor
@Observable
final class LinuxDoAuthStore {
    private(set) var account: LinuxDoAccount?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var keychainErrorMessage: String?

    private let session: URLSession
    private let keychain = LinuxDoKeychainCookieStore()
    private let accountStore = LinuxDoAccountStore()
    private let baseURL = URL(string: "https://linux.do/")!

    var isAuthenticated: Bool { account != nil }
    var username: String? { account?.username }

    init(session: URLSession = .shared) {
        self.session = session
        account = accountStore.loadAccount()
    }

    func restoreSession() async {
        await restorePersistedCookies()
        account = accountStore.loadAccount()
        let cookies = await syncDefaultCookies()
        guard !cookies.isEmpty else {
            accountStore.deleteAccount()
            account = nil
            errorMessage = nil
            return
        }

        do {
            let account = try await fetchCurrentAccount()
            self.account = account
            accountStore.saveAccount(account)
            errorMessage = nil
        } catch {
            if account == nil {
                errorMessage = nil
            }
        }
    }

    @discardableResult
    func syncDefaultCookies() async -> [HTTPCookie] {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await allCookies(from: cookieStore)
        let loginCookies = linuxDoCookies(from: cookies)
        mirrorCookiesToSharedStorage(loginCookies)
        persistLoginCookies(loginCookies)
        return loginCookies
    }

    @discardableResult
    func syncCookies(from cookieStore: WKHTTPCookieStore) async -> [HTTPCookie] {
        let cookies = await allCookies(from: cookieStore)
        let loginCookies = linuxDoCookies(from: cookies)
        mirrorCookiesToSharedStorage(loginCookies)
        persistLoginCookies(loginCookies)
        return loginCookies
    }

    func finishWebLogin(with account: LinuxDoAccount, cookieStore: WKHTTPCookieStore) async {
        _ = await syncCookies(from: cookieStore)
        self.account = account
        accountStore.saveAccount(account)
        errorMessage = nil
    }

    func refreshAccount() async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            await syncDefaultCookies()
            let account = try await fetchCurrentAccount()
            self.account = account
            accountStore.saveAccount(account)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        let webCookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await allCookies(from: webCookieStore)

        for cookie in cookies where cookie.domain.contains("linux.do") {
            await delete(cookie: cookie, from: webCookieStore)
        }

        let sharedCookies = HTTPCookieStorage.shared.cookies ?? []
        for cookie in sharedCookies where cookie.domain.contains("linux.do") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }

        do {
            try keychain.deleteCookies()
            keychainErrorMessage = nil
        } catch {
            keychainErrorMessage = error.localizedDescription
        }
        accountStore.deleteAccount()
        account = nil
        errorMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    private func fetchCurrentAccount() async throws -> LinuxDoAccount {
        var request = URLRequest(url: baseURL.appendingPathComponent("session/current.json"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ForumHub/1.0 iOS", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = true

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinuxDoAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 403 {
                throw LinuxDoAuthError.blockedByVerification
            }
            throw LinuxDoAuthError.httpStatus(httpResponse.statusCode)
        }
        return try LinuxDoSessionResponseParser.account(from: data)
    }

    private func mirrorCookiesToSharedStorage(_ cookies: [HTTPCookie]) {
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func restorePersistedCookies() async {
        let cookies: [HTTPCookie]
        do {
            cookies = try keychain.loadCookies()
            keychainErrorMessage = nil
        } catch {
            keychainErrorMessage = error.localizedDescription
            return
        }
        guard !cookies.isEmpty else { return }

        let webCookieStore = WKWebsiteDataStore.default().httpCookieStore
        for cookie in cookies {
            await set(cookie: cookie, in: webCookieStore)
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func persistLoginCookies(_ cookies: [HTTPCookie]) {
        guard !cookies.isEmpty else { return }
        do {
            try keychain.saveCookies(cookies)
            keychainErrorMessage = nil
        } catch {
            keychainErrorMessage = error.localizedDescription
        }
    }

    private func linuxDoCookies(from cookies: [HTTPCookie]) -> [HTTPCookie] {
        cookies.filter { $0.domain.contains("linux.do") }
    }

    private func set(cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private func delete(cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) {
                continuation.resume()
            }
        }
    }

    private func allCookies(from store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}

enum LinuxDoSessionResponseParser {
    static func account(from data: Data) throws -> LinuxDoAccount {
        let decoder = JSONDecoder()
        let session = try decoder.decode(LinuxDoSessionResponse.self, from: data)
        guard let user = session.currentUser else {
            throw LinuxDoAuthError.notLoggedIn
        }

        return LinuxDoAccount(
            id: user.id,
            username: user.username,
            name: user.name,
            avatarTemplate: user.avatarTemplate,
            trustLevel: user.trustLevel
        )
    }
}

private struct LinuxDoSessionResponse: Decodable {
    let currentUser: LinuxDoCurrentUserDTO?

    enum CodingKeys: String, CodingKey {
        case currentUser = "current_user"
    }
}

private struct LinuxDoCurrentUserDTO: Decodable {
    let id: Int
    let username: String
    let name: String?
    let avatarTemplate: String?
    let trustLevel: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, name
        case avatarTemplate = "avatar_template"
        case trustLevel = "trust_level"
    }
}

private struct LinuxDoAccountStore {
    private let defaults = UserDefaults.standard
    private let key = "linuxdo-account-v1"

    func saveAccount(_ account: LinuxDoAccount?) {
        guard let account,
              let data = try? JSONEncoder().encode(account)
        else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    func loadAccount() -> LinuxDoAccount? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LinuxDoAccount.self, from: data)
    }

    func deleteAccount() {
        defaults.removeObject(forKey: key)
    }
}

private struct LinuxDoKeychainCookieStore {
    private let service = "com.godmiracle.forumhub.linuxdo.cookies"
    private let account = "linuxdo-login-cookies"

    func saveCookies(_ cookies: [HTTPCookie]) throws {
        let encodedCookies = cookies.compactMap { cookie -> [String: Any]? in
            var properties: [String: Any] = [
                HTTPCookiePropertyKey.name.rawValue: cookie.name,
                HTTPCookiePropertyKey.value.rawValue: cookie.value,
                HTTPCookiePropertyKey.domain.rawValue: cookie.domain,
                HTTPCookiePropertyKey.path.rawValue: cookie.path,
                HTTPCookiePropertyKey.secure.rawValue: cookie.isSecure
            ]

            if let expiresDate = cookie.expiresDate {
                properties[HTTPCookiePropertyKey.expires.rawValue] = expiresDate.timeIntervalSince1970
            }

            return properties
        }

        let data = try JSONSerialization.data(withJSONObject: encodedCookies)
        try itemStore.save(data)
    }

    func loadCookies() throws -> [HTTPCookie] {
        guard let data = try itemStore.load(),
              let encodedCookies = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return encodedCookies.compactMap { encodedCookie in
            var properties: [HTTPCookiePropertyKey: Any] = [:]

            for (key, value) in encodedCookie {
                if key == HTTPCookiePropertyKey.expires.rawValue, let timestamp = value as? TimeInterval {
                    properties[.expires] = Date(timeIntervalSince1970: timestamp)
                } else {
                    properties[HTTPCookiePropertyKey(rawValue: key)] = value
                }
            }

            return HTTPCookie(properties: properties)
        }
    }

    func deleteCookies() throws {
        try itemStore.delete()
    }

    private var itemStore: SynchronizableKeychainStore {
        SynchronizableKeychainStore(service: service, account: account)
    }
}
