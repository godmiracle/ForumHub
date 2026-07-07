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
            .decodedHTMLEntities
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\[img\](.*?)\[/img\]"#, with: "\n[图片] $1", options: .regularExpression)
            .replacingOccurrences(of: #"\[/?[a-zA-Z][^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var structuredForumText: String {
        preservingQuoteMarkers
            .decodedHTMLEntities
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\[img\](.*?)\[/img\]"#, with: "\n[图片] $1", options: .regularExpression)
            .replacingOccurrences(of: #"\[/?(?!引用\b)[a-zA-Z][^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var preservingQuoteMarkers: String {
        let normalized = decodedUnicodeEscapes
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let patterns = [
            #"\[quote\]\[pid=\d+(?:,\d+,\d+)?\]Reply\[/pid\]\s*(?:<b>)?Post by \[uid=\d+\](.*?)\[/uid\]\s*\((.*?)\):(?:</b>)?(?:<br\s*/?>|\n)*(.*?)(?:\[/quote\])"#,
            #"\[quote\]\[pid=\d+(?:,\d+,\d+)?\]Reply\[/pid\]\s*(?:<b>)?Post by (.*?)\s*\((.*?)\):(?:</b>)?(?:<br\s*/?>|\n)*(.*?)(?:\[/quote\])"#
        ]

        var value = normalized
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }

            let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
            let matches = regex.matches(in: value, range: nsRange).reversed()
            for match in matches {
                guard match.numberOfRanges >= 4,
                      let fullRange = Range(match.range(at: 0), in: value),
                      let authorRange = Range(match.range(at: 1), in: value),
                      let timeRange = Range(match.range(at: 2), in: value),
                      let bodyRange = Range(match.range(at: 3), in: value)
                else {
                    continue
                }

                let author = String(value[authorRange]).cleanedForumText
                let createdAt = String(value[timeRange]).cleanedForumText
                let body = String(value[bodyRange]).cleanedForumText
                let replacement = """
                [引用 author="\(author)" time="\(createdAt)"]
                \(body)
                [/引用]
                """
                value.replaceSubrange(fullRange, with: replacement)
            }
        }

        return value
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

    var decodedHTMLEntities: String {
        var value = self
        let replacements = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&#34;": "\"",
            "&#x27;": "'",
            "&#x22;": "\""
        ]

        for (entity, replacement) in replacements {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }

        return value
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
