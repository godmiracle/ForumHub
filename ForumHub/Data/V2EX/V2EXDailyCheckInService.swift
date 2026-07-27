import Foundation

enum V2EXDailyCheckInPageState: Equatable {
    case available(URL)
    case alreadyCheckedIn
    case authenticationRequired
    case unknown
}

struct V2EXDailyCheckInEvidencePolicy: Equatable, Sendable {
    let confirmedActionPath: String?
    let allowsProductionWrite: Bool

    nonisolated static let production = V2EXDailyCheckInEvidencePolicy(
        confirmedActionPath: "/mission/daily/redeem",
        allowsProductionWrite: true
    )
}

enum V2EXDailyCheckInActionValidator {
    static func href(fromOnclick onclick: String) -> String? {
        let matches = onclick.matches(
            pattern: #"^\s*location\.href\s*=\s*([\"'])([^\"']+)\1\s*;\s*$"#
        )
        guard matches.count == 1 else { return nil }
        return matches[0][2].replacingOccurrences(of: "&amp;", with: "&")
    }

    static func validatedURL(
        href: String,
        confirmedPath: String
    ) -> URL? {
        let baseURL = URL(string: "https://www.v2ex.com/")!
        guard let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
              url.scheme == "https",
              url.host?.lowercased() == "www.v2ex.com",
              url.path == confirmedPath,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              queryItems.count == 1,
              queryItems[0].name == "once",
              !(queryItems[0].value ?? "").isEmpty
        else { return nil }
        return url
    }
}

enum V2EXDailyCheckInPageParser {
    static func parse(
        data: Data,
        finalURL: URL?,
        contentType: String?,
        policy: V2EXDailyCheckInEvidencePolicy
    ) -> V2EXDailyCheckInPageState {
        if finalURL?.scheme?.lowercased() == "https",
           finalURL?.host?.lowercased() == "www.v2ex.com",
           finalURL?.path == "/signin" {
            return .authenticationRequired
        }
        guard finalURL?.scheme?.lowercased() == "https",
              finalURL?.host?.lowercased() == "www.v2ex.com",
              finalURL?.path == "/mission/daily",
              let contentType = contentType?.lowercased(),
              contentType == "text/html" || contentType == "application/xhtml+xml"
        else { return .unknown }

        let html = String(decoding: data, as: UTF8.self)
        if html.contains("每日登录奖励已领取") {
            return .alreadyCheckedIn
        }
        guard let path = policy.confirmedActionPath else { return .unknown }
        let claimInputs = html.matches(
            pattern: #"<input\b[^>]*>"#,
            options: .caseInsensitive
        ).compactMap(\.first).filter { input in
            attribute(named: "type", in: input)?.lowercased() == "button"
                && attribute(named: "value", in: input)?.matches(
                    pattern: #"^\s*领取\s+.+\s+铜币\s*$"#
                ).count == 1
        }
        guard claimInputs.count == 1,
              let onclick = attribute(named: "onclick", in: claimInputs[0]),
              let href = V2EXDailyCheckInActionValidator.href(fromOnclick: onclick),
              let action = V2EXDailyCheckInActionValidator.validatedURL(
                href: href,
                confirmedPath: path
              )
        else { return .unknown }
        return .available(action)
    }

    private static func attribute(named name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let matches = tag.matches(
            pattern: "\\b\(escapedName)\\s*=\\s*([\\\"'])(.*?)\\1",
            options: .caseInsensitive
        )
        guard matches.count == 1 else { return nil }
        return matches[0][2]
    }
}

enum V2EXDailyCheckInRequestBuilder {
    static let dailyURL = URL(string: "https://www.v2ex.com/mission/daily")!

    static func pageRequest() -> URLRequest {
        V2EXRequestBuilder.publicRequest(
            url: dailyURL,
            accept: "text/html,application/xhtml+xml"
        )
    }

    static func actionRequest(url: URL) -> URLRequest {
        V2EXRequestBuilder.publicRequest(
            url: url,
            accept: "text/html,application/xhtml+xml"
        )
    }
}

@MainActor
final class V2EXDailyCheckInService: DailyCheckInServing {
    typealias Loader = (URLRequest) async throws -> (Data, URLResponse)

    private let hasWebSession: () -> Bool
    private let evidencePolicy: V2EXDailyCheckInEvidencePolicy
    private let loader: Loader

    init(
        hasWebSession: @escaping () -> Bool,
        evidencePolicy: V2EXDailyCheckInEvidencePolicy = .production,
        loader: @escaping Loader = { try await URLSession.shared.data(for: $0) }
    ) {
        self.hasWebSession = hasWebSession
        self.evidencePolicy = evidencePolicy
        self.loader = loader
    }

    func checkInIfNeeded(
        shouldContinue: @escaping @MainActor () -> Bool
    ) async throws -> DailyCheckInResult {
        guard hasWebSession() else { return .ineligibleSession }
        try Task.checkCancellation()
        guard shouldContinue() else { throw CancellationError() }
        do {
            let (pageData, pageResponse) = try await loader(V2EXDailyCheckInRequestBuilder.pageRequest())
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            guard Self.isSuccessful(pageResponse) else { return .retryableFailure }
            let state = V2EXDailyCheckInPageParser.parse(
                data: pageData,
                finalURL: pageResponse.url,
                contentType: pageResponse.mimeType,
                policy: evidencePolicy
            )
            switch state {
            case .alreadyCheckedIn:
                return .alreadyCheckedIn
            case .authenticationRequired:
                return .ineligibleSession
            case let .available(actionURL) where evidencePolicy.allowsProductionWrite:
                try Task.checkCancellation()
                guard shouldContinue() else { throw CancellationError() }
                let (_, actionResponse) = try await loader(
                    V2EXDailyCheckInRequestBuilder.actionRequest(url: actionURL)
                )
                try Task.checkCancellation()
                guard shouldContinue() else { throw CancellationError() }
                guard Self.isSuccessful(actionResponse) else { return .retryableFailure }
                let (confirmationData, confirmationResponse) = try await loader(
                    V2EXDailyCheckInRequestBuilder.pageRequest()
                )
                try Task.checkCancellation()
                guard shouldContinue() else { throw CancellationError() }
                guard Self.isSuccessful(confirmationResponse) else { return .retryableFailure }
                let confirmation = V2EXDailyCheckInPageParser.parse(
                    data: confirmationData,
                    finalURL: confirmationResponse.url,
                    contentType: confirmationResponse.mimeType,
                    policy: evidencePolicy
                )
                return confirmation == .alreadyCheckedIn ? .checkedInNow : .blockedForCurrentWindow
            case .available, .unknown:
                return .blockedForCurrentWindow
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .retryableFailure
        }
    }

    private static func isSuccessful(_ response: URLResponse) -> Bool {
        guard let response = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(response.statusCode)
    }
}
