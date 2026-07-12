import Foundation

struct ThreadDetailParser {
    static func parse(data: Data, fallbackText: String, tid: Int, page: Int = 1) -> ForumThread? {
        guard let object = NGAJSONParser.object(from: data, fallbackText: fallbackText) else {
            return nil
        }

        let userNamesByID = collectUserNames(in: object)

        if let thread = parseResultPosts(in: object, tid: tid, page: page, userNamesByID: userNamesByID) {
            return thread
        }

        let dictionaries = collectDictionaries(in: object)
        let title = dictionaries
            .compactMap { string(for: ["subject", "title", "t", "topic", "post_subject", "topic_title", "_subject"], in: $0)?.cleanedForumText }
            .first { !$0.isEmpty } ?? "帖子 \(tid)"

        let posts = dictionaries
            .compactMap { makeReply(from: $0, userNamesByID: userNamesByID) }
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

    private static func parseResultPosts(
        in object: Any,
        tid: Int,
        page: Int,
        userNamesByID: [Int: String]
    ) -> ForumThread? {
        guard let root = object as? [String: Any],
              let resultDictionaries = postDictionaries(from: root["result"])
        else {
            return nil
        }

        let result = normalizedResultDictionaries(resultDictionaries, page: page)
        let posts = result.enumerated().compactMap { index, dictionary in
            makeReply(
                from: dictionary,
                fallbackID: fallbackReplyID(tid: tid, page: page, index: index),
                userNamesByID: userNamesByID
            )
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
                int(for: ["replies", "reply_count", "replys"], in: firstDictionary) ?? 0,
                max((int(for: ["postnum"], in: firstDictionary) ?? 1) - 1, 0)
            ),
            viewCount: int(for: ["views", "view_count", "hits"], in: firstDictionary) ?? 0,
            body: firstPost.body,
            replies: replies
        )
    }

    private static func postDictionaries(from result: Any?) -> [[String: Any]]? {
        if let dictionaries = result as? [[String: Any]] {
            return sortPostDictionaries(dictionaries.filter(isThreadPostDictionary))
        }

        if let dictionary = result as? [String: Any] {
            let posts = dictionary.compactMap { _, value -> [String: Any]? in
                guard let nested = value as? [String: Any], isThreadPostDictionary(nested) else { return nil }
                return nested
            }
            let keyedPosts = sortPostDictionaries(posts)

            if !keyedPosts.isEmpty {
                return keyedPosts
            }
        }

        return nil
    }

    /// 不依赖 API 数组顺序。主楼在 NGA 中由 `pid == 0` 或楼层号 `0` 标识；
    /// 部分旧响应把主楼标为 `lou == 1`，但此时仍以 `pid == 0` 优先。
    private static func sortPostDictionaries(_ dictionaries: [[String: Any]]) -> [[String: Any]] {
        dictionaries.sorted { lhs, rhs in
            let lhsRank = postSortRank(lhs)
            let rhsRank = postSortRank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            let lhsFloor = int(for: ["lou", "floor", "position"], in: lhs) ?? .max
            let rhsFloor = int(for: ["lou", "floor", "position"], in: rhs) ?? .max
            if lhsFloor != rhsFloor {
                return lhsFloor < rhsFloor
            }

            return (int(for: ["pid", "id", "post_id"], in: lhs) ?? .max)
                < (int(for: ["pid", "id", "post_id"], in: rhs) ?? .max)
        }
    }

    private static func postSortRank(_ dictionary: [String: Any]) -> Int {
        if int(for: ["pid", "post_id"], in: dictionary) == 0 {
            return 0
        }
        if int(for: ["lou", "floor", "position"], in: dictionary) == 0 {
            return 0
        }
        return 1
    }

    /// `result` 同时包含真实楼层和引用等辅助字典；只有带 NGA 帖子身份字段的记录才可成为回帖。
    nonisolated private static func isThreadPostDictionary(_ dictionary: [String: Any]) -> Bool {
        if int(for: ["pid", "post_id"], in: dictionary) != nil {
            return true
        }

        // 兼容少数以 `id` 表示帖子 ID 的响应，但引用元数据不会同时声明所属主题。
        return int(for: ["id"], in: dictionary) != nil
            && int(for: ["tid", "topic_id", "thread_id"], in: dictionary) != nil
    }

    private static func normalizedResultDictionaries(_ dictionaries: [[String: Any]], page: Int) -> [[String: Any]] {
        guard page > 1 else { return dictionaries }

        let filtered = dictionaries.filter { dictionary in
            !isMainPostDictionary(dictionary)
        }

        return filtered.isEmpty ? dictionaries : filtered
    }

    private static func isMainPostDictionary(_ dictionary: [String: Any]) -> Bool {
        if let pid = int(for: ["pid", "post_id"], in: dictionary), pid == 0 {
            return true
        }

        if let floor = int(for: ["lou", "floor", "position"], in: dictionary), floor <= 1 {
            return true
        }

        return false
    }

    private static func fallbackReplyID(tid: Int, page: Int, index: Int) -> Int {
        tid * 10_000 + page * 100 + index
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

    private static func makeReply(from dictionary: [String: Any], userNamesByID: [Int: String]) -> Reply? {
        makeReply(
            from: dictionary,
            fallbackID: abs((string(for: ["content"], in: dictionary) ?? "").hashValue),
            userNamesByID: userNamesByID
        )
    }

    private static func makeReply(
        from dictionary: [String: Any],
        fallbackID: Int,
        userNamesByID: [Int: String]
    ) -> Reply? {
        guard let rawContent = contentText(in: dictionary),
              let body = Optional(rawContent.structuredForumText),
            !body.isEmpty
        else {
            return nil
        }

        let validPostID = validPostID(in: dictionary)
        let resolvedAuthor = authorName(in: dictionary, userNamesByID: userNamesByID)

        return Reply(
            id: validPostID ?? fallbackID,
            sourcePostID: validPostID,
            author: resolvedAuthor ?? "未知作者",
            createdAt: string(for: ["postdate", "timestamp", "created_at", "lastpost", "time"], in: dictionary) ?? "未知时间",
            body: body,
            contentDocument: .ngaBBCode(rawContent),
            avatarURL: avatarURL(in: dictionary),
            floorNumber: int(for: ["lou", "floor", "position"], in: dictionary)
        )
    }

    private static func authorName(in dictionary: [String: Any], userNamesByID: [Int: String]) -> String? {
        if let author = dictionary["author"] as? [String: Any],
           let username = string(for: ["username", "nickname", "name"], in: author)?.cleanedForumText,
           !username.isEmpty {
            return username
        }

        if let direct = string(
            for: ["author", "author_name", "username", "postusername", "poster", "user_name", "nickname", "name"],
            in: dictionary
        )?.cleanedForumText,
           direct.isUsefulForumValue {
           return direct
        }

        for key in ["user", "author_info", "poster_info", "userInfo"] {
            if let nested = dictionary[key] as? [String: Any],
               let name = authorName(in: nested, userNamesByID: userNamesByID) {
                return name
            }
        }

        return authorID(in: dictionary).flatMap { userNamesByID[$0] }
    }

    private static func authorID(in dictionary: [String: Any]) -> Int? {
        if let author = dictionary["author"] as? [String: Any],
           let id = int(for: ["uid", "id", "authorid", "author_id"], in: author) {
            return id
        }
        for key in ["user", "author_info", "poster_info", "userInfo"] {
            if let nested = dictionary[key] as? [String: Any],
               let id = int(for: ["uid", "id", "authorid", "author_id"], in: nested) {
                return id
            }
        }
        return int(for: ["uid", "authorid", "author_id", "user_id", "posterid"], in: dictionary)
    }

    private static func collectUserNames(in object: Any) -> [Int: String] {
        var names: [Int: String] = [:]

        if let dictionary = object as? [String: Any] {
            if let id = int(for: ["uid", "id"], in: dictionary),
               let name = string(for: ["username", "nickname", "name"], in: dictionary)?.cleanedForumText,
               name.isUsefulForumValue {
                names[id] = name
            }

            if let users = dictionary["__U"] as? [String: Any] {
                for (key, value) in users {
                    guard let user = value as? [String: Any],
                          let id = int(for: ["uid", "id"], in: user) ?? Int(key),
                          let name = string(for: ["username", "nickname", "name"], in: user)?.cleanedForumText,
                          name.isUsefulForumValue
                    else { continue }
                    names[id] = name
                }
            }

            for value in dictionary.values {
                for (id, name) in collectUserNames(in: value) where names[id] == nil {
                    names[id] = name
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                for (id, name) in collectUserNames(in: value) where names[id] == nil {
                    names[id] = name
                }
            }
        }

        return names
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
           let url = ForumAvatarResolver.ngaAvatarURL(from: direct) {
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

    private static func contentText(in dictionary: [String: Any]) -> String? {
        if let direct = string(for: ["content", "postcontent", "body", "comment", "post_content"], in: dictionary) {
            return direct
        }

        for key in ["content", "postcontent", "body", "comment", "post_content"] {
            if let lines = dictionary[key] as? [String] {
                return lines.joined(separator: "\n")
            }
            if let values = dictionary[key] as? [Any] {
                let lines = values.compactMap { value -> String? in
                    if let line = value as? String { return line }
                    if let segment = value as? [String: Any] {
                        return string(for: ["text", "content", "body"], in: segment)
                    }
                    return nil
                }
                if !lines.isEmpty { return lines.joined(separator: "\n") }
            }
        }
        return nil
    }

    nonisolated private static func int(for keys: [String], in dictionary: [String: Any]) -> Int? {
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
