import Foundation
import Testing
@testable import ForumHub

private final class DailyCheckInFixtureMarker {}

private func dailyFixture(_ name: String, extension fileExtension: String) throws -> Data {
    let bundle = Bundle(for: DailyCheckInFixtureMarker.self)
    let url = bundle.url(
        forResource: name,
        withExtension: fileExtension,
        subdirectory: "Fixtures"
    ) ?? bundle.url(forResource: name, withExtension: fileExtension)
    let resolvedURL = try #require(url)
    return try Data(contentsOf: resolvedURL)
}

private func dailyResponse(
    for url: URL,
    statusCode: Int = 200,
    contentType: String = "text/html"
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": contentType]
    )!
}

@MainActor
private final class StubDailyCheckInService: DailyCheckInServing {
    private let result: DailyCheckInResult
    private(set) var requestCount = 0

    init(result: DailyCheckInResult) {
        self.result = result
    }

    func checkInIfNeeded(
        shouldContinue: @escaping @MainActor () -> Bool
    ) async throws -> DailyCheckInResult {
        requestCount += 1
        guard shouldContinue() else { throw CancellationError() }
        return result
    }
}

@MainActor
private final class SuspendedDailyCheckInService: DailyCheckInServing {
    private var continuation: CheckedContinuation<DailyCheckInResult, Never>?
    private(set) var requestCount = 0
    var isWaiting: Bool { continuation != nil }

    func checkInIfNeeded(
        shouldContinue: @escaping @MainActor () -> Bool
    ) async throws -> DailyCheckInResult {
        try Task.checkCancellation()
        requestCount += 1
        let result = await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
        guard shouldContinue() else { throw CancellationError() }
        return result
    }

    func resume(with result: DailyCheckInResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
private final class SessionSwitchDailyCheckInService: DailyCheckInServing {
    private var statusContinuation: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0
    private(set) var actionCount = 0
    private(set) var maximumConcurrentRequests = 0
    private var activeRequests = 0

    var isWaitingAfterStatusRead: Bool { statusContinuation != nil }

    func checkInIfNeeded(
        shouldContinue: @escaping @MainActor () -> Bool
    ) async throws -> DailyCheckInResult {
        requestCount += 1
        activeRequests += 1
        maximumConcurrentRequests = max(maximumConcurrentRequests, activeRequests)
        defer { activeRequests -= 1 }

        guard requestCount == 1 else { return .alreadyCheckedIn }
        await withCheckedContinuation { statusContinuation = $0 }
        try Task.checkCancellation()
        guard shouldContinue() else { throw CancellationError() }
        actionCount += 1
        return .checkedInNow
    }

    func releaseStatusRead() {
        statusContinuation?.resume()
        statusContinuation = nil
    }
}

@MainActor
struct DailyCheckInParserTests {
    @Test func productionPoliciesUnlockOnlyObservedV2EXFlow() {
        #expect(!NGADailyCheckInEvidencePolicy.production.allowsProductionWrite)
        #expect(V2EXDailyCheckInEvidencePolicy.production.allowsProductionWrite)
        #expect(V2EXDailyCheckInEvidencePolicy.production.confirmedActionPath == "/mission/daily/redeem")
    }

    @Test func ngaObservedAlreadyCheckedInIsRecognizedWithoutWriteEvidence() throws {
        let data = try dailyFixture("nga-check-in-already-observed-sanitized", extension: "json")
        #expect(NGADailyCheckInParser.parse(data: data, policy: .production) == .alreadyCheckedIn)
    }

    @Test func ngaSyntheticStatesRequireInjectedEvidence() throws {
        let unavailable = try dailyFixture("nga-check-in-not-checked-synthetic", extension: "json")
        let success = try dailyFixture("nga-check-in-success-synthetic", extension: "json")
        let policy = NGADailyCheckInEvidencePolicy(
            confirmedNotCheckedInCodes: [1001],
            confirmedSuccessCodes: [1002],
            allowsProductionWrite: true
        )

        #expect(NGADailyCheckInParser.parse(data: unavailable, policy: .production) == .unknown)
        #expect(NGADailyCheckInParser.parse(data: unavailable, policy: policy) == .notCheckedIn)
        #expect(NGADailyCheckInParser.parse(data: success, policy: policy) == .checkedInNow)
    }

    @Test func ngaRequestBuilderUsesConfirmedEndpointAndRequiredHeader() {
        let status = NGADailyCheckInRequestBuilder.statusRequest()
        let write = NGADailyCheckInRequestBuilder.checkInRequest()

        #expect(status.url?.host == "bbs.nga.cn")
        #expect(status.url?.path == "/nuke.php")
        #expect(status.httpMethod == "GET")
        #expect(write.httpMethod == "POST")
        #expect(write.value(forHTTPHeaderField: "X-User-Agent") == "Nga_Official")
        #expect(status.httpShouldHandleCookies)
    }

    @Test func v2exObservedClaimedPageAndLoginRedirectAreStrictlyClassified() throws {
        let data = try dailyFixture("v2ex-daily-already-observed-sanitized", extension: "html")
        #expect(V2EXDailyCheckInPageParser.parse(
            data: data,
            finalURL: URL(string: "https://www.v2ex.com/mission/daily"),
            contentType: "text/html",
            policy: .production
        ) == .alreadyCheckedIn)
        #expect(V2EXDailyCheckInPageParser.parse(
            data: Data(),
            finalURL: URL(string: "https://www.v2ex.com/signin?next=%2Fmission%2Fdaily"),
            contentType: nil,
            policy: .production
        ) == .authenticationRequired)
    }

    @Test func v2exObservedOnclickActionIsAcceptedByProductionPolicy() throws {
        let data = try dailyFixture("v2ex-daily-available-observed-sanitized", extension: "html")

        guard case let .available(action) = V2EXDailyCheckInPageParser.parse(
            data: data,
            finalURL: URL(string: "https://www.v2ex.com/mission/daily"),
            contentType: "text/html",
            policy: .production
        ) else {
            Issue.record("真实脱敏 onclick 结构应能解析领取动作")
            return
        }
        #expect(action.scheme == "https")
        #expect(action.host == "www.v2ex.com")
        #expect(action.path == "/mission/daily/redeem")
        #expect(action.query == "once=OBSERVED_NON_REPLAYABLE")
    }

    @Test func v2exRejectsHistoricalHrefAndUnsafeOnclickShapes() throws {
        let historicalHref = try dailyFixture("v2ex-daily-available-synthetic", extension: "html")
        #expect(V2EXDailyCheckInPageParser.parse(
            data: historicalHref,
            finalURL: URL(string: "https://www.v2ex.com/mission/daily"),
            contentType: "text/html",
            policy: .production
        ) == .unknown)

        let unsafeOnclicks = [
            "fetch('/mission/daily/redeem?once=x')",
            "location.href = '/mission/daily/redeem?once=x&topic=1';",
            "location.href = 'https://evil.invalid/mission/daily/redeem?once=x';",
            "location.href = '/mission/daily/redeem?once=';",
            "location.href = '/mission/daily/redeem?once=x'; alert('x');"
        ]
        for onclick in unsafeOnclicks {
            let html = """
            <input type="button" value="领取 [已脱敏] 铜币" onclick="\(onclick)" />
            """
            #expect(V2EXDailyCheckInPageParser.parse(
                data: Data(html.utf8),
                finalURL: URL(string: "https://www.v2ex.com/mission/daily"),
                contentType: "text/html",
                policy: .production
            ) == .unknown)
        }

        #expect(V2EXDailyCheckInActionValidator.validatedURL(
            href: "https://evil.invalid/mission/daily/redeem?once=x",
            confirmedPath: "/mission/daily/redeem"
        ) == nil)
        #expect(V2EXDailyCheckInActionValidator.validatedURL(
            href: "http://www.v2ex.com/mission/daily/redeem?once=x",
            confirmedPath: "/mission/daily/redeem"
        ) == nil)
        #expect(V2EXDailyCheckInActionValidator.validatedURL(
            href: "/mission/daily/redeem?once=x&topic=1",
            confirmedPath: "/mission/daily/redeem"
        ) == nil)
    }

    @Test func v2exRejectsMultipleClaimCandidatesAndUnknownInputStructure() {
        let multiple = """
        <input type="button" value="领取 [已脱敏] 铜币" onclick="location.href = '/mission/daily/redeem?once=ONE';" />
        <input type="button" value="领取 [已脱敏] 铜币" />
        """
        let unknown = """
        <button data-action="/mission/daily/redeem?once=UNKNOWN">领取 [已脱敏] 铜币</button>
        """
        for html in [multiple, unknown] {
            #expect(V2EXDailyCheckInPageParser.parse(
                data: Data(html.utf8),
                finalURL: URL(string: "https://www.v2ex.com/mission/daily"),
                contentType: "text/html",
                policy: .production
            ) == .unknown)
        }
    }

    @Test func v2exDailyPageRejectsUnexpectedOriginPathAndContentType() throws {
        let data = try dailyFixture("v2ex-daily-available-synthetic", extension: "html")
        let policy = V2EXDailyCheckInEvidencePolicy(
            confirmedActionPath: "/mission/daily/redeem",
            allowsProductionWrite: true
        )
        let rejectedResponses: [(URL, String?)] = [
            (URL(string: "https://evil.invalid/mission/daily")!, "text/html"),
            (URL(string: "http://www.v2ex.com/mission/daily")!, "text/html"),
            (URL(string: "https://www.v2ex.com/mission/other")!, "text/html"),
            (URL(string: "https://www.v2ex.com/mission/daily")!, "application/json")
        ]

        for (url, contentType) in rejectedResponses {
            #expect(V2EXDailyCheckInPageParser.parse(
                data: data,
                finalURL: url,
                contentType: contentType,
                policy: policy
            ) == .unknown)
        }
    }
}

@MainActor
struct DailyCheckInServiceTests {
    @Test func ngaUnknownStatusNeverReachesWriteRequest() async throws {
        var requests: [URLRequest] = []
        let service = NGADailyCheckInService(
            isSessionEligible: { true },
            loader: { request in
                requests.append(request)
                return (Data("{}".utf8), dailyResponse(for: request.url!))
            }
        )

        let result = try await service.checkInIfNeeded(shouldContinue: { true })
        #expect(result == .blockedForCurrentWindow)
        #expect(requests.count == 1)
        #expect(requests.first?.url?.query?.contains("get_stat") == true)
    }

    @Test func v2exTokenOnlySessionNeverLoadsDailyPage() async throws {
        var requestCount = 0
        let service = V2EXDailyCheckInService(
            hasWebSession: { false },
            loader: { request in
                requestCount += 1
                return (Data(), dailyResponse(for: request.url!))
            }
        )

        let result = try await service.checkInIfNeeded(shouldContinue: { true })
        #expect(result == .ineligibleSession)
        #expect(requestCount == 0)
    }

    @Test func v2exSyntheticFlowUsesOneActionAndConfirmsAfterward() async throws {
        let available = try dailyFixture("v2ex-daily-available-observed-sanitized", extension: "html")
        let claimed = try dailyFixture("v2ex-daily-already-observed-sanitized", extension: "html")
        var requests: [URLRequest] = []
        let service = V2EXDailyCheckInService(
            hasWebSession: { true },
            loader: { request in
                requests.append(request)
                let data = requests.count == 1 ? available : (requests.count == 2 ? Data() : claimed)
                return (data, dailyResponse(for: request.url!))
            }
        )

        let result = try await service.checkInIfNeeded(shouldContinue: { true })
        #expect(result == .checkedInNow)
        #expect(requests.count == 3)
        #expect(requests.filter { $0.url?.path == "/mission/daily/redeem" }.count == 1)
    }

    @Test func v2exUnexpectedFinalURLNeverReachesActionRequest() async throws {
        let available = try dailyFixture("v2ex-daily-available-observed-sanitized", extension: "html")
        var requests: [URLRequest] = []
        let service = V2EXDailyCheckInService(
            hasWebSession: { true },
            loader: { request in
                requests.append(request)
                return (
                    available,
                    dailyResponse(for: URL(string: "https://evil.invalid/mission/daily")!)
                )
            }
        )

        let result = try await service.checkInIfNeeded(shouldContinue: { true })

        #expect(result == .blockedForCurrentWindow)
        #expect(requests.count == 1)
    }

    @Test func preferencesAreIndependentAndDefaultOff() throws {
        let suiteName = "DailyCheckInTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = DailyCheckInPreferences(defaults: defaults)

        #expect(!preferences.isNGAEnabled)
        #expect(!preferences.isV2EXEnabled)
        preferences.isNGAEnabled = true
        #expect(preferences.isNGAEnabled)
        #expect(!preferences.isV2EXEnabled)
        preferences.record(.alreadyCheckedIn, for: .nga, at: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(defaults.object(forKey: "daily-check-in.nga.enabled") as? Bool == true)
        #expect(defaults.object(forKey: "daily-check-in.v2ex.enabled") == nil)
        let statusData = try #require(defaults.data(forKey: "daily-check-in.safe-status.v1"))
        let statuses = try JSONDecoder().decode([ForumSource: DailyCheckInStatus].self, from: statusData)
        #expect(statuses[.nga]?.result == .alreadyCheckedIn)
    }

    @Test func coordinatorDeduplicatesInFlightRequest() async throws {
        let suiteName = "DailyCheckInTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = DailyCheckInPreferences(defaults: defaults)
        preferences.isNGAEnabled = true
        let nga = SuspendedDailyCheckInService()
        let v2ex = StubDailyCheckInService(result: .alreadyCheckedIn)
        let coordinator = DailyCheckInCoordinator(
            preferences: preferences,
            ngaService: nga,
            v2exService: v2ex
        )

        let first = Task { await coordinator.run(trigger: .launch) }
        for _ in 0..<100 where !nga.isWaiting {
            await Task.yield()
        }
        guard nga.isWaiting else {
            first.cancel()
            Issue.record("首个签到任务未进入挂起点")
            return
        }
        let second = Task { await coordinator.run(trigger: .launch) }
        await Task.yield()

        #expect(nga.requestCount == 1)
        nga.resume(with: .alreadyCheckedIn)
        await first.value
        await second.value
    }

    @Test func coordinatorThrottlesForegroundAndClearsRetryStateOnSessionChange() async throws {
        let suiteName = "DailyCheckInTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = DailyCheckInPreferences(defaults: defaults)
        preferences.isNGAEnabled = true
        let nga = StubDailyCheckInService(result: .retryableFailure)
        let v2ex = StubDailyCheckInService(result: .alreadyCheckedIn)
        var date = Date(timeIntervalSince1970: 1_700_000_000)
        let coordinator = DailyCheckInCoordinator(
            preferences: preferences,
            ngaService: nga,
            v2exService: v2ex,
            now: { date },
            foregroundThrottle: 30,
            retryBackoff: 300
        )

        await coordinator.run(trigger: .foreground)
        date.addTimeInterval(10)
        await coordinator.run(trigger: .foreground)
        #expect(nga.requestCount == 1)

        date.addTimeInterval(31)
        await coordinator.run(trigger: .foreground)
        #expect(nga.requestCount == 1)

        coordinator.sessionDidChange(for: .nga)
        date.addTimeInterval(31)
        await coordinator.run(trigger: .foreground)
        #expect(nga.requestCount == 2)
    }

    @Test func coordinatorUsesUTCServicePeriodOnlyForV2EX() async throws {
        let suiteName = "DailyCheckInTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = DailyCheckInPreferences(defaults: defaults)
        preferences.isV2EXEnabled = true
        let nga = StubDailyCheckInService(result: .alreadyCheckedIn)
        let v2ex = StubDailyCheckInService(result: .alreadyCheckedIn)
        var date = Date(timeIntervalSince1970: 1_704_153_540) // 2024-01-01 23:59 UTC
        let coordinator = DailyCheckInCoordinator(
            preferences: preferences,
            ngaService: nga,
            v2exService: v2ex,
            now: { date },
            foregroundThrottle: 0,
            retryBackoff: 0
        )

        await coordinator.run(trigger: .launch)
        date.addTimeInterval(30)
        await coordinator.run(trigger: .launch)
        #expect(v2ex.requestCount == 1)

        date.addTimeInterval(60)
        await coordinator.run(trigger: .launch)
        #expect(v2ex.requestCount == 2)
    }

    @Test func persistedCompletionDoesNotSkipColdStartServerCheck() async throws {
        let suiteName = "DailyCheckInTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistedPreferences = DailyCheckInPreferences(defaults: defaults)
        persistedPreferences.isV2EXEnabled = true
        persistedPreferences.record(
            .alreadyCheckedIn,
            for: .v2ex,
            at: Date(timeIntervalSince1970: 1_704_153_540)
        )

        let restoredPreferences = DailyCheckInPreferences(defaults: defaults)
        let nga = StubDailyCheckInService(result: .alreadyCheckedIn)
        let v2ex = StubDailyCheckInService(result: .alreadyCheckedIn)
        let coordinator = DailyCheckInCoordinator(
            preferences: restoredPreferences,
            ngaService: nga,
            v2exService: v2ex,
            now: { Date(timeIntervalSince1970: 1_704_153_570) },
            foregroundThrottle: 0,
            retryBackoff: 0
        )

        await coordinator.run(trigger: .launch)

        #expect(v2ex.requestCount == 1)
    }

    @Test func explicitSessionChangeRechecksEvenWhenEligibilityRemainsValid() async throws {
        let suiteName = "DailyCheckInTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = DailyCheckInPreferences(defaults: defaults)
        preferences.isV2EXEnabled = true
        let nga = StubDailyCheckInService(result: .alreadyCheckedIn)
        let v2ex = StubDailyCheckInService(result: .alreadyCheckedIn)
        let coordinator = DailyCheckInCoordinator(
            preferences: preferences,
            ngaService: nga,
            v2exService: v2ex,
            foregroundThrottle: 0,
            retryBackoff: 0
        )

        await coordinator.run(trigger: .launch)
        await coordinator.run(trigger: .launch)
        #expect(v2ex.requestCount == 1)

        coordinator.sessionDidChange(for: .v2ex)
        await coordinator.run(trigger: .launch)
        #expect(v2ex.requestCount == 2)
    }

    @Test func sessionChangeCancelsOldRunBeforeActionAndSerializesReplacement() async throws {
        let suiteName = "DailyCheckInTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = DailyCheckInPreferences(defaults: defaults)
        preferences.isV2EXEnabled = true
        let nga = StubDailyCheckInService(result: .alreadyCheckedIn)
        let v2ex = SessionSwitchDailyCheckInService()
        let coordinator = DailyCheckInCoordinator(
            preferences: preferences,
            ngaService: nga,
            v2exService: v2ex,
            foregroundThrottle: 0,
            retryBackoff: 0
        )

        let oldRun = Task { await coordinator.run(trigger: .launch) }
        for _ in 0..<100 where !v2ex.isWaitingAfterStatusRead {
            await Task.yield()
        }
        #expect(v2ex.isWaitingAfterStatusRead)

        coordinator.sessionDidChange(for: .v2ex)
        v2ex.releaseStatusRead()
        await oldRun.value

        #expect(v2ex.actionCount == 0)
        #expect(preferences.status(for: .v2ex) == nil)

        await coordinator.run(trigger: .launch)
        #expect(v2ex.requestCount == 2)
        #expect(v2ex.maximumConcurrentRequests == 1)
    }
}
