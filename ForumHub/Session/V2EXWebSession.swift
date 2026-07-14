import Foundation
import Security
import WebKit

@MainActor
enum V2EXWebSession {
    private static let baseURL = URL(string: "https://www.v2ex.com/")!
    private static let keychain = V2EXWebCookieKeychainStore()

    struct Result {
        let isValid: Bool
        let keychainErrorMessage: String?
    }

    static func restore() async -> Result {
        let webCookieStore = WKWebsiteDataStore.default().httpCookieStore
        let webCookies = await webCookieStore.cookies().filter(\.isValidV2EXCookie)
        if await activate(webCookies) {
            do {
                try keychain.saveCookies(webCookies)
                return Result(isValid: true, keychainErrorMessage: nil)
            } catch {
                return Result(isValid: true, keychainErrorMessage: error.localizedDescription)
            }
        }

        let persistedCookies: [HTTPCookie]
        do {
            persistedCookies = try keychain.loadCookies().filter(\.isValidV2EXCookie)
        } catch {
            return Result(isValid: false, keychainErrorMessage: error.localizedDescription)
        }
        guard !persistedCookies.isEmpty else {
            return Result(isValid: false, keychainErrorMessage: nil)
        }

        guard await activate(persistedCookies) else {
            return Result(isValid: false, keychainErrorMessage: nil)
        }
        for cookie in persistedCookies {
            await webCookieStore.setCookie(cookie)
        }
        return Result(isValid: true, keychainErrorMessage: nil)
    }

    static func syncCookies(from cookieStore: WKHTTPCookieStore) async -> Result {
        let cookies = await cookieStore.cookies().filter(\.isValidV2EXCookie)
        guard !cookies.isEmpty else { return Result(isValid: false, keychainErrorMessage: nil) }

        guard await activate(cookies) else { return Result(isValid: false, keychainErrorMessage: nil) }
        do {
            try keychain.saveCookies(cookies)
            return Result(isValid: true, keychainErrorMessage: nil)
        } catch {
            return Result(isValid: true, keychainErrorMessage: error.localizedDescription)
        }
    }

    static func validate(session: URLSession = .shared) async -> Bool {
        let url = baseURL.appendingPathComponent("my/topics")
        let request = V2EXRequestBuilder.publicRequest(
            url: url,
            accept: "text/html,application/xhtml+xml"
        )

        guard let (_, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.url?.host?.lowercased() == "www.v2ex.com",
              response.url?.path == "/my/topics"
        else { return false }
        return true
    }

    private static func activate(_ cookies: [HTTPCookie]) async -> Bool {
        guard !cookies.isEmpty else { return false }
        guard await validate(cookies: cookies) else { return false }
        cookies.forEach(HTTPCookieStorage.shared.setCookie)
        return true
    }

    private static func validate(cookies: [HTTPCookie], session: URLSession = .shared) async -> Bool {
        let url = baseURL.appendingPathComponent("my/topics")
        var request = V2EXRequestBuilder.publicRequest(
            url: url,
            accept: "text/html,application/xhtml+xml",
            handlesCookies: false
        )
        HTTPCookie.requestHeaderFields(with: cookies).forEach {
            request.setValue($0.value, forHTTPHeaderField: $0.key)
        }

        guard let (_, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.url?.host?.lowercased() == "www.v2ex.com",
              response.url?.path == "/my/topics"
        else { return false }
        return true
    }

    static func clearCookies() async -> String? {
        let webCookieStore = WKWebsiteDataStore.default().httpCookieStore
        let webCookies = await webCookieStore.cookies()
        for cookie in webCookies where cookie.isV2EXCookie {
            await webCookieStore.deleteCookie(cookie)
        }

        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.isV2EXCookie {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        do {
            try keychain.deleteCookies()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

private struct V2EXWebCookieKeychainStore {
    private let service = "com.godmiracle.forumhub.v2ex.cookies"
    private let account = "v2ex-web-login-cookies"

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

private extension HTTPCookie {
    var isV2EXCookie: Bool {
        domain.lowercased() == "v2ex.com" || domain.lowercased().hasSuffix(".v2ex.com")
    }

    var isValidV2EXCookie: Bool {
        isV2EXCookie && (expiresDate == nil || expiresDate! > .now)
    }
}

private extension WKHTTPCookieStore {
    func setCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            setCookie(cookie) { continuation.resume() }
        }
    }

    func cookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { continuation.resume(returning: $0) }
        }
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            delete(cookie) { continuation.resume() }
        }
    }
}
