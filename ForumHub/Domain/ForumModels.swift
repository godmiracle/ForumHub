import Foundation

enum ForumSource: String, CaseIterable, Codable, Identifiable {
    case nga
    case v2ex
    case linuxDo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nga: return "NGA"
        case .v2ex: return "V2EX"
        case .linuxDo: return "LINUX DO"
        }
    }
}

struct ForumCapabilities: Equatable {
    let supportsSearch: Bool
    let supportsFavorites: Bool
    let supportsReply: Bool
    let supportsAuthentication: Bool
    let supportsFeedPagination: Bool
}

struct ReplyAttachmentUpload {
    let filename: String
    let mimeType: String
    let data: Data
}

struct ForumPayload {
    let forum: ForumSummary
    let channels: [ForumChannel]
    let pinned: [ForumThread]
    let threads: [ForumThread]

    static let mock = ForumPayload(
        forum: ForumSummary(
            id: -7,
            title: "网事杂谈",
            subtitle: "Preview 使用本地 mock 数据，不访问登录页。",
            todayPosts: 0,
            onlineUsers: 3
        ),
        channels: [
            .defaultForum,
            ForumChannel(id: 706, title: "大时代"),
            ForumChannel(id: -7_955_747, title: "晴风村")
        ],
        pinned: [
            ForumThread(
                id: 90001,
                title: "版规与发帖须知",
                summary: "这里是预览数据，真机运行后会请求 NGA。",
                author: "版主组",
                lastReplyAt: "今天 09:12",
                replyCount: 128,
                viewCount: 5044,
                body: "预览模式不会触发 WebView 登录。",
                replies: []
            )
        ],
        threads: [
            ForumThread(
                id: 90002,
                title: "SwiftUI 做论坛首页，列表结构怎么拆比较顺手？",
                summary: "首页先做版面头部、置顶区、普通主题区三段。",
                author: "CJ",
                lastReplyAt: "5 分钟前",
                replyCount: 34,
                viewCount: 1402,
                body: "后面会替换成真实帖子详情接口。",
                replies: [
                    Reply(id: 1, author: "北门", createdAt: "3 分钟前", body: "先跑通登录链路。")
                ]
            ),
            ForumThread(
                id: 90003,
                title: "网页登录后复用 cookie 请求接口",
                summary: "登录成功后会同步 `WKHTTPCookieStore` 到 `HTTPCookieStorage`。",
                author: "架构组",
                lastReplyAt: "今天 16:48",
                replyCount: 18,
                viewCount: 873,
                body: "这个版本适合自用调试。",
                replies: []
            )
        ]
    )
}

struct ForumChannel: Identifiable, Equatable {
    let id: Int
    let title: String
    let source: ForumSource
    let nativeKey: String

    init(
        id: Int,
        title: String,
        source: ForumSource = .nga,
        nativeKey: String? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.nativeKey = nativeKey ?? String(id)
    }

    static let defaultForum = ForumChannel(id: -7, title: "网事杂谈")
    static let defaultChannels = [
        defaultForum,
        ForumChannel(id: 706, title: "大时代"),
        ForumChannel(id: -7_955_747, title: "晴风村")
    ]
    static let v2exLatest = ForumChannel(
        id: -20_001,
        title: "最新",
        source: .v2ex,
        nativeKey: "latest"
    )
    static let linuxDoLatest = ForumChannel(
        id: -30_001,
        title: "最新",
        source: .linuxDo,
        nativeKey: "latest"
    )
}

struct ForumSummary: Equatable {
    let id: Int
    let title: String
    let subtitle: String
    let todayPosts: Int
    let onlineUsers: Int
    let source: ForumSource

    init(
        id: Int,
        title: String,
        subtitle: String,
        todayPosts: Int,
        onlineUsers: Int,
        source: ForumSource = .nga
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.todayPosts = todayPosts
        self.onlineUsers = onlineUsers
        self.source = source
    }

    static let defaultForum = ForumSummary(
        id: -7,
        title: "网事杂谈",
        subtitle: "登录后直接请求 `subject/list`。",
        todayPosts: 0,
        onlineUsers: 0
    )
}

struct ForumThread: Identifiable, Equatable {
    let id: Int
    let title: String
    let summary: String
    let author: String
    let authorAvatarURL: URL?
    let createdAt: String
    let lastReplyAt: String
    let replyCount: Int
    let viewCount: Int
    let body: String
    let replies: [Reply]
    let source: ForumSource
    let channelID: Int?
    let channelTitle: String?

    init(
        id: Int,
        title: String,
        summary: String,
        author: String,
        authorAvatarURL: URL? = nil,
        createdAt: String = "",
        lastReplyAt: String,
        replyCount: Int,
        viewCount: Int,
        body: String,
        replies: [Reply],
        source: ForumSource = .nga,
        channelID: Int? = nil,
        channelTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.author = author
        self.authorAvatarURL = authorAvatarURL
        self.createdAt = createdAt
        self.lastReplyAt = lastReplyAt
        self.replyCount = replyCount
        self.viewCount = viewCount
        self.body = body
        self.replies = replies
        self.source = source
        self.channelID = channelID
        self.channelTitle = channelTitle
    }

    static func == (lhs: ForumThread, rhs: ForumThread) -> Bool {
        lhs.id == rhs.id && lhs.source == rhs.source
    }

    var authorReplies: [Reply] {
        guard author.isUsefulForumValue else { return [] }

        let normalizedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        return replies.filter { reply in
            reply.author.trimmingCharacters(in: .whitespacesAndNewlines).compare(
                normalizedAuthor,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }

    var createdAtSortDate: Date? {
        Self.sortDate(from: createdAt)
    }

    var lastReplySortDate: Date? {
        Self.sortDate(from: lastReplyAt)
    }

    func appendingReplies(_ additionalReplies: [Reply]) -> ForumThread {
        let existingIDs = Set(replies.map(\.id))
        let existingSignatureKeys = Set(replies.map(\.signatureKey))
        let uniqueReplies = additionalReplies.filter { reply in
            !existingIDs.contains(reply.id) && !existingSignatureKeys.contains(reply.signatureKey)
        }
        let combinedReplies = replies + uniqueReplies

        return ForumThread(
            id: id,
            title: title,
            summary: summary,
            author: author,
            authorAvatarURL: authorAvatarURL,
            createdAt: createdAt,
            lastReplyAt: uniqueReplies.last?.createdAt ?? lastReplyAt,
            replyCount: max(replyCount, combinedReplies.count),
            viewCount: viewCount,
            body: body,
            replies: combinedReplies,
            source: source,
            channelID: channelID,
            channelTitle: channelTitle
        )
    }

    func withChannel(_ channel: ForumChannel) -> ForumThread {
        ForumThread(
            id: id,
            title: title,
            summary: summary,
            author: author,
            authorAvatarURL: authorAvatarURL,
            createdAt: createdAt,
            lastReplyAt: lastReplyAt,
            replyCount: replyCount,
            viewCount: viewCount,
            body: body,
            replies: replies,
            source: source,
            channelID: channel.id,
            channelTitle: channel.title
        )
    }

    func replacingReplies(
        _ newReplies: [Reply],
        lastReplyAt: String? = nil,
        replyCount: Int? = nil
    ) -> ForumThread {
        ForumThread(
            id: id,
            title: title,
            summary: summary,
            author: author,
            authorAvatarURL: authorAvatarURL,
            createdAt: createdAt,
            lastReplyAt: lastReplyAt ?? self.lastReplyAt,
            replyCount: replyCount ?? self.replyCount,
            viewCount: viewCount,
            body: body,
            replies: newReplies,
            source: source,
            channelID: channelID,
            channelTitle: channelTitle
        )
    }

    func mergingMetadataFallback(from fallback: ForumThread) -> ForumThread {
        ForumThread(
            id: id,
            title: title.isUsefulForumValue ? title : fallback.title,
            summary: summary.isUsefulForumValue ? summary : fallback.summary,
            author: author.isUsefulForumValue ? author : fallback.author,
            authorAvatarURL: authorAvatarURL ?? fallback.authorAvatarURL,
            createdAt: createdAt.isUsefulForumValue ? createdAt : fallback.createdAt,
            lastReplyAt: lastReplyAt.isUsefulForumValue ? lastReplyAt : fallback.lastReplyAt,
            replyCount: max(replyCount, fallback.replyCount),
            viewCount: max(viewCount, fallback.viewCount),
            body: body.isUsefulForumValue ? body : fallback.body,
            replies: replies,
            source: source,
            channelID: channelID ?? fallback.channelID,
            channelTitle: channelTitle ?? fallback.channelTitle
        )
    }

    private static func sortDate(from rawValue: String) -> Date? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let timestamp = TimeInterval(value) {
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()

        if let minutes = matchInteger(in: value, pattern: #"(\d+)\s*分钟前"#) {
            return calendar.date(byAdding: .minute, value: -minutes, to: now)
        }

        if let hours = matchInteger(in: value, pattern: #"(\d+)\s*小时前"#) {
            return calendar.date(byAdding: .hour, value: -hours, to: now)
        }

        if let days = matchInteger(in: value, pattern: #"(\d+)\s*天前"#) {
            return calendar.date(byAdding: .day, value: -days, to: now)
        }

        if let time = matchString(in: value, pattern: #"今天\s*(\d{1,2}:\d{2})"#) {
            return dateForToday(time: time, calendar: calendar)
        }

        if let time = matchString(in: value, pattern: #"昨天\s*(\d{1,2}:\d{2})"#),
           let today = dateForToday(time: time, calendar: calendar) {
            return calendar.date(byAdding: .day, value: -1, to: today)
        }

        for format in [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "MM-dd HH:mm",
            "M-d HH:mm"
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                if format.contains("yyyy") {
                    return date
                }

                let year = calendar.component(.year, from: now)
                var components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
                components.year = year
                return calendar.date(from: components)
            }
        }

        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: value) {
            return date
        }

        let fallbackISO8601Formatter = ISO8601DateFormatter()
        fallbackISO8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = fallbackISO8601Formatter.date(from: value) {
            return date
        }

        return nil
    }

    private static func matchInteger(in value: String, pattern: String) -> Int? {
        guard let string = matchString(in: value, pattern: pattern) else { return nil }
        return Int(string)
    }

    private static func matchString(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: value)
        else {
            return nil
        }
        return String(value[captureRange])
    }

    private static func dateForToday(time: String, calendar: Calendar) -> Date? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }
}

struct Reply: Identifiable, Equatable {
    let id: Int
    let author: String
    let createdAt: String
    let body: String
    let avatarURL: URL?
    let floorNumber: Int?

    init(
        id: Int,
        author: String,
        createdAt: String,
        body: String,
        avatarURL: URL? = nil,
        floorNumber: Int? = nil
    ) {
        self.id = id
        self.author = author
        self.createdAt = createdAt
        self.body = body
        self.avatarURL = avatarURL
        self.floorNumber = floorNumber
    }

    var signatureKey: String {
        let normalizedAuthor = author
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedCreatedAt = createdAt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedBody = body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return "\(normalizedAuthor)|\(normalizedCreatedAt)|\(normalizedBody)"
    }
}

enum ForumAvatarResolver {
    static func ngaAvatarURL(uid: Int?) -> URL? {
        guard let uid, uid > 0 else { return nil }
        var components = URLComponents(string: "https://img4.nga.178.com/ngabbs/nga_classic/f/app/uc_server/avatar.php")
        components?.queryItems = [
            URLQueryItem(name: "uid", value: String(uid)),
            URLQueryItem(name: "size", value: "small")
        ]
        return components?.url
    }
}
