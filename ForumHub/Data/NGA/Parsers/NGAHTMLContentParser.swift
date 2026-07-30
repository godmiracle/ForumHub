import Foundation

/// 只处理 `postcontent<floor>` 内部 HTML；DOM 细节不会进入共享领域模型。
enum NGAHTMLContentParser {
    static func parse(_ html: String, sourceURL: URL? = nil) -> ForumPostDocument {
        let semantic = NGABBCodeContentParser.parse(html, origin: .ngaWeb, sourceURL: sourceURL)
        let representation = ForumContentRepresentation(
            origin: .ngaWeb,
            rawMarkup: html,
            markupFormat: .html,
            sourceURL: sourceURL,
            parserVersion: 2
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
}
