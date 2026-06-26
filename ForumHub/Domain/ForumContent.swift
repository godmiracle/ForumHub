import Foundation

struct ForumContentBlock: Identifiable, Equatable {
    enum Content: Equatable {
        case text(String)
        case image(URL)
    }

    let id: Int
    let content: Content
}

enum ForumContentParser {
    private static let imagePattern = #"(?m)^[\t ]*\[图片\][\t ]*(https?://[^\s]+)[\t ]*$"#

    static func parse(_ text: String) -> [ForumContentBlock] {
        guard let expression = try? NSRegularExpression(pattern: imagePattern) else {
            return text.isEmpty ? [] : [ForumContentBlock(id: 0, content: .text(text))]
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = expression.matches(in: text, range: fullRange)
        guard !matches.isEmpty else {
            return text.isEmpty ? [] : [ForumContentBlock(id: 0, content: .text(text))]
        }

        var blocks: [ForumContentBlock] = []
        var cursor = text.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: text),
                  let urlRange = Range(match.range(at: 1), in: text),
                  let url = URL(string: String(text[urlRange]))
            else {
                continue
            }

            appendText(String(text[cursor..<matchRange.lowerBound]), to: &blocks)
            blocks.append(ForumContentBlock(id: blocks.count, content: .image(url)))
            cursor = matchRange.upperBound
        }

        appendText(String(text[cursor...]), to: &blocks)
        return blocks
    }

    private static func appendText(_ text: String, to blocks: inout [ForumContentBlock]) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        blocks.append(ForumContentBlock(id: blocks.count, content: .text(value)))
    }
}
