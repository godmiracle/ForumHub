import SwiftUI

struct V2EXAccountView: View {
    @Bindable var authStore: V2EXAuthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var token = ""
    @State private var showsLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        connectionCard
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
            .onChange(of: token) {
                authStore.clearError()
            }
        }
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
