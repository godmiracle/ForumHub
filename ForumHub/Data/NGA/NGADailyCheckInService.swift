import Foundation

enum NGADailyCheckInState: Equatable {
    case notCheckedIn
    case alreadyCheckedIn
    case checkedInNow
    case restricted
    case authenticationFailed
    case unknown
}

struct NGADailyCheckInEvidencePolicy: Equatable, Sendable {
    let confirmedNotCheckedInCodes: Set<Int>
    let confirmedSuccessCodes: Set<Int>
    let allowsProductionWrite: Bool

    nonisolated static let production = NGADailyCheckInEvidencePolicy(
        confirmedNotCheckedInCodes: [],
        confirmedSuccessCodes: [],
        allowsProductionWrite: false
    )
}

enum NGADailyCheckInParser {
    static func parse(data: Data, policy: NGADailyCheckInEvidencePolicy) -> NGADailyCheckInState {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }
        let code = object["code"] as? Int
        let message = (object["msg"] as? String) ?? firstErrorMessage(in: object)

        if let message, message.contains("今天已经签到了") || message.contains("今日已签到") {
            return .alreadyCheckedIn
        }
        if let code, policy.confirmedNotCheckedInCodes.contains(code) {
            return .notCheckedIn
        }
        if let code, policy.confirmedSuccessCodes.contains(code) {
            return .checkedInNow
        }
        if let message, message.contains("登录") || message.contains("认证") {
            return .authenticationFailed
        }
        if let message, message.contains("频率") || message.contains("限制") || message.contains("稍后") {
            return .restricted
        }
        return .unknown
    }

    private static func firstErrorMessage(in object: [String: Any]) -> String? {
        if let errors = object["error"] as? [String] { return errors.first }
        if let errors = object["error"] as? [Any] { return errors.first as? String }
        if let errors = object["error"] as? [String: Any] {
            return errors.keys.sorted().compactMap { errors[$0] as? String }.first
        }
        return nil
    }
}

enum NGADailyCheckInRequestBuilder {
    private static let endpoint = URL(string: "https://bbs.nga.cn/nuke.php")!

    static func statusRequest() -> URLRequest {
        request(action: "get_stat", method: "GET")
    }

    static func checkInRequest() -> URLRequest {
        var request = request(action: "check_in", method: "POST")
        request.setValue("Nga_Official", forHTTPHeaderField: "X-User-Agent")
        return request
    }

    private static func request(action: String, method: String) -> URLRequest {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "__lib", value: "check_in"),
            URLQueryItem(name: "__act", value: action),
            URLQueryItem(name: "__output", value: "8")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

@MainActor
final class NGADailyCheckInService: DailyCheckInServing {
    typealias Loader = (URLRequest) async throws -> (Data, URLResponse)

    private let isSessionEligible: () async -> Bool
    private let loader: Loader
    private let evidencePolicy: NGADailyCheckInEvidencePolicy

    init(
        isSessionEligible: @escaping () async -> Bool = {
            await NGAAuthStore.shared.currentLoginState().isLoggedIn
        },
        evidencePolicy: NGADailyCheckInEvidencePolicy = .production,
        loader: @escaping Loader = { try await URLSession.shared.data(for: $0) }
    ) {
        self.isSessionEligible = isSessionEligible
        self.evidencePolicy = evidencePolicy
        self.loader = loader
    }

    func checkInIfNeeded(
        shouldContinue: @escaping @MainActor () -> Bool
    ) async throws -> DailyCheckInResult {
        guard await isSessionEligible() else { return .ineligibleSession }
        try Task.checkCancellation()
        guard shouldContinue() else { throw CancellationError() }
        do {
            let (statusData, statusResponse) = try await loader(NGADailyCheckInRequestBuilder.statusRequest())
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            guard Self.isSuccessful(statusResponse) else { return .retryableFailure }
            switch NGADailyCheckInParser.parse(data: statusData, policy: evidencePolicy) {
            case .alreadyCheckedIn:
                return .alreadyCheckedIn
            case .notCheckedIn where evidencePolicy.allowsProductionWrite:
                break
            case .restricted, .authenticationFailed, .unknown, .notCheckedIn, .checkedInNow:
                return .blockedForCurrentWindow
            }

            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            let (writeData, writeResponse) = try await loader(NGADailyCheckInRequestBuilder.checkInRequest())
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            guard Self.isSuccessful(writeResponse) else { return .retryableFailure }
            switch NGADailyCheckInParser.parse(data: writeData, policy: evidencePolicy) {
            case .checkedInNow: return .checkedInNow
            case .alreadyCheckedIn: return .alreadyCheckedIn
            case .restricted, .authenticationFailed, .unknown, .notCheckedIn:
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
