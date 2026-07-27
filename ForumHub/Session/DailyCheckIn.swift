import Foundation
import Observation

enum DailyCheckInResult: String, Codable, Equatable, Sendable {
    case checkedInNow
    case alreadyCheckedIn
    case ineligibleSession
    case retryableFailure
    case blockedForCurrentWindow

    var safeStatusText: String {
        switch self {
        case .checkedInNow:
            return "签到成功"
        case .alreadyCheckedIn:
            return "今日已签到"
        case .ineligibleSession:
            return "需要有效登录会话"
        case .retryableFailure:
            return "暂时无法检查，请稍后重试"
        case .blockedForCurrentWindow:
            return "远端状态尚未确认，已停止自动操作"
        }
    }

    var confirmsCompletion: Bool {
        self == .checkedInNow || self == .alreadyCheckedIn
    }
}

struct DailyCheckInStatus: Codable, Equatable, Sendable {
    let result: DailyCheckInResult
    let updatedAt: Date
}

@MainActor
@Observable
final class DailyCheckInPreferences {
    private enum Key {
        static let nga = "daily-check-in.nga.enabled"
        static let v2ex = "daily-check-in.v2ex.enabled"
        static let status = "daily-check-in.safe-status.v1"
    }

    private let defaults: UserDefaults
    private(set) var statuses: [ForumSource: DailyCheckInStatus]

    var isNGAEnabled: Bool {
        didSet { defaults.set(isNGAEnabled, forKey: Key.nga) }
    }

    var isV2EXEnabled: Bool {
        didSet { defaults.set(isV2EXEnabled, forKey: Key.v2ex) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isNGAEnabled = defaults.bool(forKey: Key.nga)
        isV2EXEnabled = defaults.bool(forKey: Key.v2ex)
        if let data = defaults.data(forKey: Key.status),
           let decoded = try? JSONDecoder().decode([ForumSource: DailyCheckInStatus].self, from: data) {
            statuses = decoded
        } else {
            statuses = [:]
        }
    }

    func isEnabled(for source: ForumSource) -> Bool {
        switch source {
        case .nga: isNGAEnabled
        case .v2ex: isV2EXEnabled
        case .linuxDo: false
        }
    }

    func status(for source: ForumSource) -> DailyCheckInStatus? {
        statuses[source]
    }

    func record(_ result: DailyCheckInResult, for source: ForumSource, at date: Date) {
        guard source != .linuxDo else { return }
        statuses[source] = DailyCheckInStatus(result: result, updatedAt: date)
        if let data = try? JSONEncoder().encode(statuses) {
            defaults.set(data, forKey: Key.status)
        }
    }

    func clearRuntimeStatus(for source: ForumSource) {
        statuses.removeValue(forKey: source)
        if let data = try? JSONEncoder().encode(statuses) {
            defaults.set(data, forKey: Key.status)
        }
    }
}

@MainActor
protocol DailyCheckInServing {
    func checkInIfNeeded(
        shouldContinue: @escaping @MainActor () -> Bool
    ) async throws -> DailyCheckInResult
}

@MainActor
final class DailyCheckInCoordinator {
    enum Trigger: Equatable {
        case launch
        case foreground
    }

    private let preferences: DailyCheckInPreferences
    private let ngaService: any DailyCheckInServing
    private let v2exService: any DailyCheckInServing
    private let now: () -> Date
    private let foregroundThrottle: TimeInterval
    private let retryBackoff: TimeInterval
    private struct SourceRun {
        let generation: Int
        let task: Task<Void, Never>
    }

    private struct CompletionCache {
        let generation: Int
        let date: Date
    }

    private var sourceRuns: [ForumSource: SourceRun] = [:]
    private var sessionGenerations: [ForumSource: Int] = [:]
    private var completionCache: [ForumSource: CompletionCache] = [:]
    private var lastAttemptAt: [ForumSource: Date] = [:]
    private var lastForegroundAt: Date?

    init(
        preferences: DailyCheckInPreferences,
        ngaService: any DailyCheckInServing,
        v2exService: any DailyCheckInServing,
        now: @escaping () -> Date = Date.init,
        foregroundThrottle: TimeInterval = 30,
        retryBackoff: TimeInterval = 5 * 60
    ) {
        self.preferences = preferences
        self.ngaService = ngaService
        self.v2exService = v2exService
        self.now = now
        self.foregroundThrottle = foregroundThrottle
        self.retryBackoff = retryBackoff
    }

    func run(trigger: Trigger) async {
        let date = now()
        if trigger == .foreground,
           let lastForegroundAt,
           date.timeIntervalSince(lastForegroundAt) < foregroundThrottle {
            return
        }
        if trigger == .foreground { lastForegroundAt = date }

        async let nga: Void = run(source: .nga, service: ngaService, at: date)
        async let v2ex: Void = run(source: .v2ex, service: v2exService, at: date)
        _ = await (nga, v2ex)
    }

    func sessionDidChange(for source: ForumSource) {
        sessionGenerations[source, default: 0] += 1
        sourceRuns[source]?.task.cancel()
        lastAttemptAt[source] = nil
        completionCache[source] = nil
        preferences.clearRuntimeStatus(for: source)
    }

    private func run(source: ForumSource, service: any DailyCheckInServing, at date: Date) async {
        let generation = sessionGenerations[source, default: 0]
        if let existingRun = sourceRuns[source] {
            await existingRun.task.value
            if existingRun.generation == generation { return }
        }

        guard preferences.isEnabled(for: source) else { return }
        if let completion = completionCache[source],
           completion.generation == generation,
           isSameConfirmedServicePeriod(source: source, lhs: completion.date, rhs: date) {
            return
        }
        if let lastAttempt = lastAttemptAt[source],
           date.timeIntervalSince(lastAttempt) < retryBackoff {
            return
        }

        lastAttemptAt[source] = date
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRun(
                source: source,
                service: service,
                generation: generation
            )
        }
        sourceRuns[source] = SourceRun(generation: generation, task: task)
        await task.value
    }

    private func performRun(
        source: ForumSource,
        service: any DailyCheckInServing,
        generation: Int
    ) async {
        defer {
            if sourceRuns[source]?.generation == generation {
                sourceRuns[source] = nil
            }
        }

        do {
            let result = try await service.checkInIfNeeded { [weak self] in
                guard let self else { return false }
                return !Task.isCancelled
                    && self.sessionGenerations[source, default: 0] == generation
            }
            try Task.checkCancellation()
            guard sessionGenerations[source, default: 0] == generation else { return }
            let recordedAt = now()
            preferences.record(result, for: source, at: recordedAt)
            if result.confirmsCompletion {
                completionCache[source] = CompletionCache(
                    generation: generation,
                    date: recordedAt
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard sessionGenerations[source, default: 0] == generation else { return }
            preferences.record(.retryableFailure, for: source, at: now())
        }
    }

    private func isSameConfirmedServicePeriod(source: ForumSource, lhs: Date, rhs: Date) -> Bool {
        guard source == .v2ex else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }
}
