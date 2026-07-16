import Foundation

enum NGAThreadSourceError: LocalizedError, Equatable {
    case contentUnavailable

    var errorDescription: String? {
        "NGA API 与网页都没有返回可显示的帖子正文。"
    }
}

extension NGAThreadSourceError: ForumErrorConvertible {
    var forumError: ForumError { .sourceUnavailable }
}

/// NGA 帖子详情的来源选择只依据解析质量，不比较或拼接正文文本。
enum NGAThreadContentSourcePolicy {
    typealias WebLoader = () async throws -> ForumThread?

    static func resolve(
        apiThread: ForumThread,
        requestedPage: Int = 1,
        fetchWeb: WebLoader
    ) async throws -> ForumThread {
        guard quality(of: apiThread, requestedPage: requestedPage) == .unusable else {
            return apiThread
        }

        guard let webThread = try await fetchWeb() else {
            throw NGAThreadSourceError.contentUnavailable
        }
        return try NGAThreadWebFallbackAssembler.assemble(
            apiThread: apiThread,
            webThread: webThread,
            requestedPage: requestedPage
        )
    }

    static func quality(
        of thread: ForumThread,
        requestedPage: Int = 1
    ) -> ForumContentParseQuality {
        let requiredDocuments = requestedPage > 1
            ? thread.replies.map(\.contentDocument)
            : [thread.contentDocument] + thread.replies.map(\.contentDocument)
        return requiredDocuments
            .map(\.quality)
            .min() ?? .unusable
    }
}

/// Web 只替换同一 API 楼层的整份语义文档；身份、元数据、成员与顺序均由 API 决定。
enum NGAThreadWebFallbackAssembler {
    static func assemble(
        apiThread: ForumThread,
        webThread: ForumThread,
        requestedPage: Int = 1
    ) throws -> ForumThread {
        let webRepliesByFloor = Dictionary(
            webThread.replies.compactMap { reply in
                reply.floorNumber.map { ($0, reply) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let webOnlyFloors = Set(webRepliesByFloor.keys).subtracting(
            apiThread.replies.compactMap(\.floorNumber)
        )

        let mainDocument: ForumPostDocument
        if requestedPage == 1, apiThread.contentDocument.quality == .unusable {
            guard webThread.contentDocument.quality != .unusable else {
                throw NGAThreadSourceError.contentUnavailable
            }
            mainDocument = selectingWeb(
                api: apiThread.contentDocument,
                web: webThread.contentDocument,
                ignoredWebOnlyFloorCount: webOnlyFloors.count
            )
        } else {
            if requestedPage == 1 {
                mainDocument = retainingAPIObservation(
                    api: apiThread.contentDocument,
                    web: webThread.contentDocument,
                    ignoredWebOnlyFloorCount: webOnlyFloors.count
                )
            } else {
                mainDocument = webOnlyFloors.isEmpty
                    ? apiThread.contentDocument
                    : appendingWebOnlyFloorDiagnostic(to: apiThread.contentDocument)
            }
        }

        let replies = try apiThread.replies.map { apiReply -> Reply in
            guard let floor = apiReply.floorNumber,
                  let webReply = webRepliesByFloor[floor]
            else {
                if apiReply.contentDocument.quality != .unusable { return apiReply }
                throw NGAThreadSourceError.contentUnavailable
            }

            if apiReply.contentDocument.quality != .unusable {
                return apiReply.replacingContent(with: retainingAPIObservation(
                    api: apiReply.contentDocument,
                    web: webReply.contentDocument,
                    ignoredWebOnlyFloorCount: 0
                ))
            }
            guard webReply.contentDocument.quality != .unusable else {
                throw NGAThreadSourceError.contentUnavailable
            }
            return apiReply.replacingContent(with: selectingWeb(
                api: apiReply.contentDocument,
                web: webReply.contentDocument,
                ignoredWebOnlyFloorCount: 0
            ))
        }

        return ForumThread(
            id: apiThread.id,
            title: apiThread.title,
            summary: mainDocument.bodyText,
            author: apiThread.author,
            authorAvatarURL: apiThread.authorAvatarURL,
            createdAt: apiThread.createdAt,
            lastReplyAt: apiThread.lastReplyAt,
            replyCount: apiThread.replyCount,
            viewCount: apiThread.viewCount,
            body: mainDocument.bodyText,
            contentDocument: mainDocument,
            replies: replies,
            source: apiThread.source,
            channelID: apiThread.channelID,
            channelTitle: apiThread.channelTitle,
            sourceMetadata: apiThread.sourceMetadata
        )
    }

    private static func selectingWeb(
        api: ForumPostDocument,
        web: ForumPostDocument,
        ignoredWebOnlyFloorCount: Int
    ) -> ForumPostDocument {
        var diagnostics = api.diagnostics + web.diagnostics
        if ignoredWebOnlyFloorCount > 0 {
            diagnostics.append(.init(
                code: .webOnlyFloorIgnored,
                severity: .warning,
                safeMessage: "网页包含 API 未确认的额外楼层，已忽略"
            ))
        }
        let representationOffset = api.representations.count
        let selectedBlocks = web.blocks.map { block in
            let provenance = block.provenance.map {
                ForumContentProvenance(
                    representationIndex: $0.representationIndex + representationOffset,
                    occurrencePath: $0.occurrencePath
                )
            }
            return ForumContentBlock(
                id: block.id,
                content: block.content,
                provenance: provenance
            )
        }
        return ForumPostDocument(
            rawMarkup: web.rawMarkup,
            fallbackText: web.bodyText,
            markupFormat: web.markupFormat,
            sourceURL: web.sourceURL,
            representations: api.representations + web.representations,
            blocks: selectedBlocks,
            diagnostics: diagnostics,
            quality: web.quality,
            schemaVersion: max(api.schemaVersion, web.schemaVersion)
        )
    }

    private static func retainingAPIObservation(
        api: ForumPostDocument,
        web: ForumPostDocument,
        ignoredWebOnlyFloorCount: Int
    ) -> ForumPostDocument {
        var diagnostics = api.diagnostics + web.diagnostics
        if api.quality == .valid,
           web.quality == .valid,
           api.blocks != web.blocks {
            diagnostics.append(.init(
                code: .sourceConflict,
                severity: .information,
                safeMessage: "API 与网页语义内容不同，已保留 API 内容"
            ))
        }
        if ignoredWebOnlyFloorCount > 0 {
            diagnostics.append(.init(
                code: .webOnlyFloorIgnored,
                severity: .warning,
                safeMessage: "网页包含 API 未确认的额外楼层，已忽略"
            ))
        }
        return ForumPostDocument(
            rawMarkup: api.rawMarkup,
            fallbackText: api.bodyText,
            markupFormat: api.markupFormat,
            sourceURL: api.sourceURL,
            representations: api.representations + web.representations,
            blocks: api.blocks,
            diagnostics: diagnostics,
            quality: api.quality,
            schemaVersion: max(api.schemaVersion, web.schemaVersion)
        )
    }

    private static func appendingWebOnlyFloorDiagnostic(
        to document: ForumPostDocument
    ) -> ForumPostDocument {
        ForumPostDocument(
            rawMarkup: document.rawMarkup,
            fallbackText: document.bodyText,
            markupFormat: document.markupFormat,
            sourceURL: document.sourceURL,
            representations: document.representations,
            blocks: document.blocks,
            diagnostics: document.diagnostics + [.init(
                code: .webOnlyFloorIgnored,
                severity: .warning,
                safeMessage: "网页包含 API 未确认的额外楼层，已忽略"
            )],
            quality: document.quality,
            schemaVersion: document.schemaVersion
        )
    }
}
