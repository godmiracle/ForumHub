import SwiftUI

struct LinuxDoAccountView: View {
    @Bindable var authStore: LinuxDoAuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsLoginSheet = false
    @State private var showsLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        accountCard
                        helpCard
                    }
                    .padding(20)
                }
            }
            .navigationTitle("LINUX DO 连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showsLoginSheet) {
                LinuxDoLoginSheet(authStore: authStore)
            }
            .confirmationDialog("退出 LINUX DO？", isPresented: $showsLogoutConfirmation) {
                Button("退出登录", role: .destructive) {
                    Task {
                        await authStore.logout()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会清除本机保存的 LINUX DO Cookie 和账号缓存。")
            }
        }
    }

    @ViewBuilder
    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let account = authStore.account {
                HStack(spacing: 14) {
                    AvatarView(name: account.displayName)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.displayName)
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(PaperTheme.ink)
                        Text(account.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(PaperTheme.mutedText)
                    }
                }

                if let message = authStore.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(PaperTheme.accent)
                }

                if let message = authStore.keychainErrorMessage {
                    Label(message, systemImage: "exclamationmark.icloud")
                        .font(.footnote)
                        .foregroundStyle(PaperTheme.accent)
                }

                Button {
                    Task {
                        await authStore.refreshAccount()
                    }
                } label: {
                    HStack {
                        if authStore.isRefreshing {
                            ProgressView().tint(.white)
                        }
                        Text(authStore.isRefreshing ? "正在刷新" : "刷新账号信息")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.18, green: 0.48, blue: 0.38))
                .disabled(authStore.isRefreshing)

                Button("重新登录") {
                    authStore.clearError()
                    showsLoginSheet = true
                }
                .buttonStyle(.bordered)
                .tint(PaperTheme.secondaryInk)

                Button(role: .destructive) {
                    showsLogoutConfirmation = true
                } label: {
                    Label("退出 LINUX DO", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(PaperTheme.accent)
            } else {
                Label("通过网页登录并复用 Cookie", systemImage: "network")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(PaperTheme.ink)

                Text("会打开 LINUX DO 网页，完成登录和浏览器验证后，App 会同步 Cookie，并尝试读取当前账号信息。")
                    .font(.subheadline)
                    .foregroundStyle(PaperTheme.mutedText)
                    .lineSpacing(3)

                if let message = authStore.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(PaperTheme.accent)
                }


                if let message = authStore.keychainErrorMessage {
                    Label(message, systemImage: "exclamationmark.icloud")
                        .font(.footnote)
                        .foregroundStyle(PaperTheme.accent)
                }

                Button("打开网页登录") {
                    authStore.clearError()
                    showsLoginSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.18, green: 0.48, blue: 0.38))
            }
        }
        .padding(18)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("使用说明")
                .font(.headline)
                .foregroundStyle(PaperTheme.ink)
            Text("如果网页里先出现 Cloudflare 或其他验证页面，先在网页中完成它，再继续登录。当前这版主要用于识别登录状态和读取账号信息，不保证所有需要身份的论坛接口都已经完全放行。")
                .font(.subheadline)
                .foregroundStyle(PaperTheme.mutedText)
                .lineSpacing(3)
        }
        .padding(18)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
