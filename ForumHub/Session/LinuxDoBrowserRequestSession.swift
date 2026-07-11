import Foundation
import WebKit

enum LinuxDoRequestError: LocalizedError {
    case verificationRequired
    case invalidBrowserResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .verificationRequired:
            return "LINUX DO 当前需要浏览器验证，请完成验证后重新加载。"
        case .invalidBrowserResponse:
            return "LINUX DO 浏览器请求返回了无法识别的数据。"
        case let .httpStatus(statusCode):
            return "LINUX DO 请求失败（\(statusCode)）。"
        }
    }
}

extension LinuxDoRequestError: ForumErrorConvertible {
    var forumError: ForumError {
        switch self {
        case .verificationRequired:
            return .accessDenied
        case .invalidBrowserResponse:
            return .malformedResponse
        case let .httpStatus(statusCode):
            return ForumError.fromHTTPStatus(statusCode)
        }
    }
}

@MainActor
final class LinuxDoBrowserRequestSession: NSObject, WKNavigationDelegate {
    static let shared = LinuxDoBrowserRequestSession()

    private let homeURL = URL(string: "https://linux.do/")!
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        return webView
    }()
    private var didLoadHome = false
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    func fetchJSON(from url: URL) async throws -> Data {
        try await loadHomeIfNeeded()
        try await load(url)

        let body = try await readDocumentBody()
        if body.contains("cf-mitigated") || body.contains("Just a moment") {
            throw LinuxDoRequestError.verificationRequired
        }

        let data = Data(body.utf8)
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw LinuxDoRequestError.invalidBrowserResponse
        }
        return data
    }

    func invalidateLoadedPage() {
        didLoadHome = false
    }

    private func loadHomeIfNeeded() async throws {
        guard !didLoadHome else { return }
        try await load(homeURL)
        didLoadHome = true
    }

    private func load(_ url: URL) async throws {
        guard navigationContinuation == nil else {
            throw LinuxDoRequestError.verificationRequired
        }

        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    private func readDocumentBody() async throws -> String {
        let value = try await webView.evaluateJavaScript("document.body.innerText")
        guard let body = value as? String else {
            throw LinuxDoRequestError.invalidBrowserResponse
        }
        return body
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, let continuation = navigationContinuation else { return }
            navigationContinuation = nil
            continuation.resume()
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finishNavigation(with: error)
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finishNavigation(with: error)
    }

    private nonisolated func finishNavigation(with error: Error) {
        Task { @MainActor [weak self] in
            guard let self, let continuation = navigationContinuation else { return }
            navigationContinuation = nil
            continuation.resume(throwing: error)
        }
    }
}
