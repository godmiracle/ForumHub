import Foundation

enum ForumError: LocalizedError, Equatable {
    case offline
    case timeout
    case authenticationExpired
    case accessDenied
    case rateLimited
    case malformedResponse
    case sourceUnavailable
    case unsupported(String)
    case unknown

    var userMessage: String {
        switch self {
        case .offline:
            return "网络连接似乎有问题。"
        case .timeout:
            return "请求超时，请稍后重试。"
        case .authenticationExpired:
            return "登录状态已失效，请重新登录后再试。"
        case .accessDenied:
            return "当前请求被拒绝，请检查权限或稍后重试。"
        case .rateLimited:
            return "请求过于频繁，请稍后再试。"
        case .malformedResponse:
            return "论坛返回的数据暂时无法解析。"
        case .sourceUnavailable:
            return "论坛服务暂时不可用，请稍后重试。"
        case let .unsupported(message):
            return message
        case .unknown:
            return "操作未完成，请稍后重试。"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .offline:
            return "请检查网络连接后重新加载。"
        case .timeout, .rateLimited, .sourceUnavailable, .unknown:
            return "请稍后重新加载。"
        case .authenticationExpired:
            return "请在账户页面完成登录。"
        case .accessDenied:
            return "请确认账号权限或在网页完成必要验证。"
        case .malformedResponse:
            return "可以稍后刷新，或切换到其他帖子。"
        case .unsupported:
            return nil
        }
    }

    var errorDescription: String? {
        userMessage
    }

    static func resolve(_ error: any Error) -> ForumError? {
        guard !isCancellation(error) else { return nil }

        if let forumError = error as? ForumError {
            return forumError
        }
        if let convertible = error as? any ForumErrorConvertible {
            return convertible.forumError
        }
        if let urlError = error as? URLError {
            return from(urlError: urlError)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return from(urlError: URLError(URLError.Code(rawValue: nsError.code)))
        }
        return .unknown
    }

    static func fromHTTPStatus(_ statusCode: Int) -> ForumError {
        switch statusCode {
        case 401:
            return .authenticationExpired
        case 403:
            return .accessDenied
        case 429:
            return .rateLimited
        case 500...599:
            return .sourceUnavailable
        default:
            return .unknown
        }
    }

    private static func from(urlError: URLError) -> ForumError {
        switch urlError.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .dataNotAllowed,
             .internationalRoamingOff:
            return .offline
        case .userAuthenticationRequired,
             .userCancelledAuthentication:
            return .authenticationExpired
        default:
            return .unknown
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

protocol ForumErrorConvertible: Error {
    var forumError: ForumError { get }
}
