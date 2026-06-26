import Foundation

enum NGAJSONParser {
    static func object(from data: Data, fallbackText: String) -> Any? {
        if let object = try? JSONSerialization.jsonObject(with: data) {
            return object
        }

        let text = normalizedJSONText(fallbackText)
        guard let normalizedData = text.data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: normalizedData)
    }

    private static func normalizedJSONText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startIndex = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return trimmed
        }

        var json = String(trimmed[startIndex...])
        if json.hasSuffix(";") {
            json.removeLast()
        }

        return json
    }
}

extension String {
    var isUsefulForumValue: Bool {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        let placeholders = [
            "未知作者",
            "未知时间",
            "网页内容",
            "来自网页兜底解析"
        ]

        if placeholders.contains(value) {
            return false
        }

        if value.range(of: #"^帖子\s+\d+$"#, options: .regularExpression) != nil {
            return false
        }

        return true
    }

    func matches(pattern: String, options: NSRegularExpression.Options = []) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).map { result in
            (0..<result.numberOfRanges).map { index in
                let range = result.range(at: index)
                guard let stringRange = Range(range, in: self) else {
                    return ""
                }

                return String(self[stringRange])
            }
        }
    }

    var cleanedForumText: String {
        decodedUnicodeEscapes
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"\[img\](.*?)\[/img\]"#, with: "\n[图片] $1", options: .regularExpression)
            .replacingOccurrences(of: #"\[/?[a-zA-Z][^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var decodedUnicodeEscapes: String {
        let quoted = "\"\(replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
            .replacingOccurrences(of: "\\\\u", with: "\\u")
            .replacingOccurrences(of: "\\\\/", with: "/")

        guard let data = quoted.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? String
        else {
            return self
        }

        return decoded
    }
}

extension Array where Element == Reply {
    func uniquedByID() -> [Reply] {
        var seen = Set<Int>()
        return filter { seen.insert($0.id).inserted }
    }
}

extension Array where Element == ForumThread {
    func uniquedByThreadID() -> [ForumThread] {
        var seen = Set<Int>()
        return filter { seen.insert($0.id).inserted }
    }
}

extension Array where Element == ForumChannel {
    func uniquedByChannelID() -> [ForumChannel] {
        var seen = Set<Int>()
        return filter { seen.insert($0.id).inserted }
    }
}

