import SwiftUI
import WebKit

struct NGALoginSheet: View {
    let onLogin: () -> Void
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

                NGAWebLoginView {
                    onLogin()
                } onMessage: { message in
                    self.message = message
                }
            }
            .navigationTitle("登录 NGA")
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
                            let loginState = await NGAAuthStore.shared.syncDefaultCookies()
                            await MainActor.run {
                                if loginState.isLoggedIn {
                                    onLogin()
                                } else {
                                    message = "还没有检测到有效登录 cookie。请确认网页登录已经成功，再点完成。"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct NGAWebLoginView: UIViewRepresentable {
    let onLogin: () -> Void
    let onMessage: (String) -> Void

    init(onLogin: @escaping () -> Void, onMessage: @escaping (String) -> Void) {
        self.onLogin = onLogin
        self.onMessage = onMessage
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLogin: onLogin, onMessage: onMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        let url = URL(string: "https://bbs.nga.cn/nuke.php?__lib=login&__act=account&login")!
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let onLogin: () -> Void
        private let onMessage: (String) -> Void
        private var didNotifyLogin = false

        init(onLogin: @escaping () -> Void, onMessage: @escaping (String) -> Void) {
            self.onLogin = onLogin
            self.onMessage = onMessage
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                await syncAndMaybeFinish(from: webView, message: nil)
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
                await syncAndMaybeFinish(from: webView, message: message)
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
                await syncAndMaybeFinish(from: webView, message: message)
            }
        }

        private func syncAndMaybeFinish(from webView: WKWebView, message: String?) async {
            if let message, !message.isEmpty {
                await MainActor.run {
                    onMessage(message)
                }
            }

            let loginState = await NGAAuthStore.shared.syncAndReadLoginState(from: webView.configuration.websiteDataStore.httpCookieStore)
            guard loginState.isLoggedIn, !didNotifyLogin else { return }
            didNotifyLogin = true
            await MainActor.run {
                onLogin()
            }
        }
    }
}

