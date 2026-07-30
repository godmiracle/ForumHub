import Foundation

/// NGA BBCode 的来源适配器。它先保留语法 occurrence，再直接降低为共享语义块。
enum NGABBCodeContentParser {
    private enum SyntaxNode {
        case text(String)
        case image(String)
        case emoji(String)
        case quote(author: String, createdAt: String, body: String)
        case lineBreak
        case formattedText(String)
        case strikethrough(String)
        case link(label: String, destination: String)
        case video(source: String, poster: String?)
        case unsupported(String)
    }

    private struct LeadingReplyHeader {
        let quote: SyntaxNode
        let remainder: String
    }

    static func parse(
        _ markup: String,
        origin: ForumContentRepresentation.Origin = .ngaAPI,
        sourceURL: URL? = nil
    ) -> ForumPostDocument {
        let syntax = tokenize(normalizedSourceMarkup(markup))
        var diagnostics: [ForumContentDiagnostic] = []
        var blocks: [ForumContentBlock] = []
        var pendingInlineNodes: [ForumInlineNode] = []
        var pendingHasFormatting = false

        func appendBlock(_ content: ForumContentBlock.Content) {
            let occurrence = blocks.count
            blocks.append(ForumContentBlock(
                id: occurrence,
                content: content,
                provenance: .init(representationIndex: 0, occurrencePath: [occurrence])
            ))
        }

        func flushPendingInlineNodes() {
            if case let .text(text)? = pendingInlineNodes.first {
                pendingInlineNodes[0] = .text(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if case let .text(text)? = pendingInlineNodes.last {
                pendingInlineNodes[pendingInlineNodes.count - 1] = .text(
                    text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            pendingInlineNodes.removeAll { node in
                if case let .text(text) = node { return text.isEmpty }
                return false
            }
            guard !pendingInlineNodes.isEmpty else {
                pendingHasFormatting = false
                return
            }

            if pendingHasFormatting {
                appendBlock(.inline(pendingInlineNodes))
            } else {
                let text = pendingInlineNodes.compactMap { node -> String? in
                    if case let .text(value) = node { return value }
                    return nil
                }.joined()
                if !text.isEmpty { appendBlock(.text(text)) }
            }
            pendingInlineNodes.removeAll(keepingCapacity: true)
            pendingHasFormatting = false
        }

        for node in syntax {
            switch node {
            case let .text(text), let .formattedText(text):
                pendingInlineNodes.append(.text(text))
                continue
            case let .strikethrough(text):
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    pendingInlineNodes.append(.strikethrough([.text(value)]))
                    pendingHasFormatting = true
                }
                continue
            case let .link(label, rawDestination):
                flushPendingInlineNodes()
                if let destination = NGARichContentURLResolver.resolve(rawDestination) {
                    appendBlock(.link(label: label, destination: destination))
                } else {
                    appendBlock(.unsupported(label))
                    diagnostics.append(.init(
                        code: .malformedMarkup,
                        severity: .warning,
                        safeMessage: "NGA 链接地址无法解析"
                    ))
                }
            case let .image(rawURL):
                flushPendingInlineNodes()
                if let url = NGAImageURLResolver.resolve(rawURL) {
                    appendBlock(.image(url))
                } else {
                    appendBlock(.unsupported("[图片] \(rawURL)"))
                    diagnostics.append(.init(
                        code: .malformedMarkup,
                        severity: .warning,
                        safeMessage: "NGA 图片地址无法解析"
                    ))
                }
            case let .video(rawSource, rawPoster):
                flushPendingInlineNodes()
                if let sourceURL = NGARichContentURLResolver.resolve(rawSource) {
                    let posterURL = rawPoster.flatMap { NGAImageURLResolver.resolve($0) }
                    appendBlock(.video(.init(sourceURL: sourceURL, posterURL: posterURL)))
                } else {
                    appendBlock(.unsupported("[视频] \(rawSource)"))
                    diagnostics.append(.init(
                        code: .malformedMarkup,
                        severity: .warning,
                        safeMessage: "NGA 视频地址无法解析"
                    ))
                }
            case let .emoji(rawMarkup):
                flushPendingInlineNodes()
                if let emoji = NGAForumEmojiResolver.resolve(markup: rawMarkup) {
                    appendBlock(.emoji(emoji))
                } else {
                    appendBlock(.unsupported(rawMarkup))
                    diagnostics.append(.init(
                        code: .unsupportedMarkup,
                        severity: .warning,
                        safeMessage: "NGA 表情类型暂不支持"
                    ))
                }
            case let .quote(author, createdAt, body):
                flushPendingInlineNodes()
                appendBlock(.quote(.init(
                    author: author.trimmingCharacters(in: .whitespacesAndNewlines),
                    createdAt: createdAt.trimmingCharacters(in: .whitespacesAndNewlines),
                    body: body.trimmingCharacters(in: .whitespacesAndNewlines)
                )))
            case .lineBreak:
                flushPendingInlineNodes()
            case let .unsupported(rawMarkup):
                flushPendingInlineNodes()
                appendBlock(.unsupported(rawMarkup))
                diagnostics.append(.init(
                    code: .unsupportedMarkup,
                    severity: .warning,
                    safeMessage: "NGA 正文含未支持标记"
                ))
            }
        }
        flushPendingInlineNodes()

        if blocks.isEmpty {
            diagnostics.append(.init(
                code: .emptyContent,
                severity: .error,
                safeMessage: "NGA 正文没有可显示节点"
            ))
        }
        let quality: ForumContentParseQuality = blocks.isEmpty
            ? .unusable
            : (diagnostics.isEmpty ? .valid : .degraded)
        let representation = ForumContentRepresentation(
            origin: origin,
            rawMarkup: markup,
            markupFormat: .ngaBBCode,
            sourceURL: sourceURL,
            parserVersion: 2
        )

        return ForumPostDocument(
            rawMarkup: markup,
            fallbackText: ForumContentProjector.plainText(from: blocks),
            markupFormat: .ngaBBCode,
            sourceURL: sourceURL,
            representations: [representation],
            blocks: blocks,
            diagnostics: diagnostics,
            quality: quality
        )
    }

    private static func tokenize(_ markup: String) -> [SyntaxNode] {
        if let replyHeader = leadingReplyHeader(in: markup) {
            return [replyHeader.quote] + tokenize(replyHeader.remainder)
        }

        var nodes: [SyntaxNode] = []
        var cursor = markup.startIndex
        while cursor < markup.endIndex {
            guard let openingBracket = markup[cursor...].firstIndex(of: "[") else {
                appendText(String(markup[cursor...]), to: &nodes)
                break
            }
            if cursor < openingBracket {
                appendText(String(markup[cursor..<openingBracket]), to: &nodes)
            }
            guard let token = token(at: openingBracket, in: markup) else {
                appendText("[", to: &nodes)
                cursor = markup.index(after: openingBracket)
                continue
            }
            nodes.append(contentsOf: token.nodes)
            cursor = token.endIndex
        }
        return nodes
    }

    private static func token(
        at openingBracket: String.Index,
        in markup: String
    ) -> (nodes: [SyntaxNode], endIndex: String.Index)? {
        guard let closingBracket = markup[openingBracket...].firstIndex(of: "]") else {
            return nil
        }
        let afterOpeningTag = markup.index(after: closingBracket)
        let rawHeader = String(markup[markup.index(after: openingBracket)..<closingBracket])
        let header = rawHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerHeader = header.lowercased()

        if lowerHeader == "br" {
            return ([.lineBreak], afterOpeningTag)
        }
        if lowerHeader.hasPrefix("s:"), header.split(separator: ":", maxSplits: 2).count == 3 {
            return ([.emoji(String(markup[openingBracket..<afterOpeningTag]))], afterOpeningTag)
        }
        if lowerHeader.hasPrefix("/") {
            return ([.unsupported(String(markup[openingBracket..<afterOpeningTag]))], afterOpeningTag)
        }

        let name = tagName(in: header)
        guard !name.isEmpty else { return nil }
        let closingTag = "[/\(name)]"
        guard let closingRange = markup.range(
            of: closingTag,
            options: [.caseInsensitive],
            range: afterOpeningTag..<markup.endIndex
        ) else {
            let rawOpeningTag = String(markup[openingBracket..<afterOpeningTag])
            return knownStandaloneTag(name)
                ? ([.unsupported(rawOpeningTag)], afterOpeningTag)
                : nil
        }

        let body = String(markup[afterOpeningTag..<closingRange.lowerBound])
        let rawToken = String(markup[openingBracket..<closingRange.upperBound])
        switch name.lowercased() {
        case "img":
            return ([.image(body)], closingRange.upperBound)
        case "url":
            return ([.link(
                label: body,
                destination: linkDestination(in: header) ?? body
            )], closingRange.upperBound)
        case "video":
            return ([.video(
                source: body,
                poster: attribute("poster", in: header)
            )], closingRange.upperBound)
        case "引用":
            return ([.quote(
                author: attribute("author", in: header) ?? "",
                createdAt: attribute("time", in: header) ?? "",
                body: body
            )], closingRange.upperBound)
        case "quote":
            return ([semanticQuote(from: body)], closingRange.upperBound)
        case "b", "i", "u", "color", "size":
            let nested = tokenize(body)
            return (nested.isEmpty ? [.formattedText(body)] : nested, closingRange.upperBound)
        case "del":
            return ([.strikethrough(body)], closingRange.upperBound)
        default:
            return ([.unsupported(rawToken)], closingRange.upperBound)
        }
    }

    private static func appendText(_ text: String, to nodes: inout [SyntaxNode]) {
        guard !text.isEmpty else { return }
        nodes.append(.text(text))
    }

    private static func tagName(in header: String) -> String {
        String(header.prefix { character in
            character != "=" && !character.isWhitespace
        })
    }

    private static func knownStandaloneTag(_ name: String) -> Bool {
        ["img", "url", "video", "引用", "quote", "b", "i", "u", "color", "size", "del"].contains(name.lowercased())
    }

    private static func attribute(_ name: String, in header: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)(?:^|\s)"# + escapedName + #"\s*=\s*\"([^\"]*)\""#
        ),
              let match = expression.firstMatch(
                in: header,
                range: NSRange(header.startIndex..<header.endIndex, in: header)
              ),
              let valueRange = Range(match.range(at: 1), in: header)
        else { return nil }
        return String(header[valueRange])
    }

    /// NGA 的旧回复目标头不一定包含外层 `[quote]`。这里只消费头部元数据，
    /// 当前楼层正文继续交给 tokenizer，确保其中的图片、表情和顺序不丢失。
    private static func leadingReplyHeader(in markup: String) -> LeadingReplyHeader? {
        var value = markup
        trimLeadingWhitespace(from: &value)
        _ = removePrefix("<b>", from: &value)
        guard removePrefix("Reply", from: &value) else { return nil }
        trimLeadingWhitespace(from: &value)

        if removePrefix("to", from: &value) {
            trimLeadingWhitespace(from: &value)
            if !removeLeadingReferenceTarget(from: &value) {
                guard removePrefix("Reply", from: &value) else { return nil }
            }
            trimLeadingWhitespace(from: &value)
        }

        guard removePrefix("Post by ", from: &value),
              let attribution = removeLeadingQuoteAttribution(from: &value)
        else { return nil }
        removeQuoteHeaderSuffix(from: &value)

        return LeadingReplyHeader(
            quote: .quote(
                author: attribution.author.cleanedForumText,
                createdAt: attribution.createdAt.cleanedForumText,
                body: ""
            ),
            remainder: value
        )
    }

    /// 解析 NGA API 返回的英文 quote 容器。引用目标（tid/pid）只用于定位头部，
    /// 不进入共享领域模型；作者、时间和正文按标记边界消费，避免为每种组合追加整段正则。
    private static func semanticQuote(from sourceBody: String) -> SyntaxNode {
        var headerAndBody = sourceBody
        _ = removeLeadingReferenceTarget(from: &headerAndBody)
        trimLeadingWhitespace(from: &headerAndBody)
        _ = removePrefix("<b>", from: &headerAndBody)
        trimLeadingWhitespace(from: &headerAndBody)

        guard removePrefix("Post by ", from: &headerAndBody),
              let attribution = removeLeadingQuoteAttribution(from: &headerAndBody)
        else {
            return .quote(author: "", createdAt: "", body: normalizedQuoteBody(sourceBody))
        }
        removeQuoteHeaderSuffix(from: &headerAndBody)

        return .quote(
            author: attribution.author.cleanedForumText,
            createdAt: attribution.createdAt.cleanedForumText,
            body: normalizedQuoteBody(headerAndBody)
        )
    }

    @discardableResult
    private static func removeLeadingReferenceTarget(from value: inout String) -> Bool {
        guard value.first == "[",
              let headerEnd = value.firstIndex(of: "]")
        else { return false }
        let headerStart = value.index(after: value.startIndex)
        let header = String(value[headerStart..<headerEnd])
        let name = tagName(in: header).lowercased()
        guard name == "tid" || name == "pid",
              let closingRange = value.range(
                of: "[/\(name)]",
                options: [.caseInsensitive],
                range: value.index(after: headerEnd)..<value.endIndex
              )
        else { return false }
        value.removeSubrange(value.startIndex..<closingRange.upperBound)
        return true
    }

    private static func removeLeadingQuoteAttribution(
        from value: inout String
    ) -> (author: String, createdAt: String)? {
        guard let author = removeLeadingQuoteAuthor(from: &value) else { return nil }
        trimLeadingWhitespace(from: &value)
        guard value.first == "(",
              let closingParenthesis = value.firstIndex(of: ")")
        else { return nil }

        let timeStart = value.index(after: value.startIndex)
        let createdAt = String(value[timeStart..<closingParenthesis])
        value.removeSubrange(value.startIndex...closingParenthesis)
        return (author, createdAt)
    }

    private static func removeLeadingQuoteAuthor(from value: inout String) -> String? {
        if value.lowercased().hasPrefix("[uid="),
           let headerEnd = value.firstIndex(of: "]"),
           let closingRange = value.range(
            of: "[/uid]",
            options: [.caseInsensitive],
            range: value.index(after: headerEnd)..<value.endIndex
           ) {
            let authorStart = value.index(after: headerEnd)
            let author = String(value[authorStart..<closingRange.lowerBound])
            value.removeSubrange(value.startIndex..<closingRange.upperBound)
            return author
        }

        guard let timeSeparator = value.range(of: " (") else { return nil }
        let author = String(value[..<timeSeparator.lowerBound])
        value.removeSubrange(value.startIndex..<timeSeparator.upperBound)
        value.insert("(", at: value.startIndex)
        return author
    }

    private static func removeLeadingBreaks(from value: inout String) {
        while true {
            trimLeadingWhitespace(from: &value)
            guard removePrefix("[br]", from: &value) else { return }
        }
    }

    private static func removeQuoteHeaderSuffix(from value: inout String) {
        trimLeadingWhitespace(from: &value)
        if value.first == ":" {
            value.removeFirst()
        }
        trimLeadingWhitespace(from: &value)
        _ = removePrefix("</b>", from: &value)
        removeLeadingBreaks(from: &value)
    }

    private static func removePrefix(_ prefix: String, from value: inout String) -> Bool {
        guard value.range(of: prefix, options: [.anchored, .caseInsensitive]) != nil else {
            return false
        }
        value.removeFirst(prefix.count)
        return true
    }

    private static func trimLeadingWhitespace(from value: inout String) {
        guard let firstContent = value.firstIndex(where: { !$0.isWhitespace }) else {
            value.removeAll()
            return
        }
        value.removeSubrange(value.startIndex..<firstContent)
    }

    private static func normalizedQuoteBody(_ body: String) -> String {
        body.replacingOccurrences(
            of: #"(?i)\[br\]"#,
            with: "\n",
            options: .regularExpression
        )
        .cleanedForumText
    }

    private static func normalizedSourceMarkup(_ markup: String) -> String {
        var value = normalizeLegacyQuotes(in: markup)
        value = NGAEmbeddedHTMLNormalizer.normalize(value)
        value = value.decodedHTMLEntities
        value = value.replacingOccurrences(
            of: #"(?i)\[图片\]\s*((?:https?:)?//[^\s\[]+|\.?/[^\s\[]+)"#,
            with: "[img]$1[/img]",
            options: .regularExpression
        )
        return value
    }

    private static func normalizeLegacyQuotes(in markup: String) -> String {
        let patterns = [
            #"\[quote\]\[pid=\d+(?:,\d+,\d+)?\]Reply\[/pid\]\s*(?:<b>)?Post by \[uid=\d+\](.*?)\[/uid\]\s*\((.*?)\):(?:</b>)?(?:<br\s*/?>|\n)*(.*?)(?:\[/quote\])"#,
            #"\[quote\]\[pid=\d+(?:,\d+,\d+)?\]Reply\[/pid\]\s*(?:<b>)?Post by (.*?)\s*\((.*?)\):(?:</b>)?(?:<br\s*/?>|\n)*(.*?)(?:\[/quote\])"#
        ]
        var value = markup
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else { continue }
            let matches = expression.matches(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
            ).reversed()
            for match in matches {
                guard let fullRange = Range(match.range(at: 0), in: value),
                      let authorRange = Range(match.range(at: 1), in: value),
                      let timeRange = Range(match.range(at: 2), in: value),
                      let bodyRange = Range(match.range(at: 3), in: value)
                else { continue }
                let author = String(value[authorRange]).cleanedForumText
                let time = String(value[timeRange]).cleanedForumText
                let body = String(value[bodyRange]).cleanedForumText
                value.replaceSubrange(
                    fullRange,
                    with: "[引用 author=\"\(author)\" time=\"\(time)\"]\(body)[/引用]"
                )
            }
        }
        return value
    }

    private static func capture(_ index: Int, _ match: NSTextCheckingResult, _ text: String) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func linkDestination(in header: String) -> String? {
        guard let separator = header.firstIndex(of: "=") else { return nil }
        let value = header[header.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

/// NGA 正文同时可能包含 BBCode 与浏览器 HTML。这里以容错扫描方式把 HTML 降低成
/// 已有 BBCode 语义接缝：不执行事件或脚本，不依赖站点 class，并让未知元素透明保留子内容。
private enum NGAEmbeddedHTMLNormalizer {
    private struct Tag {
        let name: String
        let header: String
        let isClosing: Bool
        let isSelfClosing: Bool
    }

    private struct MediaContext {
        let type: String
        var sourceURL: URL?
        let posterURL: URL?
    }

    private static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "dd", "details", "dialog",
        "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
        "h1", "h2", "h3", "h4", "h5", "h6", "header", "main", "nav", "ol", "p",
        "pre", "section", "summary", "table", "tbody", "tfoot", "thead", "tr", "ul"
    ]
    private static let suppressedTags: Set<String> = [
        "canvas", "noscript", "script", "style", "template"
    ]

    static func normalize(_ markup: String) -> String {
        var output = ""
        var cursor = markup.startIndex
        var anchorStack: [Bool] = []
        var mediaStack: [MediaContext] = []

        while cursor < markup.endIndex {
            guard let tagStart = markup[cursor...].firstIndex(of: "<") else {
                if mediaStack.isEmpty {
                    output.append(contentsOf: markup[cursor...])
                }
                break
            }
            if mediaStack.isEmpty {
                output.append(contentsOf: markup[cursor..<tagStart])
            }

            if markup[tagStart...].hasPrefix("<!--") {
                guard let commentEnd = markup.range(
                    of: "-->",
                    range: markup.index(tagStart, offsetBy: 4)..<markup.endIndex
                ) else {
                    break
                }
                cursor = commentEnd.upperBound
                continue
            }

            guard let end = tagEnd(in: markup, from: tagStart),
                  let tag = parseTag(String(markup[markup.index(after: tagStart)..<end]))
            else {
                if mediaStack.isEmpty {
                    output.append("<")
                }
                cursor = markup.index(after: tagStart)
                continue
            }
            let afterTag = markup.index(after: end)

            if !tag.isClosing, suppressedTags.contains(tag.name) {
                cursor = tag.isSelfClosing
                    ? afterTag
                    : endOfSuppressedElement(named: tag.name, in: markup, after: afterTag)
                continue
            }

            switch tag.name {
            case "a":
                if tag.isClosing {
                    if anchorStack.popLast() == true {
                        output.append("[/url]")
                    }
                } else {
                    let destination: URL?
                    if let rawDestination = attribute("href", in: tag.header) {
                        destination = NGARichContentURLResolver.resolve(rawDestination)
                    } else {
                        destination = nil
                    }
                    let opensSemanticLink = destination != nil && mediaStack.isEmpty
                    if let destination, opensSemanticLink {
                        output.append("[url=\(destination.absoluteString)]")
                    }
                    if !tag.isSelfClosing {
                        anchorStack.append(opensSemanticLink)
                    }
                }

            case "img":
                guard !tag.isClosing, mediaStack.isEmpty,
                      let rawSource = firstAttribute(
                        ["data-src", "data-original", "data-lazy-src", "src"],
                        in: tag.header
                      ),
                      let source = NGAImageURLResolver.resolve(rawSource)
                else { break }
                output.append("[img]\(source.absoluteString)[/img]")

            case "video", "audio":
                if tag.isClosing {
                    if let index = mediaStack.lastIndex(where: { $0.type == tag.name }) {
                        let media = mediaStack[index]
                        mediaStack.removeSubrange(index...)
                        appendMedia(media, to: &output)
                    }
                } else {
                    let media = mediaContext(for: tag)
                    if tag.isSelfClosing {
                        appendMedia(media, to: &output)
                    } else {
                        mediaStack.append(media)
                    }
                }

            case "source":
                guard !tag.isClosing, !mediaStack.isEmpty,
                      let rawSource = firstAttribute(["src", "data-src"], in: tag.header),
                      let source = NGARichContentURLResolver.resolve(rawSource)
                else { break }
                if mediaStack[mediaStack.count - 1].sourceURL == nil {
                    mediaStack[mediaStack.count - 1].sourceURL = source
                }

            case "iframe":
                guard !tag.isClosing,
                      let rawSource = firstAttribute(["src", "data-src"], in: tag.header),
                      let source = NGARichContentURLResolver.resolve(rawSource)
                else { break }
                output.append("[url=\(source.absoluteString)]打开嵌入内容[/url][br]")

            case "br", "hr":
                if !tag.isClosing {
                    output.append("[br]")
                }

            case "li":
                output.append(tag.isClosing ? "[br]" : "[br]• ")

            case "td", "th":
                if tag.isClosing {
                    output.append("　")
                }

            case "del", "s", "strike":
                output.append(tag.isClosing ? "[/del]" : "[del]")

            default:
                if blockTags.contains(tag.name) {
                    output.append("[br]")
                }
                // 行内样式与未知自定义元素都只去掉标签外壳，子内容按原顺序继续解析。
            }

            cursor = afterTag
        }

        while let openedSemanticLink = anchorStack.popLast() {
            if openedSemanticLink {
                output.append("[/url]")
            }
        }
        for media in mediaStack {
            appendMedia(media, to: &output)
        }
        return output
    }

    private static func mediaContext(for tag: Tag) -> MediaContext {
        let sourceURL = firstAttribute(["src", "data-src"], in: tag.header)
            .flatMap { NGARichContentURLResolver.resolve($0) }
        let posterURL = firstAttribute(["poster", "data-poster"], in: tag.header)
            .flatMap { NGAImageURLResolver.resolve($0) }
        return MediaContext(type: tag.name, sourceURL: sourceURL, posterURL: posterURL)
    }

    private static func appendMedia(_ media: MediaContext, to output: inout String) {
        guard let sourceURL = media.sourceURL else { return }
        if media.type == "video" {
            let posterAttribute = media.posterURL.map { #" poster="\#($0.absoluteString)""# } ?? ""
            output.append("[video\(posterAttribute)]\(sourceURL.absoluteString)[/video][br]")
        } else {
            output.append(mediaLink(url: sourceURL, type: media.type))
        }
    }

    private static func mediaLink(url: URL, type: String) -> String {
        let label = type == "audio" ? "播放音频" : "播放视频"
        return "[url=\(url.absoluteString)]\(label)[/url][br]"
    }

    private static func endOfSuppressedElement(
        named name: String,
        in markup: String,
        after openingTag: String.Index
    ) -> String.Index {
        guard let closingStart = markup.range(
            of: "</\(name)",
            options: [.caseInsensitive],
            range: openingTag..<markup.endIndex
        )?.lowerBound,
              let closingEnd = tagEnd(in: markup, from: closingStart)
        else {
            return markup.endIndex
        }
        return markup.index(after: closingEnd)
    }

    private static func tagEnd(in markup: String, from start: String.Index) -> String.Index? {
        var cursor = markup.index(after: start)
        var quote: Character?
        while cursor < markup.endIndex {
            let character = markup[cursor]
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return cursor
            }
            cursor = markup.index(after: cursor)
        }
        return nil
    }

    private static func parseTag(_ rawHeader: String) -> Tag? {
        let header = rawHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !header.isEmpty else { return nil }
        if header.hasPrefix("!") || header.hasPrefix("?") {
            return Tag(name: "", header: header, isClosing: false, isSelfClosing: true)
        }

        var cursor = header.startIndex
        let isClosing = header[cursor] == "/"
        if isClosing {
            cursor = header.index(after: cursor)
        }
        guard cursor < header.endIndex, header[cursor].isLetter else { return nil }
        let nameStart = cursor
        while cursor < header.endIndex {
            let character = header[cursor]
            guard character.isLetter || character.isNumber || character == "-" || character == ":"
            else { break }
            cursor = header.index(after: cursor)
        }
        let name = header[nameStart..<cursor].lowercased()
        return Tag(
            name: name,
            header: header,
            isClosing: isClosing,
            isSelfClosing: header.hasSuffix("/") || ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"].contains(name)
        )
    }

    private static func firstAttribute(_ names: [String], in header: String) -> String? {
        for name in names {
            if let value = attribute(name, in: header), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func attribute(_ requestedName: String, in header: String) -> String? {
        var cursor = header.startIndex
        if cursor < header.endIndex, header[cursor] == "/" {
            cursor = header.index(after: cursor)
        }
        while cursor < header.endIndex, !header[cursor].isWhitespace {
            cursor = header.index(after: cursor)
        }

        while cursor < header.endIndex {
            while cursor < header.endIndex,
                  header[cursor].isWhitespace || header[cursor] == "/" {
                cursor = header.index(after: cursor)
            }
            guard cursor < header.endIndex else { break }
            let nameStart = cursor
            while cursor < header.endIndex {
                let character = header[cursor]
                guard character.isLetter || character.isNumber || character == "-" || character == "_" || character == ":"
                else { break }
                cursor = header.index(after: cursor)
            }
            guard nameStart < cursor else {
                cursor = header.index(after: cursor)
                continue
            }
            let name = header[nameStart..<cursor].lowercased()
            while cursor < header.endIndex, header[cursor].isWhitespace {
                cursor = header.index(after: cursor)
            }
            guard cursor < header.endIndex, header[cursor] == "=" else {
                continue
            }
            cursor = header.index(after: cursor)
            while cursor < header.endIndex, header[cursor].isWhitespace {
                cursor = header.index(after: cursor)
            }
            guard cursor < header.endIndex else { return nil }

            let value: String
            if header[cursor] == "\"" || header[cursor] == "'" {
                let quote = header[cursor]
                cursor = header.index(after: cursor)
                let valueStart = cursor
                while cursor < header.endIndex, header[cursor] != quote {
                    cursor = header.index(after: cursor)
                }
                value = String(header[valueStart..<cursor])
                if cursor < header.endIndex {
                    cursor = header.index(after: cursor)
                }
            } else {
                let valueStart = cursor
                while cursor < header.endIndex,
                      !header[cursor].isWhitespace {
                    cursor = header.index(after: cursor)
                }
                value = String(header[valueStart..<cursor])
            }

            if name == requestedName.lowercased() {
                return value.decodedHTMLEntities
            }
        }
        return nil
    }
}

private enum NGARichContentURLResolver {
    static func resolve(_ rawValue: String) -> URL? {
        var value = rawValue
            .decodedHTMLEntities
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\/", with: "/")
        if value.hasPrefix("//") {
            value = "https:" + value
        }
        guard !value.contains("["),
              !value.contains("]"),
              let forumBaseURL = URL(string: "https://bbs.nga.cn/"),
              let url = URL(string: value, relativeTo: forumBaseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }
}
