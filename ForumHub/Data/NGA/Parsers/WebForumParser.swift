import Foundation

struct WebForumParser {
    static func parseForumHTML(_ html: String, fid: Int, page: Int) -> ForumPayload? {
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

        let contentMatches = html.matches(
            pattern: #"<(?:p|span|div|td)[^>]+(?:id|class)=['"][^'"]*(?:postcontent|post_content|postbody|content)[^'"]*['"][^>]*>(.*?)</(?:p|span|div|td)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        let pageAuthor = html.matches(
            pattern: #"(?:用户名|作者|poster|username)[^<]{0,24}<[^>]*>([^<]{1,40})</"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        .first?
        .dropFirst()
        .first?
        .cleanedForumText

        var replies = contentMatches.enumerated().compactMap { index, match -> Reply? in
            guard match.count >= 2 else { return nil }
            let body = match[1].structuredForumText
            guard body.count >= 2 else { return nil }

            return Reply(
                id: tid * 1000 + index,
                author: pageAuthor?.isUsefulForumValue == true ? pageAuthor! : "未知作者",
                createdAt: "",
                body: body
            )
        }
        .uniquedByID()

        if replies.isEmpty {
            let bodyText = html.cleanedForumText
            let excerpt = String(bodyText.prefix(3000))
            guard excerpt.count >= 2 else { return nil }
            replies = [
                Reply(id: tid * 1000, author: "网页内容", createdAt: "", body: excerpt)
            ]
        }

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
            replies: replies
        )
    }
}
