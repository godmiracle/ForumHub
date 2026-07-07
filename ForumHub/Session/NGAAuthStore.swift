import Foundation
import Security
import WebKit

final class NGAAuthStore {
    static let shared = NGAAuthStore()
    private let keychain = NGAKeychainCookieStore()

    func currentLoginState() async -> NGALoginState {
        await restorePersistedCookies()

        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await cookieStore.cookies()
        mirrorCookiesToSharedStorage(cookies)
        persistLoginCookies(cookies)

        return NGALoginState(cookies: cookies)
    }

    func syncAndReadLoginState(from cookieStore: WKHTTPCookieStore) async -> NGALoginState {
        let cookies = await cookieStore.cookies()
        mirrorCookiesToSharedStorage(cookies)
        persistLoginCookies(cookies)

        return NGALoginState(cookies: cookies)
    }

    func syncDefaultCookies() async -> NGALoginState {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await cookieStore.cookies()
        mirrorCookiesToSharedStorage(cookies)
        persistLoginCookies(cookies)

        return NGALoginState(cookies: cookies)
    }

    func logout() async {
        let webCookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await webCookieStore.cookies()

        for cookie in cookies where cookie.domain.contains("nga.cn") || cookie.domain.contains("178.com") {
            await webCookieStore.deleteCookie(cookie)
        }

        let sharedCookies = HTTPCookieStorage.shared.cookies ?? []
        for cookie in sharedCookies where cookie.domain.contains("nga.cn") || cookie.domain.contains("178.com") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }

        keychain.deleteCookies()
    }

    private func mirrorCookiesToSharedStorage(_ cookies: [HTTPCookie]) {
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func restorePersistedCookies() async {
        let cookies = keychain.loadCookies()
        guard !cookies.isEmpty else { return }

        let webCookieStore = WKWebsiteDataStore.default().httpCookieStore
        for cookie in cookies {
            await webCookieStore.setCookie(cookie)
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func persistLoginCookies(_ cookies: [HTTPCookie]) {
        let loginCookies = cookies.filter { cookie in
            ["ngaPassportUid", "ngaPassportCid"].contains(cookie.name)
        }

        guard !loginCookies.isEmpty else { return }
        keychain.saveCookies(loginCookies)
    }
}

struct NGALoginState {
    let uid: String?
    let cid: String?
    let cookieNames: [String]

    init(uid: String?, cid: String?, cookieNames: [String]) {
        self.uid = uid
        self.cid = cid
        self.cookieNames = cookieNames
    }

    init(cookies: [HTTPCookie]) {
        uid = cookies.first(where: { $0.name == "ngaPassportUid" })?.value
        cid = cookies.first(where: { $0.name == "ngaPassportCid" })?.value
        cookieNames = cookies
            .map(\.name)
            .filter { $0.localizedCaseInsensitiveContains("nga") || $0.localizedCaseInsensitiveContains("guest") || $0.localizedCaseInsensitiveContains("last") }
            .sorted()
    }

    var isLoggedIn: Bool {
        if let cid, !cid.isEmpty {
            return true
        }

        guard let uid, !uid.isEmpty else {
            return false
        }

        return !uid.localizedCaseInsensitiveContains("guest")
    }

    var cidPreview: String {
        guard let cid, !cid.isEmpty else {
            return "未识别"
        }

        if cid.count <= 10 {
            return cid
        }

        return "\(cid.prefix(6))...\(cid.suffix(4))"
    }

    var identitySummary: String {
        guard let uid, !uid.isEmpty else {
            return "NGA 用户"
        }
        return "UID \(uid)"
    }

    static let empty = NGALoginState(uid: nil, cid: nil, cookieNames: [])
}

struct NGAKeychainCookieStore {
    private let service = "com.godmiracle.forumhub.cookies"
    private let legacyService = "com.godmiracle.nga.cookies"
    private let account = "nga-login-cookies"

    func saveCookies(_ cookies: [HTTPCookie]) {
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

        guard let data = try? JSONSerialization.data(withJSONObject: encodedCookies) else {
            return
        }

        deleteCookies()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    func loadCookies() -> [HTTPCookie] {
        let data = loadData(forService: service) ?? loadData(forService: legacyService)
        guard let data,
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

    func deleteCookies() {
        deleteData(forService: service)
        deleteData(forService: legacyService)
    }

    private func loadData(forService service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private func deleteData(forService service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}

private extension WKHTTPCookieStore {
    func setCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    func cookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            delete(cookie) {
                continuation.resume()
            }
        }
    }
}
