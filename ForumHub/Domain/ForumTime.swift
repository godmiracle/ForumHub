import Foundation

enum ForumTime {
    nonisolated static func parse(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "未知时间" else { return nil }

        if let timestamp = TimeInterval(value) {
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
            return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
        }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        if let minutes = capturedInteger(in: value, pattern: #"(\d+)\s*分钟前"#) {
            return calendar.date(byAdding: .minute, value: -minutes, to: now)
        }
        if let hours = capturedInteger(in: value, pattern: #"(\d+)\s*小时前"#) {
            return calendar.date(byAdding: .hour, value: -hours, to: now)
        }
        if let days = capturedInteger(in: value, pattern: #"(\d+)\s*天前"#) {
            return calendar.date(byAdding: .day, value: -days, to: now)
        }
        if let time = capturedString(in: value, pattern: #"今天\s*(\d{1,2}:\d{2})"#) {
            return dateForToday(time: time, calendar: calendar)
        }
        if let time = capturedString(in: value, pattern: #"昨天\s*(\d{1,2}:\d{2})"#),
           let today = dateForToday(time: time, calendar: calendar) {
            return calendar.date(byAdding: .day, value: -1, to: today)
        }

        for format in [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
            "MM-dd HH:mm", "M-d HH:mm"
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                guard !format.contains("yyyy") else { return date }
                var components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
                components.year = calendar.component(.year, from: now)
                return calendar.date(from: components)
            }
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        return internet.date(from: value)
    }

    nonisolated static func feedText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    nonisolated static func storageText(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    nonisolated private static func capturedInteger(in value: String, pattern: String) -> Int? {
        capturedString(in: value, pattern: pattern).flatMap(Int.init)
    }

    nonisolated private static func capturedString(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: value)
        else { return nil }
        return String(value[captureRange])
    }

    nonisolated private static func dateForToday(time: String, calendar: Calendar) -> Date? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }
}
