import SwiftUI

struct UserAccountView: View {
    let loginState: NGALoginState
    let isAuthenticated: Bool
    let repository: any ThreadRepository
    let activeSource: ForumSource
    let availableSources: [ForumSource]
    let capabilities: ForumCapabilities
    @Bindable var blockedUsers: BlockedUsersStore
    @Bindable var favoriteThreads: FavoriteThreadsStore
    @Bindable var v2exAuthStore: V2EXAuthStore
    @Bindable var linuxDoAuthStore: LinuxDoAuthStore
    let scrollToTopTrigger: Int
    let repositoryForSource: (ForumSource) -> any ThreadRepository
    let onLogin: () -> Void
    let onLogout: () async -> Void
    @State private var showsLogoutConfirmation = false
    @State private var showsClearCacheConfirmation = false
    @State private var showsCacheCleared = false
    @State private var isClearingCache = false
    @State private var showsV2EXAccount = false
    @State private var showsLinuxDoAccount = false
    private let topAnchorID = "user-top-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 1)
                    .id(topAnchorID)

                VStack(alignment: .leading, spacing: 22) {
                    if isAuthenticated {
                        HStack(spacing: 14) {
                            AvatarView(name: loginState.uid ?? "NGA")

                            VStack(alignment: .leading, spacing: 4) {
                                Text("NGA 用户")
                                    .font(.system(size: 24, weight: .bold, design: .serif))
                                    .foregroundStyle(PaperTheme.ink)
                                Text("已登录")
                                    .font(.subheadline)
                                    .foregroundStyle(PaperTheme.mutedText)
                            }
                        }

                        VStack(spacing: 0) {
                            accountRow(title: "UID", value: loginState.uid ?? "未识别")
                            Divider().overlay(PaperTheme.hairline)
                            accountRow(title: "CID", value: maskedCID)
                            Divider().overlay(PaperTheme.hairline)
                            accountRow(title: "登录凭证", value: "已保存 \(loginState.cookieNames.count) 项")
                        }
                        .padding(.horizontal, 16)
                        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("尚未登录 NGA", systemImage: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 22, weight: .bold, design: .serif))
                                .foregroundStyle(PaperTheme.ink)

                            Text("游客可以浏览公开内容。登录后可使用你的 NGA 会话访问需要身份的内容。")
                                .font(.subheadline)
                                .foregroundStyle(PaperTheme.mutedText)
                                .lineSpacing(3)

                            Button("登录 NGA") {
                                onLogin()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(PaperTheme.accent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("社区连接")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PaperTheme.mutedText)
                            .padding(.bottom, 8)

                        ForEach(availableSources) { source in
                            Button {
                                if source == .nga, !isAuthenticated {
                                    onLogin()
                                } else if source == .v2ex {
                                    showsV2EXAccount = true
                                } else if source == .linuxDo {
                                    showsLinuxDoAccount = true
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(sourceColor(source))
                                        .frame(width: 10, height: 10)
                                    Text(source.title)
                                        .font(.headline)
                                        .foregroundStyle(PaperTheme.ink)
                                    Spacer()
                                    Text(sourceStatus(source))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(PaperTheme.mutedText)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(PaperTheme.mutedText)
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            if source != availableSources.last {
                                Divider().overlay(PaperTheme.hairline)
                            }
                        }
                    }
                    .padding(16)
                    .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    NavigationLink {
                        SavedThreadsView(
                            favorites: favoriteThreads,
                            blockedUsers: blockedUsers,
                            repositoryForSource: repositoryForSource
                        )
                    } label: {
                        menuRow(
                            icon: favoriteThreads.entries.isEmpty ? "star" : "star.fill",
                            title: "本地收藏",
                            subtitle: favoriteThreads.entries.isEmpty
                                ? "收藏帖子后会保存在本机"
                                : "已收藏 \(favoriteThreads.entries.count) 个帖子"
                        )
                    }
                    .buttonStyle(.plain)

                    if capabilities.supportsFavorites, isAuthenticated {
                        NavigationLink {
                            FavoriteThreadsView(
                                repository: repository,
                                blockedUsers: blockedUsers,
                                favoriteThreads: favoriteThreads
                            )
                        } label: {
                            menuRow(
                                icon: "star.fill",
                                title: "我的收藏",
                                subtitle: "查看当前账号收藏的帖子"
                            )
                        }
                        .buttonStyle(.plain)
                    } else if capabilities.supportsFavorites {
                        Button {
                            onLogin()
                        } label: {
                            menuRow(
                                icon: "star",
                                title: "我的收藏",
                                subtitle: "登录 NGA 后查看收藏帖子"
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        menuRow(
                            icon: "star.slash",
                            title: "我的收藏",
                            subtitle: "\(activeSource.title) 官方接口暂不提供收藏列表"
                        )
                        .opacity(0.62)
                    }

                    NavigationLink {
                        BlockedUsersView(blockedUsers: blockedUsers)
                    } label: {
                        menuRow(
                            icon: "person.crop.circle.badge.xmark",
                            title: "我的屏蔽",
                            subtitle: blockedUsers.blockedUsers.isEmpty
                                ? "尚未屏蔽用户"
                                : "已屏蔽 \(blockedUsers.blockedUsers.count) 位用户"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showsClearCacheConfirmation = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash.slash")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(isClearingCache ? "正在清除缓存" : "清除缓存")
                                    .font(.headline)
                                Text("图片与网页缓存，不会退出登录")
                                    .font(.caption)
                                    .foregroundStyle(PaperTheme.mutedText)
                            }
                            Spacer()
                            if isClearingCache {
                                ProgressView()
                                    .tint(PaperTheme.mutedText)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .padding(16)
                        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isClearingCache)

                    if isAuthenticated {
                        Button(role: .destructive) {
                            showsLogoutConfirmation = true
                        } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .tint(PaperTheme.accent)

                        Text("退出后会清除本机 Keychain、WebView 和请求会话中的 NGA 登录 Cookie。")
                            .font(.footnote)
                            .foregroundStyle(PaperTheme.mutedText)
                            .lineSpacing(3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 120)
            }
            .onChange(of: scrollToTopTrigger) {
                withAnimation(.snappy(duration: 0.28)) {
                    proxy.scrollTo(topAnchorID, anchor: .top)
                }
            }
        }
        .navigationTitle("用户")
        .sheet(isPresented: $showsV2EXAccount) {
            V2EXAccountView(authStore: v2exAuthStore)
        }
        .sheet(isPresented: $showsLinuxDoAccount) {
            LinuxDoAccountView(authStore: linuxDoAuthStore)
        }
        .confirmationDialog("确认退出 NGA？", isPresented: $showsLogoutConfirmation, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task { await onLogout() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("下次使用时需要重新登录。")
        }
        .confirmationDialog("清除本地缓存？", isPresented: $showsClearCacheConfirmation, titleVisibility: .visible) {
            Button("清除缓存", role: .destructive) {
                Task {
                    isClearingCache = true
                    await AppCacheManager.clear()
                    isClearingCache = false
                    showsCacheCleared = true
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除图片和网页缓存，登录状态与版面订阅会保留。")
        }
        .alert("缓存已清除", isPresented: $showsCacheCleared) {
            Button("好", role: .cancel) {}
        }
    }

    private var maskedCID: String {
        guard let cid = loginState.cid, !cid.isEmpty else { return "未识别" }
        guard cid.count > 8 else { return cid }
        return "\(cid.prefix(4))...\(cid.suffix(4))"
    }

    private func sourceStatus(_ source: ForumSource) -> String {
        switch source {
        case .nga:
            return isAuthenticated ? "已登录 · Cookie" : "游客"
        case .v2ex:
            return v2exAuthStore.isAuthenticated
                ? "已连接 · \(v2exAuthStore.username ?? "V2EX")"
                : "公开浏览"
        case .linuxDo:
            return linuxDoAuthStore.isAuthenticated
                ? "已连接 · \(linuxDoAuthStore.username ?? "LINUX DO")"
                : "网页登录"
        }
    }

    private func sourceColor(_ source: ForumSource) -> Color {
        switch source {
        case .nga:
            return PaperTheme.accent
        case .v2ex:
            return Color(red: 0.27, green: 0.42, blue: 0.57)
        case .linuxDo:
            return Color(red: 0.18, green: 0.48, blue: 0.38)
        }
    }

    private func accountRow(title: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .foregroundStyle(PaperTheme.secondaryInk)
            Spacer()
            Text(value)
                .foregroundStyle(PaperTheme.mutedText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 16, design: .serif))
        .padding(.vertical, 15)
    }

    private func menuRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PaperTheme.mutedText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(PaperTheme.secondaryInk)
        .padding(16)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
