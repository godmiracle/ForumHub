import Foundation

struct ForumContentBlock: Identifiable, Equatable {
    enum Content: Equatable {
        case text(String)
        case image(URL)
        case quote(ForumQuoteBlock)
    }

    let id: Int
    let content: Content
}

struct ForumQuoteBlock: Equatable {
    let author: String
    let createdAt: String
    let body: String
}

enum ForumContentParser {
    private static let tokenPattern = #"(?ms)\[引用 author="(.*?)" time="(.*?)"\](.*?)\[/引用\]|(?m)^[\t ]*\[图片\][\t ]*(https?://[^\s]+)[\t ]*$"#
    private static let expression = try? NSRegularExpression(pattern: tokenPattern)
    private static let legacyLeadingQuotePattern = #"(?ms)\AReply(?: to Reply)? Post by (.*?) \((.*?)\)\s*(.*)\z"#
    private static let legacyLeadingQuoteExpression = try? NSRegularExpression(pattern: legacyLeadingQuotePattern)
    private static let cache = NSCache<NSString, ForumContentBlockArrayBox>()

    static func parse(_ text: String) -> [ForumContentBlock] {
        let cacheKey = text as NSString
        if let cachedBlocks = cache.object(forKey: cacheKey)?.blocks {
            return cachedBlocks
        }

        if let legacyBlocks = parseLegacyLeadingQuote(in: text) {
            cache.setObject(ForumContentBlockArrayBox(legacyBlocks), forKey: cacheKey)
            return legacyBlocks
        }

        guard let expression else {
            return text.isEmpty ? [] : [ForumContentBlock(id: 0, content: .text(text))]
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = expression.matches(in: text, range: fullRange)
        guard !matches.isEmpty else {
            let blocks = text.isEmpty ? [] : [ForumContentBlock(id: 0, content: .text(text))]
            cache.setObject(ForumContentBlockArrayBox(blocks), forKey: cacheKey)
            return blocks
        }

        var blocks: [ForumContentBlock] = []
        var cursor = text.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }

            appendText(String(text[cursor..<matchRange.lowerBound]), to: &blocks)

            if let authorRange = Range(match.range(at: 1), in: text),
               let timeRange = Range(match.range(at: 2), in: text),
               let bodyRange = Range(match.range(at: 3), in: text) {
                blocks.append(
                    ForumContentBlock(
                        id: blocks.count,
                        content: .quote(
                            ForumQuoteBlock(
                                author: String(text[authorRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                                createdAt: String(text[timeRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                                body: String(text[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        )
                    )
                )
            } else if let urlRange = Range(match.range(at: 4), in: text),
                      let url = URL(string: String(text[urlRange])) {
                blocks.append(ForumContentBlock(id: blocks.count, content: .image(url)))
            }
            cursor = matchRange.upperBound
        }

        appendText(String(text[cursor...]), to: &blocks)
        cache.setObject(ForumContentBlockArrayBox(blocks), forKey: cacheKey)
        return blocks
    }

    private static func appendText(_ text: String, to blocks: inout [ForumContentBlock]) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        blocks.append(ForumContentBlock(id: blocks.count, content: .text(value)))
    }

    static func containsQuoteBlock(in text: String) -> Bool {
        parse(text).contains {
            if case .quote = $0.content {
                return true
            }
            return false
        }
    }

    private static func parseLegacyLeadingQuote(in text: String) -> [ForumContentBlock]? {
        guard let legacyLeadingQuoteExpression else { return nil }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = legacyLeadingQuoteExpression.firstMatch(in: text, range: fullRange),
              let authorRange = Range(match.range(at: 1), in: text),
              let timeRange = Range(match.range(at: 2), in: text),
              let bodyRange = Range(match.range(at: 3), in: text)
        else {
            return nil
        }

        let author = String(text[authorRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt = String(text[timeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(text[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !author.isEmpty, !body.isEmpty else { return nil }

        return [
            ForumContentBlock(
                id: 0,
                content: .quote(
                    ForumQuoteBlock(
                        author: author,
                        createdAt: createdAt,
                        body: body
                    )
                )
            )
        ]
    }
}

private final class ForumContentBlockArrayBox: NSObject {
    let blocks: [ForumContentBlock]

    init(_ blocks: [ForumContentBlock]) {
        self.blocks = blocks
    }
}
