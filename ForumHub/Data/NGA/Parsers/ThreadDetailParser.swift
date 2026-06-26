import Foundation

struct ThreadDetailParser {
    static func parse(data: Data, fallbackText: String, tid: Int, page: Int = 1) -> ForumThread? {
        guard let object = NGAJSONParser.object(from: data, fallbackText: fallbackText) else {
            return nil
        }

        if let thread = parseResultArray(in: object, tid: tid, page: page) {
            return thread
        }

        let dictionaries = collectDictionaries(in: object)
        let title = dictionaries
            .compactMap { string(for: ["subject", "title", "t", "topic", "post_subject", "topic_title", "_subject"], in: $0)?.cleanedForumText }
            .first { !$0.isEmpty } ?? "帖子 \(tid)"

        let posts = dictionaries
            .compactMap { makeReply(from: $0) }
            .uniquedByID()

        guard !posts.isEmpty else {
            return nil
        }

        if page > 1 {
            return continuationPage(tid: tid, posts: posts)
        }

        let firstPost = posts[0]
        let replies = Array(posts.dropFirst())

        return ForumThread(
            id: tid,
            title: title,
            summary: firstPost.body,
            author: firstPost.author,
            authorAvatarURL: firstPost.avatarURL,
            lastReplyAt: firstPost.createdAt,
            replyCount: replies.count,
            viewCount: int(for: ["views", "view_count", "hits"], in: dictionaries.first ?? [:]) ?? 0,
            body: firstPost.body,
            replies: replies
        )
    }

    private static func parseResultArray(in object: Any, tid: Int, page: Int) -> ForumThread? {
        guard let root = object as? [String: Any],
              let result = root["result"] as? [[String: Any]]
        else {
            return nil
        }

        let posts = result.enumerated().compactMap { index, dictionary in
            makeReply(from: dictionary, fallbackID: tid * 1000 + index)
        }

        guard !posts.isEmpty else {
            return nil
        }

        if page > 1 {
            return continuationPage(tid: tid, posts: posts)
        }

        let firstPost = posts[0]
        let replies = Array(posts.dropFirst())
        let firstDictionary = result.first ?? [:]
        let title = string(for: ["subject", "title", "post_subject", "topic_title"], in: firstDictionary)?.cleanedForumText ?? "帖子 \(tid)"

        return ForumThread(
            id: tid,
            title: title,
            summary: firstPost.body,
            author: firstPost.author,
            authorAvatarURL: firstPost.avatarURL,
            lastReplyAt: firstPost.createdAt,
            replyCount: max(
                replies.count,
                int(for: ["replies", "reply_count", "postnum"], in: firstDictionary) ?? 0
            ),
            viewCount: int(for: ["views", "view_count", "hits"], in: firstDictionary) ?? 0,
            body: firstPost.body,
            replies: replies
        )
    }

    private static func continuationPage(tid: Int, posts: [Reply]) -> ForumThread {
        ForumThread(
            id: tid,
            title: "帖子 \(tid)",
            summary: "",
            author: "未知作者",
            lastReplyAt: posts.last?.createdAt ?? "",
            replyCount: posts.count,
            viewCount: 0,
            body: "",
            replies: posts
        )
    }

    private static func collectDictionaries(in object: Any) -> [[String: Any]] {
        if let dictionary = object as? [String: Any] {
            return [dictionary] + dictionary.values.flatMap { collectDictionaries(in: $0) }
        }

        if let array = object as? [Any] {
            return array.flatMap { collectDictionaries(in: $0) }
        }

        return []
    }

    private static func makeReply(from dictionary: [String: Any]) -> Reply? {
        makeReply(from: dictionary, fallbackID: abs((string(for: ["content"], in: dictionary) ?? "").hashValue))
    }

    private static func makeReply(from dictionary: [String: Any], fallbackID: Int) -> Reply? {
        guard let body = string(for: ["content", "postcontent", "body", "comment"], in: dictionary)?
            .cleanedForumText,
            !body.isEmpty
        else {
            return nil
        }

        return Reply(
            id: validPostID(in: dictionary) ?? fallbackID,
            author: authorName(in: dictionary) ?? "未知作者",
            createdAt: string(for: ["postdate", "timestamp", "created_at", "lastpost", "time"], in: dictionary) ?? "未知时间",
            body: body,
            avatarURL: avatarURL(in: dictionary)
        )
    }

    private static func authorName(in dictionary: [String: Any]) -> String? {
        if let author = dictionary["author"] as? [String: Any],
           let username = string(for: ["username", "nickname", "name"], in: author)?.cleanedForumText,
           !username.isEmpty {
            return username
        }

        return string(
            for: ["author", "author_name", "username", "postusername", "poster", "user_name", "nickname", "name"],
            in: dictionary
        )?.cleanedForumText
    }

    private static func validPostID(in dictionary: [String: Any]) -> Int? {
        guard let id = int(for: ["pid", "id", "post_id"], in: dictionary), id > 0 else {
            return nil
        }

        return id
    }

    private static func avatarURL(in dictionary: [String: Any]) -> URL? {
        if let direct = string(
            for: [
                "avatar",
                "avatar_url",
                "avatar_normal",
                "avatar_middle",
                "portrait",
                "face"
            ],
            in: dictionary
        ),
           let url = URL(string: direct),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return url
        }

        if let author = dictionary["author"] as? [String: Any] {
            if let direct = avatarURL(in: author) {
                return direct
            }
            return ForumAvatarResolver.ngaAvatarURL(uid: int(for: ["uid", "id"], in: author))
        }

        for key in ["user", "author_info", "poster_info", "userInfo"] {
            if let nested = dictionary[key] as? [String: Any],
               let url = avatarURL(in: nested) {
                return url
            }
        }

        return ForumAvatarResolver.ngaAvatarURL(uid: int(for: ["uid", "authorid", "author_id"], in: dictionary))
    }

    private static func string(for keys: [String], in dictionary: [String: Any]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }

            if let value = dictionary[key] as? NSNumber {
                return value.stringValue
            }
        }

        return nil
    }

    private static func int(for keys: [String], in dictionary: [String: Any]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }

            if let value = dictionary[key] as? NSNumber {
                return value.intValue
            }

            if let value = dictionary[key] as? String, let intValue = Int(value) {
                return intValue
            }
        }

        return nil
    }
}
