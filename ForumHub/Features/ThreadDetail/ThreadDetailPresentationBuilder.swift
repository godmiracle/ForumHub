import Foundation

struct ThreadDetailReplyTreeNode: Identifiable, Equatable {
    let reply: Reply
    let children: [ThreadDetailReplyTreeNode]

    var id: Int { reply.id }
}

struct ThreadDetailFlattenedReply: Equatable {
    let reply: Reply
    let depth: Int
    let visualDepth: Int
}

enum ThreadDetailReplyForestBuilder {
    static let maximumVisualDepth = 3

    static func build(from replies: [Reply]) -> [ThreadDetailReplyTreeNode] {
        let repliesByID = Dictionary(uniqueKeysWithValues: replies.map { ($0.id, $0) })
        var childrenByParentID: [Int: [Int]] = [:]
        var rootIDs: [Int] = []

        for reply in replies {
            if let parentID = reply.conversation?.parentReplyID,
               parentID != reply.id,
               repliesByID[parentID] != nil {
                childrenByParentID[parentID, default: []].append(reply.id)
            } else {
                rootIDs.append(reply.id)
            }
        }

        func node(for id: Int, ancestors: Set<Int>) -> ThreadDetailReplyTreeNode? {
            guard let reply = repliesByID[id], !ancestors.contains(id) else { return nil }
            let nextAncestors = ancestors.union([id])
            let children = childrenByParentID[id, default: []].compactMap {
                node(for: $0, ancestors: nextAncestors)
            }
            return ThreadDetailReplyTreeNode(reply: reply, children: children)
        }

        return rootIDs.compactMap { node(for: $0, ancestors: []) }
    }

    static func flatten(_ roots: [ThreadDetailReplyTreeNode]) -> [ThreadDetailFlattenedReply] {
        var result: [ThreadDetailFlattenedReply] = []

        func append(_ node: ThreadDetailReplyTreeNode, depth: Int) {
            result.append(ThreadDetailFlattenedReply(
                reply: node.reply,
                depth: depth,
                visualDepth: min(depth, maximumVisualDepth)
            ))
            node.children.forEach { append($0, depth: depth + 1) }
        }

        roots.forEach { append($0, depth: 0) }
        return result
    }
}

enum ThreadDetailPresentationBuilder {
    static func displayedReplies(
        thread: ForumThread,
        showsOnlyThreadAuthor: Bool,
        showsRepliesInReverseOrder: Bool,
        source: ForumSource,
        usesThreadedV2EXPresentation: Bool = false,
        isBlocked: (ForumSource, String) -> Bool
    ) -> [Reply] {
        let sourceReplies = showsOnlyThreadAuthor ? thread.authorReplies : thread.replies
        let visibleReplies = sourceReplies.filter { !isBlocked(source, $0.author) }

        if source == .v2ex, usesThreadedV2EXPresentation, !showsOnlyThreadAuthor {
            let roots = ThreadDetailReplyForestBuilder.build(from: visibleReplies)
            let orderedRoots = showsRepliesInReverseOrder ? Array(roots.reversed()) : roots
            return ThreadDetailReplyForestBuilder.flatten(orderedRoots).map(\.reply)
        }

        return showsRepliesInReverseOrder ? Array(visibleReplies.reversed()) : visibleReplies
    }

    static func displayedReplyEntries(
        displayedReplies: [Reply],
        allReplies: [Reply],
        pageStartReplyIndices: [Int: Int],
        supportsDirectPagination: Bool,
        pageSize: Int,
        prefetchReplyDistance: Int,
        usesThreadedPresentation: Bool = false
    ) -> [ThreadDetailDisplayedReplyEntry] {
        let sortedPageStarts = pageStartReplyIndices.sorted { $0.value < $1.value }
        let replyIndices = Dictionary(uniqueKeysWithValues: allReplies.enumerated().map { ($1.id, $0) })
        let prefetchStartIndex = max(displayedReplies.count - prefetchReplyDistance, 0)
        var firstVisibleReplyIDByPage: [Int: Int] = [:]
        let flattenedReplies = usesThreadedPresentation
            ? ThreadDetailReplyForestBuilder.flatten(
                ThreadDetailReplyForestBuilder.build(from: displayedReplies)
            )
            : displayedReplies.map {
                ThreadDetailFlattenedReply(reply: $0, depth: 0, visualDepth: 0)
            }
        let hierarchyByReplyID = Dictionary(
            uniqueKeysWithValues: flattenedReplies.map { ($0.reply.id, $0) }
        )

        return displayedReplies.enumerated().map { visualIndex, reply in
            let replyIndex = replyIndices[reply.id]
            let page = resolvedPage(forReplyIndex: replyIndex, pageStarts: sortedPageStarts)
            let showsPageAnchor = firstVisibleReplyIDByPage[page] == nil
            if showsPageAnchor { firstVisibleReplyIDByPage[page] = reply.id }
            let hierarchy = hierarchyByReplyID[reply.id]
                ?? ThreadDetailFlattenedReply(reply: reply, depth: 0, visualDepth: 0)

            return ThreadDetailDisplayedReplyEntry(
                reply: reply,
                page: page,
                showsPageAnchor: showsPageAnchor,
                floorLabel: floorLabel(
                    replyIndex: replyIndex,
                    page: page,
                    floorNumber: reply.floorNumber,
                    pageStartReplyIndices: pageStartReplyIndices,
                    supportsDirectPagination: supportsDirectPagination,
                    pageSize: pageSize
                ),
                loadsNextPageWhenAppearing: visualIndex >= prefetchStartIndex,
                hierarchyDepth: hierarchy.depth,
                visualDepth: hierarchy.visualDepth,
                displayedContentDocument: displayedDocument(
                    for: reply,
                    suppressesVerifiedReference: usesThreadedPresentation && hierarchy.depth > 0
                )
            )
        }
    }

    private static func displayedDocument(
        for reply: Reply,
        suppressesVerifiedReference: Bool
    ) -> ForumPostDocument {
        guard suppressesVerifiedReference,
              let prefix = reply.conversation?.verifiedLeadingPrefix,
              let firstBlock = reply.contentDocument.blocks.first,
              case let .text(text) = firstBlock.content,
              text.hasPrefix(prefix)
        else { return reply.contentDocument }

        let remainingText = String(text.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let remainingBlocks = [
            ForumContentBlock(
                id: firstBlock.id,
                content: .text(remainingText),
                provenance: firstBlock.provenance
            )
        ] + reply.contentDocument.blocks.dropFirst()

        return ForumPostDocument(
            rawMarkup: reply.contentDocument.rawMarkup,
            fallbackText: remainingText,
            markupFormat: reply.contentDocument.markupFormat,
            sourceURL: reply.contentDocument.sourceURL,
            representations: reply.contentDocument.representations,
            blocks: remainingBlocks,
            diagnostics: reply.contentDocument.diagnostics,
            quality: reply.contentDocument.quality,
            schemaVersion: reply.contentDocument.schemaVersion
        )
    }

    private static func resolvedPage(forReplyIndex replyIndex: Int?, pageStarts: [(key: Int, value: Int)]) -> Int {
        guard let replyIndex else { return 1 }
        return pageStarts.last(where: { $0.value <= replyIndex })?.key ?? 1
    }

    private static func floorLabel(
        replyIndex: Int?, page: Int, floorNumber: Int?, pageStartReplyIndices: [Int: Int], supportsDirectPagination: Bool, pageSize: Int
    ) -> String {
        if let floorNumber, floorNumber > 0 { return "\(floorNumber)楼" }
        guard let replyIndex else { return "--楼" }
        guard supportsDirectPagination, page > 1 else { return "\(replyIndex + 2)楼" }
        let pageStartIndex = pageStartReplyIndices[page] ?? 0
        return "\(((page - 1) * pageSize) + (replyIndex - pageStartIndex) + 1)楼"
    }
}
