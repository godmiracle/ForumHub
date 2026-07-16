import Foundation

enum ForumContentParseQuality: Int, Comparable, Equatable {
    case unusable
    case degraded
    case valid

    static func < (lhs: ForumContentParseQuality, rhs: ForumContentParseQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ForumContentRepresentation: Equatable {
    enum Origin: Equatable {
        case local
        case ngaAPI
        case ngaWeb
        case remote(ForumSource)
    }

    let origin: Origin
    let rawMarkup: String
    let markupFormat: ForumPostDocument.MarkupFormat
    let sourceURL: URL?
    let parserVersion: Int
}

struct ForumContentDiagnostic: Equatable {
    enum Code: String, Equatable {
        case emptyContent
        case malformedMarkup
        case unsupportedMarkup
        case sourceConflict
        case webOnlyFloorIgnored
        case sourceUnavailable
    }

    enum Severity: Equatable {
        case information
        case warning
        case error
    }

    let code: Code
    let severity: Severity
    /// 仅允许固定、非用户输入的调试说明；不得保存原始正文或凭证。
    let safeMessage: String
}

struct ForumContentProvenance: Equatable {
    let representationIndex: Int
    let occurrencePath: [Int]
}

struct ForumContentResource: Equatable {
    enum Kind: Equatable {
        case image
        case emoji
        case attachment
    }

    let url: URL
    let kind: Kind
    let accessibilityLabel: String?
}

enum ForumInlineNode: Equatable {
    case text(String)
    case link(label: String, destination: URL)
    case emphasis([ForumInlineNode])
    case strikethrough([ForumInlineNode])
    case resource(ForumContentResource)
    case unsupported(String)
}

/// 帖子正文的语义文档。原始表示用于追溯，`blocks` 才是阅读、分享和快照的权威输入。
struct ForumPostDocument: Equatable {
    enum MarkupFormat: Equatable {
        case plainText
        case ngaBBCode
        case html
        case markdown
    }

    let rawMarkup: String
    let markupFormat: MarkupFormat
    let sourceURL: URL?
    let representations: [ForumContentRepresentation]
    let blocks: [ForumContentBlock]
    let diagnostics: [ForumContentDiagnostic]
    let quality: ForumContentParseQuality
    let schemaVersion: Int

    init(
        rawMarkup: String,
        fallbackText: String,
        markupFormat: MarkupFormat,
        sourceURL: URL? = nil,
        representations: [ForumContentRepresentation]? = nil,
        blocks: [ForumContentBlock]? = nil,
        diagnostics: [ForumContentDiagnostic] = [],
        quality: ForumContentParseQuality? = nil,
        schemaVersion: Int = 1
    ) {
        self.rawMarkup = rawMarkup
        self.markupFormat = markupFormat
        self.sourceURL = sourceURL
        self.representations = representations ?? [
            ForumContentRepresentation(
                origin: .local,
                rawMarkup: rawMarkup,
                markupFormat: markupFormat,
                sourceURL: sourceURL,
                parserVersion: 1
            )
        ]
        let visibleFallback = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.blocks = blocks ?? (visibleFallback.isEmpty ? [] : [
            ForumContentBlock(id: 0, content: .text(visibleFallback))
        ])
        self.diagnostics = diagnostics
        self.quality = quality ?? (visibleFallback.isEmpty ? .unusable : .valid)
        self.schemaVersion = schemaVersion
    }

    static func plainText(_ text: String) -> ForumPostDocument {
        ForumPostDocument(rawMarkup: text, fallbackText: text, markupFormat: .plainText)
    }

    var bodyText: String {
        ForumContentProjector.plainText(from: blocks)
    }

    var imageURLs: [URL] {
        ForumContentProjector.imageURLs(from: blocks)
    }
}

struct ForumContentBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case paragraph
        case image
        case emoji
        case quote
        case unsupported
    }

    enum Content: Equatable {
        case text(String)
        case inline([ForumInlineNode])
        case link(label: String, destination: URL)
        case image(URL)
        case emoji(ForumContentEmoji)
        case quote(ForumQuoteBlock)
        case unsupported(String)
    }

    let id: Int
    let content: Content
    var provenance: ForumContentProvenance? = nil

    var kind: Kind {
        switch content {
        case .text, .inline, .link: .paragraph
        case .image: .image
        case .emoji: .emoji
        case .quote: .quote
        case .unsupported: .unsupported
        }
    }
}

enum ForumContentProjector {
    static func plainText(from blocks: [ForumContentBlock]) -> String {
        blocks.compactMap { block -> String? in
            switch block.content {
            case let .text(text): return text
            case let .inline(nodes): return plainText(from: nodes)
            case let .link(label, destination): return "\(label) (\(destination.absoluteString))"
            case let .image(url): return "[图片] \(url.absoluteString)"
            case let .emoji(emoji): return "[表情] \(emoji.name)"
            case let .quote(quote):
                return "[引用 author=\"\(quote.author)\" time=\"\(quote.createdAt)\"]\(quote.body)[/引用]"
            case let .unsupported(fallback): return fallback
            }
        }
        .joined(separator: "\n")
    }

    private static func plainText(from nodes: [ForumInlineNode]) -> String {
        nodes.map { node in
            switch node {
            case let .text(text), let .unsupported(text):
                return text
            case let .link(label, _):
                return label
            case let .emphasis(children), let .strikethrough(children):
                return plainText(from: children)
            case let .resource(resource):
                return resource.accessibilityLabel ?? ""
            }
        }
        .joined()
    }

    static func imageURLs(from blocks: [ForumContentBlock]) -> [URL] {
        blocks.compactMap { block in
            switch block.content {
            case let .image(url): url
            default: nil
            }
        }
    }

    static func accessibilityText(from blocks: [ForumContentBlock]) -> String {
        plainText(from: blocks)
    }

    static func contentSignature(from blocks: [ForumContentBlock]) -> String {
        plainText(from: blocks)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

struct ForumContentEmoji: Equatable {
    let name: String
    let url: URL
}

struct ForumQuoteBlock: Equatable {
    let author: String
    let createdAt: String
    let body: String
}
