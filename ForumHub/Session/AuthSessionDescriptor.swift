import Foundation

enum SourceSessionState: String, Equatable, Codable {
    case checking
    case signedOut
    case authenticated
    case expired

    var isAuthenticated: Bool { self == .authenticated }
}

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
    let sessionState: SourceSessionState
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
        let state = sourceSessionState
        return AuthSessionDescriptor(
            source: .nga,
            title: ForumSource.nga.title,
            statusText: isLoggedIn ? "已连接" : "游客浏览",
            detailText: isLoggedIn ? identitySummary : "登录后可使用完整 NGA 会话",
            connectionKindText: "网页登录",
            sessionState: state,
            isAuthenticated: state.isAuthenticated,
            action: state.isAuthenticated ? .none : .login,
            actionTitle: state == .expired ? "重新连接" : (state.isAuthenticated ? nil : "连接")
        )
    }
}

extension V2EXAuthStore: AuthSessionDescriptorProviding {
    var authSessionDescriptor: AuthSessionDescriptor {
        let isConnected = isAuthenticated || hasWebSession
        let connectionKind: String
        if isAuthenticated, hasWebSession {
            connectionKind = "访问令牌 + 网页登录"
        } else if hasWebSession {
            connectionKind = "网页登录"
        } else {
            connectionKind = "访问令牌"
        }

        return AuthSessionDescriptor(
            source: .v2ex,
            title: ForumSource.v2ex.title,
            statusText: isConnected ? "已连接" : "未连接",
            detailText: isAuthenticated
                ? "@\(username ?? "V2EX")"
                : (hasWebSession ? "网页收藏会话有效" : "连接后可使用账号相关能力"),
            connectionKindText: connectionKind,
            sessionState: isConnected ? .authenticated : .signedOut,
            isAuthenticated: isConnected,
            action: .manage,
            actionTitle: isConnected ? "管理" : "连接"
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
            sessionState: isAuthenticated ? .authenticated : .signedOut,
            isAuthenticated: isAuthenticated,
            action: .manage,
            actionTitle: isAuthenticated ? "管理" : "连接"
        )
    }
}
