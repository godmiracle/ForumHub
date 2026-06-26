import Foundation

struct ForumPayloadParser {
    static func parse(data: Data, fallbackText: String, fid: Int) -> ForumPayload? {
        guard let object = NGAJSONParser.object(from: data, fallbackText: fallbackText) else {
            return nil
        }

        let candidates = collectCandidates(in: object)
        guard !candidates.isEmpty else {
            return nil
        }

        let threads = candidates.prefix(30).enumerated().map { index, item in
            ForumThread(
                id: item.id ?? (100000 + index),
                title: item.title,
                summary: item.summary,
                author: item.author,
                authorAvatarURL: item.authorAvatarURL,
                createdAt: item.createdAt,
                lastReplyAt: item.lastReplyAt,
                replyCount: item.replyCount,
                viewCount: item.viewCount,
                body: item.summary,
                replies: []
            )
        }

        return ForumPayload(
            forum: ForumSummary(
                id: fid,
                title: "NGA 版面 \(fid)",
                subtitle: "已使用网页登录后的 cookie 直连 `app_api.php`。",
                todayPosts: 0,
                onlineUsers: threads.count
            ),
            channels: collectChannels(in: object, fallbackFID: fid),
            pinned: [],
            threads: threads
        )
    }

    private static func collectChannels(in object: Any, fallbackFID: Int) -> [ForumChannel] {
        var channels: [ForumChannel] = []

        if let dictionary = object as? [String: Any] {
            if let channel = makeChannel(from: dictionary) {
                channels.append(channel)
            }

            for value in dictionary.values {
                channels.append(contentsOf: collectChannels(in: value, fallbackFID: fallbackFID))
            }
        } else if let array = object as? [Any] {
            for item in array {
                channels.append(contentsOf: collectChannels(in: item, fallbackFID: fallbackFID))
            }
        } else if let string = object as? String,
                  let nestedObject = NGAJSONParser.object(from: Data(), fallbackText: string) {
            channels.append(contentsOf: collectChannels(in: nestedObject, fallbackFID: fallbackFID))
        }

        let unique = channels.uniquedByChannelID()
        return unique.isEmpty ? [ForumChannel(id: fallbackFID, title: "NGA 版面 \(fallbackFID)")] : unique
    }

    private static func makeChannel(from dictionary: [String: Any]) -> ForumChannel? {
        guard let id = int(for: ["fid", "forum_id", "id"], in: dictionary),
              let title = string(for: ["name", "title", "forum_name", "fname"], in: dictionary)?.cleanedForumText,
              !title.isEmpty
        else {
            return nil
        }

        let looksLikeForum = dictionary.keys.contains("fid")
            || dictionary.keys.contains("forum_id")
            || dictionary.keys.contains("forum_name")
            || dictionary.keys.contains("fname")

        guard looksLikeForum else {
            return nil
        }

        return ForumChannel(id: id, title: title)
    }

    private static func collectCandidates(in object: Any) -> [ThreadCandidate] {
        var results: [ThreadCandidate] = []

        if let dictionary = object as? [String: Any] {
            if let candidate = makeCandidate(from: dictionary) {
                results.append(candidate)
            }

            for value in dictionary.values {
                results.append(contentsOf: collectCandidates(in: value))
            }
        } else if let array = object as? [Any] {
            for item in array {
                results.append(contentsOf: collectCandidates(in: item))
            }
        } else if let string = object as? String,
                  let nestedObject = NGAJSONParser.object(from: Data(), fallbackText: string) {
            results.append(contentsOf: collectCandidates(in: nestedObject))
        }

        var seen = Set<Int>()
        return results.filter { candidate in
            if let id = candidate.id {
                return seen.insert(id).inserted
            }

            let key = candidate.title.hashValue
            return seen.insert(key).inserted
        }
    }

    private static func makeCandidate(from dictionary: [String: Any]) -> ThreadCandidate? {
        let title = string(for: ["subject", "title", "t", "topic", "post_subject", "topic_title", "_subject"], in: dictionary)?
            .cleanedForumText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let title, title.count >= 2 else {
            return nil
        }

        let id = int(for: ["tid", "id", "topic_id", "thread_id"], in: dictionary)
        guard id != nil || dictionary.keys.contains("subject") else {
            return nil
        }

        return ThreadCandidate(
            id: id,
            title: title,
            summary: string(for: ["content", "intro", "subject", "title", "post_subject"], in: dictionary)?.cleanedForumText ?? title,
            author: authorName(in: dictionary) ?? "未知作者",
            authorAvatarURL: avatarURL(in: dictionary),
            createdAt: string(for: ["postdate", "timestamp", "created_at", "post_time", "time"], in: dictionary) ?? "未知时间",
            lastReplyAt: string(for: ["lastpost", "postdate", "timestamp", "last_reply_time", "lastmodify"], in: dictionary) ?? "未知时间",
            replyCount: int(for: ["replies", "reply_count", "postnum", "replys"], in: dictionary) ?? 0,
            viewCount: int(for: ["views", "view_count", "hits"], in: dictionary) ?? 0
        )
    }

    private static func authorName(in dictionary: [String: Any]) -> String? {
        if let direct = string(
            for: [
                "author",
                "author_name",
                "username",
                "postusername",
                "lastposter",
                "poster",
                "user_name",
                "nickname",
                "name"
            ],
            in: dictionary
        )?.cleanedForumText,
           direct.isUsefulForumValue {
            return direct
        }

        for key in ["user", "author_info", "poster_info", "userInfo"] {
            if let nested = dictionary[key] as? [String: Any],
               let name = authorName(in: nested) {
                return name
            }
        }

        return nil
    }

    private static func avatarURL(in dictionary: [String: Any]) -> URL? {
        if let direct = string(
            for: ["avatar", "avatar_url", "avatar_normal", "avatar_middle", "portrait", "face"],
            in: dictionary
        ),
           let url = URL(string: direct),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return url
        }

        for key in ["author", "user", "author_info", "poster_info", "userInfo"] {
            if let nested = dictionary[key] as? [String: Any] {
                if let direct = avatarURL(in: nested) {
                    return direct
                }
                if key == "author" || key == "user" {
                    return ForumAvatarResolver.ngaAvatarURL(uid: int(for: ["uid", "id"], in: nested))
                }
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

struct ForumChannelParser {
    static func parse(data: Data, fallbackText: String) -> [ForumChannel] {
        guard let object = NGAJSONParser.object(from: data, fallbackText: fallbackText) else {
            return []
        }

        return collectChannels(in: object).uniquedByChannelID()
    }

    private static func collectChannels(in object: Any) -> [ForumChannel] {
        var channels: [ForumChannel] = []

        if let dictionary = object as? [String: Any] {
            if let channel = makeChannel(from: dictionary) {
                channels.append(channel)
            }

            for value in dictionary.values {
                channels.append(contentsOf: collectChannels(in: value))
            }
        } else if let array = object as? [Any] {
            for item in array {
                channels.append(contentsOf: collectChannels(in: item))
            }
        } else if let string = object as? String,
                  let nestedObject = NGAJSONParser.object(from: Data(), fallbackText: string) {
            channels.append(contentsOf: collectChannels(in: nestedObject))
        }

        return channels
    }

    private static func makeChannel(from dictionary: [String: Any]) -> ForumChannel? {
        guard let id = int(for: ["fid", "forum_id", "id", "fid2"], in: dictionary),
              id != 0,
              let title = string(for: ["name", "title", "forum_name", "fname", "forum", "text"], in: dictionary)?.cleanedForumText,
              !title.isEmpty
        else {
            return nil
        }

        let isLikelyForum = dictionary.keys.contains("fid")
            || dictionary.keys.contains("forum_id")
            || dictionary.keys.contains("forum_name")
            || dictionary.keys.contains("fname")
            || dictionary.keys.contains("fid2")

        guard isLikelyForum else {
            return nil
        }

        return ForumChannel(id: id, title: title)
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

private struct ThreadCandidate {
    let id: Int?
    let title: String
    let summary: String
    let author: String
    let authorAvatarURL: URL?
    let createdAt: String
    let lastReplyAt: String
    let replyCount: Int
    let viewCount: Int
}
