import Foundation

struct WebForumParser {
    static func parseForumHTML(_ html: String, fid: Int, page: Int) -> ForumPayload? {
        let topicRowThreads = parseTopicRows(from: html, fid: fid)
        if !topicRowThreads.isEmpty {
            return ForumPayload(
                forum: ForumSummary(
                    id: fid,
                    title: "NGA 版面 \(fid)",
                    subtitle: "正在使用网页登录 cookie 浏览网页内容，第 \(page) 页。",
                    todayPosts: 0,
                    onlineUsers: topicRowThreads.count
                ),
                channels: parseChannels(from: html, fallbackFID: fid),
                pinned: [],
                threads: topicRowThreads
            )
        }

        let links = html.matches(
            pattern: #"<a([^>]+href=['"][^'"]*(?:read\.php\?tid=|tid=)(\d+)[^'"]*['"][^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        let threads = links.compactMap { match -> ForumThread? in
            guard match.count >= 3,
                  let id = Int(match[2])
            else {
                return nil
            }

            let attributes = match[1]
            let linkText = match.count >= 4 ? match[3] : ""
            let title = firstAttribute(["title", "data-title", "data-subject"], in: attributes)?.cleanedForumText
                ?? linkText.cleanedForumText

            guard title.count >= 2, !title.localizedCaseInsensitiveContains("回复") else {
                return nil
            }

            return ForumThread(
                id: id,
                title: title,
                summary: "来自网页兜底解析",
                author: firstAttribute(["data-author", "author", "username"], in: attributes)?.cleanedForumText ?? "未知作者",
                createdAt: "",
                lastReplyAt: "",
                replyCount: 0,
                viewCount: 0,
                body: title,
                replies: []
            )
        }
        .uniquedByThreadID()
        .prefix(40)

        let threadList = Array(threads)
        guard !threadList.isEmpty else {
            return nil
        }

        return ForumPayload(
            forum: ForumSummary(
                id: fid,
                title: "NGA 版面 \(fid)",
                subtitle: "正在使用网页登录 cookie 浏览网页内容，第 \(page) 页。",
                todayPosts: 0,
                onlineUsers: threadList.count
            ),
            channels: parseChannels(from: html, fallbackFID: fid),
            pinned: [],
            threads: threadList
        )
    }

    private static func parseTopicRows(from html: String, fid: Int) -> [ForumThread] {
        let rows = html.matches(
            pattern: #"<tr[^>]*\btopicrow\b[^>]*>(.*?)</tr>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        return rows.compactMap { match -> ForumThread? in
            guard match.count >= 2 else { return nil }
            let rowHTML = match[1]
            let anchors = rowHTML.matches(
                pattern: #"<a([^>]*)>(.*?)</a>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )

            guard let topicAnchor = anchors.first(where: { anchor in
                guard anchor.count >= 3 else { return false }
                let attributes = anchor[1]
                let identifier = firstAttribute(["id"], in: attributes) ?? ""
                return hasClass("topic", in: attributes) || identifier.hasPrefix("t_tt")
            }),
            let href = firstAttribute(["href"], in: topicAnchor[1]),
            let idMatch = href.matches(pattern: #"\btid=(\d+)"#, options: [.caseInsensitive]).first,
            idMatch.count >= 2,
            let id = Int(idMatch[1])
            else {
                return nil
            }

            let title = topicAnchor[2].cleanedForumText
            guard title.count >= 2,
                  !title.localizedCaseInsensitiveContains("打开新窗口")
            else {
                return nil
            }

            let author = anchors.first(where: { anchor in
                guard anchor.count >= 3 else { return false }
                let attributes = anchor[1]
                let identifier = firstAttribute(["id"], in: attributes) ?? ""
                return hasClass("author", in: attributes) || identifier.hasPrefix("t_ta")
            })?[2].cleanedForumText

            let replyCount = anchors.first(where: { anchor in
                guard anchor.count >= 3 else { return false }
                let attributes = anchor[1]
                let identifier = firstAttribute(["id"], in: attributes) ?? ""
                return hasClass("replies", in: attributes) || identifier.hasPrefix("t_rc")
            })
            .flatMap { Int($0[2].cleanedForumText) } ?? 0

            let postDate = rowHTML.matches(
                pattern: #"<span([^>]*(?:\bpostdate\b|\bid=['\"]t_pt[^'\"]*['\"])[^>]*)>(.*?)</span>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
            .first
            .flatMap { $0.count >= 3 ? $0[2].cleanedForumText : nil } ?? ""

            return ForumThread(
                id: id,
                title: title,
                summary: "",
                author: author?.isUsefulForumValue == true ? author! : "未知作者",
                createdAt: postDate,
                // topicrow 这里只提供首帖 postdate，不能伪装成最后回复时间。
                lastReplyAt: "",
                replyCount: replyCount,
                viewCount: 0,
                body: title,
                replies: [],
                channelID: fid
            )
        }
        .uniquedByThreadID()
        .prefix(40)
        .map { $0 }
    }

    private static func parseChannels(from html: String, fallbackFID: Int) -> [ForumChannel] {
        let matches = html.matches(
            pattern: #"<a([^>]+href=['"][^'"]*(?:thread\.php\?fid=|fid=)(-?\d+)[^'"]*['"][^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        let channels = matches.compactMap { match -> ForumChannel? in
            guard match.count >= 4,
                  let id = Int(match[2])
            else {
                return nil
            }

            let attributes = match[1]
            let linkText = match[3]
            let title = firstAttribute(["title", "data-title", "data-name"], in: attributes)?.cleanedForumText
                ?? linkText.cleanedForumText

            guard title.count >= 1,
                  !title.localizedCaseInsensitiveContains("回复"),
                  !title.localizedCaseInsensitiveContains("下一页")
            else {
                return nil
            }

            return ForumChannel(id: id, title: title)
        }
        .uniquedByChannelID()

        return channels.isEmpty ? [ForumChannel(id: fallbackFID, title: "NGA 版面 \(fallbackFID)")] : channels
    }

    private static func firstAttribute(_ names: [String], in attributes: String) -> String? {
        for name in names {
            let matches = attributes.matches(
                pattern: #"\b\#(name)\s*=\s*['"]([^'"]+)['"]"#,
                options: [.caseInsensitive]
            )

            if let value = matches.first?.dropFirst().first, !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private static func hasClass(_ expectedClass: String, in attributes: String) -> Bool {
        guard let classes = firstAttribute(["class"], in: attributes) else {
            return false
        }

        return classes
            .split(whereSeparator: { $0.isWhitespace })
            .contains { $0.caseInsensitiveCompare(expectedClass) == .orderedSame }
    }

    static func parseThreadHTML(_ html: String, tid: Int, page: Int = 1) -> ForumThread? {
        let title = html.matches(
            pattern: #"<title>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        .first?
        .dropFirst()
        .first?
        .cleanedForumText
        .replacingOccurrences(of: " - NGA玩家社区", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        // 不能用 `.*?</div>` 一类正则提取正文：主楼中只要有嵌套 `div`，
        // 就会在首个内层闭合标签提前截断。按标签层级取出精确的楼层节点。
        let contentNodes = HTMLPostContentExtractor.postContentNodes(in: html)

        let pageAuthor = html.matches(
            pattern: #"(?:用户名|作者|poster|username)[^<]{0,24}<[^>]*>([^<]{1,40})</"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        .first?
        .dropFirst()
        .first?
        .cleanedForumText

        var replies = contentNodes.compactMap { node -> Reply? in
            let floor = node.floor
            let rawMarkup = node.innerHTML
            let document = NGAHTMLContentParser.parse(rawMarkup)
            guard document.quality != .unusable else { return nil }

            return Reply(
                id: tid * 100_000 + floor,
                author: pageAuthor?.isUsefulForumValue == true ? pageAuthor! : "未知作者",
                createdAt: "",
                body: document.bodyText,
                contentDocument: document,
                floorNumber: floor
            )
        }
        .uniquedByID()

        // 权限错误、登录页等网页响应没有帖子正文容器，不能把整页提示文本
        // 误认为主贴内容；调用方会在此时保留已成功解析的 API 正文。
        guard !replies.isEmpty else { return nil }

        if page > 1 {
            return ForumThread(
                id: tid,
                title: title?.isEmpty == false ? title! : "帖子 \(tid)",
                summary: "",
                author: "未知作者",
                createdAt: "",
                lastReplyAt: replies.last?.createdAt ?? "",
                replyCount: replies.count,
                viewCount: 0,
                body: "",
                replies: replies
            )
        }

        let firstPost = replies.removeFirst()

        return ForumThread(
            id: tid,
            title: title?.isEmpty == false ? title! : "帖子 \(tid)",
            summary: firstPost.body,
            author: firstPost.author,
            createdAt: firstPost.createdAt,
            lastReplyAt: firstPost.createdAt,
            replyCount: replies.count,
            viewCount: 0,
            body: firstPost.body,
            contentDocument: firstPost.contentDocument,
            replies: replies
        )
    }

}

/// 仅负责定位 NGA 的 `postcontent<楼层号>` 节点。它不是通用 HTML 渲染器，
/// 但会按相同标签的嵌套层级配对，避免正文中的嵌套容器截断主楼内容。
private enum HTMLPostContentExtractor {
    struct Node {
        let floor: Int
        let innerHTML: String
    }

    static func postContentNodes(in html: String) -> [Node] {
        var nodes: [Node] = []
        var cursor = html.startIndex

        while let openingStart = html[cursor...].firstIndex(of: "<"),
              let openingEnd = tagEnd(in: html, from: openingStart) {
            let openingTag = String(html[openingStart...openingEnd])
            guard let tagName = openingTagName(in: openingTag),
                  let floor = postContentFloor(in: openingTag),
                  !isSelfClosing(openingTag),
                  let closingRange = matchingClosingTag(
                    for: tagName,
                    in: html,
                    contentStart: html.index(after: openingEnd)
                  )
            else {
                cursor = html.index(after: openingStart)
                continue
            }

            nodes.append(Node(
                floor: floor,
                innerHTML: String(html[html.index(after: openingEnd)..<closingRange.lowerBound])
            ))
            cursor = closingRange.upperBound
        }

        var seenFloors = Set<Int>()
        return nodes.filter { seenFloors.insert($0.floor).inserted }
    }

    private static func matchingClosingTag(
        for tagName: String,
        in html: String,
        contentStart: String.Index
    ) -> Range<String.Index>? {
        var depth = 1
        var cursor = contentStart

        while let tagStart = html[cursor...].firstIndex(of: "<"),
              let tagEndIndex = tagEnd(in: html, from: tagStart) {
            let tag = String(html[tagStart...tagEndIndex])
            if let closingName = closingTagName(in: tag), closingName == tagName {
                depth -= 1
                if depth == 0 {
                    return tagStart..<html.index(after: tagEndIndex)
                }
            } else if openingTagName(in: tag) == tagName, !isSelfClosing(tag) {
                depth += 1
            }
            cursor = html.index(after: tagEndIndex)
        }

        return nil
    }

    private static func tagEnd(in html: String, from start: String.Index) -> String.Index? {
        var cursor = html.index(after: start)
        var quote: Character?

        while cursor < html.endIndex {
            let character = html[cursor]
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return cursor
            }
            cursor = html.index(after: cursor)
        }
        return nil
    }

    private static func openingTagName(in tag: String) -> String? {
        let trimmed = tag
            .dropFirst()
            .dropLast()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("!"), !trimmed.hasPrefix("?") else {
            return nil
        }
        return trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "/" }).first?.lowercased()
    }

    private static func closingTagName(in tag: String) -> String? {
        let trimmed = tag
            .dropFirst()
            .dropLast()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        return trimmed.dropFirst().split(whereSeparator: { $0.isWhitespace || $0 == ">" }).first?.lowercased()
    }

    private static func postContentFloor(in openingTag: String) -> Int? {
        openingTag.matches(
            pattern: #"\bid\s*=\s*['\"]postcontent(\d+)['\"]"#,
            options: [.caseInsensitive]
        )
        .first?
        .dropFirst()
        .first
        .flatMap(Int.init)
    }

    private static func isSelfClosing(_ tag: String) -> Bool {
        tag.dropLast().trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/")
    }
}
