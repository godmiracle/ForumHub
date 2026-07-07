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
    private var authSessionRegistry: AuthSessionRegistry {
        AuthSessionRegistry(
            ngaLoginState: loginState,
            v2exAuthStore: v2exAuthStore,
            linuxDoAuthStore: linuxDoAuthStore
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 1)
                    .id(topAnchorID)

                let sessionDescriptors = authSessionRegistry.descriptors(for: availableSources)

                VStack(alignment: .leading, spacing: 22) {
                    overviewCard(sessionDescriptors: sessionDescriptors)

                    sectionHeader("社区账号")

                    VStack(spacing: 14) {
                        ForEach(sessionDescriptors) { descriptor in
                            sourceAccountCard(for: descriptor)
                        }
                    }

                    sectionHeader("我的内容")

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

                    sectionHeader("应用与维护")

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

                        Text("退出后会移除本机保存的 NGA 登录会话。")
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

    private func overviewCard(sessionDescriptors: [AuthSessionDescriptor]) -> some View {
        let connectedDescriptors = sessionDescriptors.filter(\.isAuthenticated)
        let connectedTitles = connectedDescriptors.map(\.title).joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 14) {
            Label("账号总览", systemImage: "person.crop.circle.badge.checkmark")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(PaperTheme.ink)

            Text(connectedDescriptors.isEmpty ? "当前未连接任何社区账号" : "已连接 \(connectedDescriptors.count) 个社区")
                .font(.title3.weight(.semibold))
                .foregroundStyle(PaperTheme.secondaryInk)

            Text(
                connectedDescriptors.isEmpty
                    ? "你仍然可以浏览公开内容；有需要时再连接对应社区即可。"
                    : "当前已连接：\(connectedTitles)。涉及账号能力时，会按各社区自己的登录方式处理。"
            )
            .font(.subheadline)
            .foregroundStyle(PaperTheme.mutedText)
            .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func handleSessionAction(for descriptor: AuthSessionDescriptor) {
        switch descriptor.source {
        case .nga:
            if descriptor.action == .login {
                onLogin()
            }
        case .v2ex:
            showsV2EXAccount = true
        case .linuxDo:
            showsLinuxDoAccount = true
        }
    }

    @ViewBuilder
    private func sourceAccountCard(for descriptor: AuthSessionDescriptor) -> some View {
        let content = HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(sourceColor(descriptor.source))
                .frame(width: 12, height: 12)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text(descriptor.title)
                        .font(.headline)
                        .foregroundStyle(PaperTheme.ink)

                    Text(descriptor.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(descriptor.isAuthenticated ? PaperTheme.accent : PaperTheme.mutedText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            (descriptor.isAuthenticated ? PaperTheme.accent.opacity(0.12) : PaperTheme.paperDeep.opacity(0.55)),
                            in: Capsule()
                        )
                }

                if let detailText = descriptor.detailText {
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(PaperTheme.secondaryInk)
                }

                Text("登录方式：\(descriptor.connectionKindText)")
                    .font(.caption)
                    .foregroundStyle(PaperTheme.mutedText)

                if let actionTitle = descriptor.actionTitle {
                    Text(actionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PaperTheme.accent)
                }
            }

            Spacer(minLength: 0)

            if descriptor.action != .none {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PaperTheme.mutedText)
                    .padding(.top, 6)
            }
        }
        .padding(16)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

        if descriptor.action == .none {
            content
        } else {
            Button {
                handleSessionAction(for: descriptor)
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(PaperTheme.mutedText)
            .padding(.horizontal, 2)
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
