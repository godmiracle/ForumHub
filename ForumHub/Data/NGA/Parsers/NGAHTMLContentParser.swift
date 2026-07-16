import Foundation

/// 只处理 `postcontent<floor>` 内部 HTML；DOM 细节不会进入共享领域模型。
enum NGAHTMLContentParser {
    static func parse(_ html: String, sourceURL: URL? = nil) -> ForumPostDocument {
        var markup = html
        markup = replaceImages(in: markup)
        markup = replaceLinks(in: markup)
        markup = markup.replacingOccurrences(
            of: #"(?i)<br\s*/?>"#,
            with: "[br]",
            options: .regularExpression
        )
        markup = markup.replacingOccurrences(
            of: #"(?i)</?(?:b|strong)>"#,
            with: "",
            options: .regularExpression
        )
        markup = markup.replacingOccurrences(
            of: #"(?i)</?(?:div|p|span)(?:\s+[^>]*)?>"#,
            with: "[br]",
            options: .regularExpression
        )

        let semantic = NGABBCodeContentParser.parse(markup, origin: .ngaWeb, sourceURL: sourceURL)
        let representation = ForumContentRepresentation(
            origin: .ngaWeb,
            rawMarkup: html,
            markupFormat: .html,
            sourceURL: sourceURL,
            parserVersion: 1
        )
        return ForumPostDocument(
            rawMarkup: html,
            fallbackText: semantic.bodyText,
            markupFormat: .html,
            sourceURL: sourceURL,
            representations: [representation],
            blocks: semantic.blocks,
            diagnostics: semantic.diagnostics,
            quality: semantic.quality
        )
    }

    private static func replaceImages(in html: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?is)<img\b[^>]*\bsrc\s*=\s*['\"]([^'\"]+)['\"][^>]*>"#
        ) else { return html }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return expression.stringByReplacingMatches(
            in: html,
            range: range,
            withTemplate: "[img]$1[/img]"
        )
    }

    private static func replaceLinks(in html: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?is)<a\b[^>]*\bhref\s*=\s*['\"]([^'\"]+)['\"][^>]*>(.*?)</a>"#
        ) else { return html }
        return expression.stringByReplacingMatches(
            in: html,
            range: NSRange(html.startIndex..<html.endIndex, in: html),
            withTemplate: "[url=$1]$2[/url]"
        )
    }
}
