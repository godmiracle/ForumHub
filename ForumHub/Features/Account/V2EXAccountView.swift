import SwiftUI
import WebKit

struct V2EXAccountView: View {
    @Bindable var authStore: V2EXAuthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var token = ""
    @State private var showsLogoutConfirmation = false
    @State private var showsWebLogin = false
    @State private var showsWebLogoutConfirmation = false
    @State private var hasCompletedWebLogin = UserDefaults.standard.bool(forKey: "v2ex-web-login-completed")

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        connectionCard
                        webConnectionCard
                        tokenHelp
                    }
                    .padding(20)
                }
            }
            .navigationTitle("V2EX 连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog("退出 V2EX？", isPresented: $showsLogoutConfirmation) {
                Button("退出登录", role: .destructive) {
                    authStore.logout()
                    token = ""
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会删除保存在本机 Keychain 中的 Token，不影响 V2EX 网站账号。")
            }
            .confirmationDialog("退出 V2EX 网页登录？", isPresented: $showsWebLogoutConfirmation) {
                Button("退出网页登录", role: .destructive) {
                    Task {
                        await V2EXWebSession.clearCookies()
                        hasCompletedWebLogin = false
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会清除 App 内网页的 V2EX Cookie，不影响 API Token。")
            }
            .sheet(isPresented: $showsWebLogin) {
                V2EXWebLoginSheet {
                    hasCompletedWebLogin = true
                    showsWebLogin = false
                }
            }
            .onChange(of: token) {
                authStore.clearError()
            }
        }
    }

    private var webConnectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("网页登录", systemImage: "globe")
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(PaperTheme.ink)

            Text(hasCompletedWebLogin
                 ? "已完成网页登录。打开“浏览网页原帖”时会复用这份 Cookie 会话。"
                 : "用于 App 内“浏览网页原帖”的账号态，不会读取或使用 API Token。")
                .font(.subheadline)
                .foregroundStyle(PaperTheme.mutedText)
                .lineSpacing(3)

            if hasCompletedWebLogin {
                Button(role: .destructive) {
                    showsWebLogoutConfirmation = true
                } label: {
                    Label("退出网页登录", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(PaperTheme.accent)
            } else {
                Button {
                    showsWebLogin = true
                } label: {
                    Label("登录 V2EX 网页", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PaperTheme.accent)
            }
        }
        .padding(18)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let account = authStore.account {
                HStack(spacing: 14) {
                    AvatarView(name: account.username)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.username)
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(PaperTheme.ink)
                        Text("V2EX 已连接 · ID \(account.id)")
                            .font(.subheadline)
                            .foregroundStyle(PaperTheme.mutedText)
                    }
                }

                Button(role: .destructive) {
                    showsLogoutConfirmation = true
                } label: {
                    Label("断开 V2EX", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(PaperTheme.accent)
            } else {
                Label("使用 Personal Access Token", systemImage: "key.horizontal")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(PaperTheme.ink)

                SecureField("粘贴 V2EX Token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .padding(14)
                    .background(PaperTheme.paper, in: RoundedRectangle(cornerRadius: 12))

                if let message = authStore.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(PaperTheme.accent)
                }

                Button {
                    Task {
                        if await authStore.login(token: token) {
                            token = ""
                        }
                    }
                } label: {
                    HStack {
                        if authStore.isValidating {
                            ProgressView().tint(.white)
                        }
                        Text(authStore.isValidating ? "正在验证" : "验证并连接")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PaperTheme.accent)
                .disabled(authStore.isValidating || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var tokenHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("如何获取 Token")
                .font(.headline)
                .foregroundStyle(PaperTheme.ink)
            Text("在 V2EX 网站创建 Personal Access Token，然后粘贴到上方。App 不会保存你的账号密码，验证成功后 Token 仅存于本机 Keychain。")
                .font(.subheadline)
                .foregroundStyle(PaperTheme.mutedText)
                .lineSpacing(3)
            Button("前往 V2EX Token 设置") {
                openURL(URL(string: "https://www.v2ex.com/settings/tokens")!)
            }
            .buttonStyle(.bordered)
            .tint(PaperTheme.secondaryInk)
        }
        .padding(18)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct V2EXWebLoginSheet: View {
    let onCompleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hasDetectedLogin = false

    var body: some View {
        NavigationStack {
            V2EXWebLoginView {
                hasDetectedLogin = true
            }
            .navigationTitle("登录 V2EX 网页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        onCompleted()
                    }
                    .disabled(!hasDetectedLogin)
                }
            }
        }
    }
}

private struct V2EXWebLoginView: UIViewRepresentable {
    let onLoginDetected: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoginDetected: onLoginDetected)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: URL(string: "https://www.v2ex.com/signin")!))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onLoginDetected: () -> Void
        private var didDetectLogin = false

        init(onLoginDetected: @escaping () -> Void) {
            self.onLoginDetected = onLoginDetected
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let script = "!location.pathname.startsWith('/signin') && document.querySelector('a[href*=/signin]') === null"
            webView.evaluateJavaScript(script) { value, _ in
                guard value as? Bool == true, !self.didDetectLogin else { return }
                self.didDetectLogin = true
                DispatchQueue.main.async {
                    self.onLoginDetected()
                }
            }
        }
    }
}

private enum V2EXWebSession {
    static func clearCookies() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies where cookie.domain == "v2ex.com" || cookie.domain.hasSuffix(".v2ex.com") {
            await withCheckedContinuation { continuation in
                store.delete(cookie) { continuation.resume() }
            }
        }
    }
}
