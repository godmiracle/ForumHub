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
                Text("会删除保存在 iCloud Keychain 中的 Token，不影响 V2EX 网站账号。")
            }
            .confirmationDialog("退出 V2EX 网页登录？", isPresented: $showsWebLogoutConfirmation) {
                Button("退出网页登录", role: .destructive) {
                    Task {
                        await authStore.logoutWebSession()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会清除本机 App 内网页 Cookie，并删除 iCloud Keychain 中的会话备份，不影响 API Token。")
            }
            .sheet(isPresented: $showsWebLogin) {
                V2EXWebLoginSheet(authStore: authStore) {
                    showsWebLogin = false
                }
            }
            .onChange(of: token) {
                authStore.clearError()
            }
        }
        .task {
            await authStore.refreshWebSession()
        }
    }

    private var webConnectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("网页登录", systemImage: "globe")
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(PaperTheme.ink)

            Text(authStore.hasWebSession
                 ? "网页登录有效，可同步 V2EX 站点收藏并复用到网页原帖。"
                 : "用于 V2EX 站点收藏和网页原帖，不会向网页暴露 API Token。")
                .font(.subheadline)
                .foregroundStyle(PaperTheme.mutedText)
                .lineSpacing(3)

            if let message = authStore.webSessionSyncErrorMessage {
                Label(message, systemImage: "exclamationmark.icloud")
                    .font(.footnote)
                    .foregroundStyle(PaperTheme.accent)
            }

            if authStore.hasWebSession {
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
    @Bindable var authStore: V2EXAuthStore
    let onCompleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hasDetectedLogin = false

    var body: some View {
        NavigationStack {
            V2EXWebLoginView(authStore: authStore) {
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
    @Bindable var authStore: V2EXAuthStore
    let onLoginDetected: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(authStore: authStore, onLoginDetected: onLoginDetected)
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
        @MainActor @Bindable private var authStore: V2EXAuthStore
        private let onLoginDetected: () -> Void
        private var didDetectLogin = false

        init(authStore: V2EXAuthStore, onLoginDetected: @escaping () -> Void) {
            _authStore = Bindable(authStore)
            self.onLoginDetected = onLoginDetected
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                guard await authStore.syncWebSession(
                    from: webView.configuration.websiteDataStore.httpCookieStore
                ), !didDetectLogin else { return }
                didDetectLogin = true
                await MainActor.run { onLoginDetected() }
            }
        }
    }
}
