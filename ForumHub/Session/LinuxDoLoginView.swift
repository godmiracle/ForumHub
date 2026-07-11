import SwiftUI
import WebKit

struct LinuxDoLoginSheet: View {
    @Bindable var authStore: LinuxDoAuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.yellow.opacity(0.16))
                }

                LinuxDoWebLoginView(authStore: authStore) { account in
                    message = "已识别账号 @\(account.username)"
                } onMessage: { message in
                    self.message = message
                }
            }
            .navigationTitle("连接 LINUX DO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        Task {
                            await authStore.refreshAccount()
                            LinuxDoBrowserRequestSession.shared.invalidateLoadedPage()
                            await MainActor.run {
                                if authStore.isAuthenticated {
                                    dismiss()
                                } else {
                                    message = authStore.errorMessage ?? "还没有检测到有效登录状态，请先在网页中完成登录和验证。"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct LinuxDoWebLoginView: UIViewRepresentable {
    @Bindable var authStore: LinuxDoAuthStore
    let onAccountDetected: (LinuxDoAccount) -> Void
    let onMessage: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(authStore: authStore, onAccountDetected: onAccountDetected, onMessage: onMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: URL(string: "https://linux.do/login")!))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @MainActor @Bindable private var authStore: LinuxDoAuthStore
        private let onAccountDetected: (LinuxDoAccount) -> Void
        private let onMessage: (String) -> Void
        private var didDetectAccount = false

        init(
            authStore: LinuxDoAuthStore,
            onAccountDetected: @escaping (LinuxDoAccount) -> Void,
            onMessage: @escaping (String) -> Void
        ) {
            _authStore = Bindable(authStore)
            self.onAccountDetected = onAccountDetected
            self.onMessage = onMessage
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                await syncAndMaybeResolveAccount(from: webView, message: nil)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            completionHandler()
            Task {
                await syncAndMaybeResolveAccount(from: webView, message: message)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
            Task {
                await syncAndMaybeResolveAccount(from: webView, message: message)
            }
        }

        private func syncAndMaybeResolveAccount(from webView: WKWebView, message: String?) async {
            if let message, !message.isEmpty {
                await MainActor.run {
                    onMessage(message)
                }
            }

            _ = await authStore.syncCookies(from: webView.configuration.websiteDataStore.httpCookieStore)

            guard let account = await readCurrentAccount(from: webView), !didDetectAccount else { return }
            didDetectAccount = true
            await authStore.finishWebLogin(
                with: account,
                cookieStore: webView.configuration.websiteDataStore.httpCookieStore
            )
            LinuxDoBrowserRequestSession.shared.invalidateLoadedPage()
            await MainActor.run {
                onAccountDetected(account)
            }
        }

        private func readCurrentAccount(from webView: WKWebView) async -> LinuxDoAccount? {
            let script = """
            (async function() {
              try {
                const response = await fetch('/session/current.json', { credentials: 'include' });
                return await response.text();
              } catch (error) {
                return '';
              }
            })();
            """

            let rawValue: Any?
            do {
                rawValue = try await webView.evaluateJavaScript(script)
            } catch {
                return nil
            }

            guard let text = rawValue as? String,
                  let data = text.data(using: .utf8)
            else { return nil }

            return try? LinuxDoSessionResponseParser.account(from: data)
        }
    }
}
