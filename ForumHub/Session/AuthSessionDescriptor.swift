import Foundation

struct AuthSessionDescriptor: Identifiable, Equatable {
    enum Action: Equatable {
        case none
        case login
        case manage
    }

    let source: ForumSource
    let title: String
    let statusText: String
    let detailText: String?
    let connectionKindText: String
    let isAuthenticated: Bool
    let action: Action
    let actionTitle: String?

    var id: ForumSource { source }
}

protocol AuthSessionDescriptorProviding {
    var authSessionDescriptor: AuthSessionDescriptor { get }
}

@MainActor
struct AuthSessionRegistry {
    private let descriptorsBySource: [ForumSource: AuthSessionDescriptor]

    init(
        ngaLoginState: NGALoginState,
        v2exAuthStore: V2EXAuthStore,
        linuxDoAuthStore: LinuxDoAuthStore
    ) {
        let descriptors = [
            ngaLoginState.authSessionDescriptor,
            v2exAuthStore.authSessionDescriptor,
            linuxDoAuthStore.authSessionDescriptor
        ]
        descriptorsBySource = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.source, $0) })
    }

    func descriptors(for sources: [ForumSource]) -> [AuthSessionDescriptor] {
        sources.compactMap { descriptorsBySource[$0] }
    }

    func descriptor(for source: ForumSource) -> AuthSessionDescriptor? {
        descriptorsBySource[source]
    }

    static func restoreAll(
        ngaRestore: @escaping @MainActor () async -> Void,
        v2exAuthStore: V2EXAuthStore,
        linuxDoAuthStore: LinuxDoAuthStore
    ) async {
        async let ngaSession: Void = ngaRestore()
        async let v2exSession: Void = v2exAuthStore.restoreSession()
        async let linuxDoSession: Void = linuxDoAuthStore.restoreSession()
        _ = await (ngaSession, v2exSession, linuxDoSession)
    }
}

extension NGALoginState: AuthSessionDescriptorProviding {
    var authSessionDescriptor: AuthSessionDescriptor {
        AuthSessionDescriptor(
            source: .nga,
            title: ForumSource.nga.title,
            statusText: isLoggedIn ? "已连接" : "游客浏览",
            detailText: isLoggedIn ? identitySummary : "登录后可使用完整 NGA 会话",
            connectionKindText: "网页登录",
            isAuthenticated: isLoggedIn,
            action: isLoggedIn ? .none : .login,
            actionTitle: isLoggedIn ? nil : "连接"
        )
    }
}

extension V2EXAuthStore: AuthSessionDescriptorProviding {
    var authSessionDescriptor: AuthSessionDescriptor {
        AuthSessionDescriptor(
            source: .v2ex,
            title: ForumSource.v2ex.title,
            statusText: isAuthenticated ? "已连接" : "未连接",
            detailText: isAuthenticated ? "@\(username ?? "V2EX")" : "连接后可使用账号相关能力",
            connectionKindText: "访问令牌",
            isAuthenticated: isAuthenticated,
            action: .manage,
            actionTitle: isAuthenticated ? "管理" : "连接"
        )
    }
}

extension LinuxDoAuthStore: AuthSessionDescriptorProviding {
    var authSessionDescriptor: AuthSessionDescriptor {
        AuthSessionDescriptor(
            source: .linuxDo,
            title: ForumSource.linuxDo.title,
            statusText: isAuthenticated ? "已连接" : "未连接",
            detailText: isAuthenticated ? account?.subtitle : "连接后可读取当前账号状态",
            connectionKindText: "网页登录",
            isAuthenticated: isAuthenticated,
            action: .manage,
            actionTitle: isAuthenticated ? "管理" : "连接"
        )
    }
}
