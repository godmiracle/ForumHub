import Foundation

struct DiscourseThreadRepository: ThreadRepository {
    let source = ForumSource.linuxDo
    let capabilities = ForumCapabilities(
        supportsSearch: true,
        supportsFavorites: false,
        supportsReply: false,
        supportsReplyTargeting: false,
        supportsAuthentication: true,
        supportsFeedPagination: true
    )
    let defaultChannel = ForumChannel.linuxDoLatest

    private let session: URLSession
    private let baseURL: URL

    init(
        baseURL: URL = URL(string: "https://linux.do/")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchChannels() async throws -> [ForumChannel] {
        let data = try await getJSON(path: "site.json")
        let site = try JSONDecoder().decode(DiscourseSiteResponse.self, from: data)
        let categories = site.categories
            .filter { !$0.readRestricted }
            .map(DiscourseMapper.channel)

        return [defaultChannel] + categories.filter { $0.nativeKey != defaultChannel.nativeKey }
    }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        let path = channel.nativeKey == defaultChannel.nativeKey
            ? "latest.json"
            : "c/\(channel.nativeKey).json"
        let data = try await getJSON(
            path: path,
            queryItems: [URLQueryItem(name: "page", value: String(page))]
        )
        let listing = try JSONDecoder().decode(DiscourseTopicListResponse.self, from: data)
        let payload = DiscourseMapper.payload(
            source: source,
            channel: channel,
            listing: listing
        )
        let topicCount = listing.topicList?.topics.count ?? 0
        return ThreadFetchResult(
            payload: payload,
            rawText: String(decoding: data, as: UTF8.self),
            hasMore: topicCount >= 20
        )
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult {
        let data = try await getJSON(
            path: "top.json",
            queryItems: [URLQueryItem(name: "page", value: String(page))]
        )
        let listing = try JSONDecoder().decode(DiscourseTopicListResponse.self, from: data)
        let payload = DiscourseMapper.payload(
            source: source,
            channel: ForumChannel(id: -30_002, title: "热门", source: .linuxDo, nativeKey: "top"),
            listing: listing,
            titleOverride: "LINUX DO 热门"
        )
        let topicCount = listing.topicList?.topics.count ?? 0
        return ThreadFetchResult(
            payload: payload,
            rawText: String(decoding: data, as: UTF8.self),
            hasMore: topicCount >= 20
        )
    }

    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult {
        throw ForumProviderError.unsupported("Discourse 站点当前未接入主题收藏。")
    }

    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ForumProviderError.unsupported("请输入搜索关键词。")
        }

        let data = try await getJSON(
            path: "search/query.json",
            queryItems: [
                URLQueryItem(name: "term", value: trimmed),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
        let search = try JSONDecoder().decode(DiscourseSearchResponse.self, from: data)
        let payload = DiscourseMapper.searchPayload(source: source, query: trimmed, search: search)
        let topicCount = search.topics.count
        return ThreadFetchResult(
            payload: payload,
            rawText: String(decoding: data, as: UTF8.self),
            hasMore: topicCount >= 20
        )
    }

    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult {
        guard page == 1 else {
            throw ForumProviderError.unsupported("Discourse 主题详情暂不支持分页回帖读取。")
        }

        let data = try await getJSON(path: "t/\(tid).json")
        let thread = try LinuxDoDiscourseParser.threadDetail(from: data)
        return ThreadDetailFetchResult(
            thread: thread,
            rawText: String(decoding: data, as: UTF8.self)
        )
    }

    func addFavoriteThread(tid: Int) async throws {
        throw ForumProviderError.unsupported("Discourse 站点当前未接入主题收藏。")
    }

    func removeFavoriteThread(tid: Int) async throws {
        throw ForumProviderError.unsupported("Discourse 站点当前未接入主题收藏。")
    }

    func replyThread(
        tid: Int,
        target: ThreadReplyTarget,
        content: String,
        attachments: [ReplyAttachmentUpload]
    ) async throws {
        throw ForumProviderError.unsupported("Discourse 站点当前未接入主题回复。")
    }

    private func getJSON(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw ForumProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ForumHub/1.0 iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ForumProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 403 {
                return try await LinuxDoBrowserRequestSession.shared.fetchJSON(from: url)
            }
            throw ForumProviderError.httpStatus(httpResponse.statusCode)
        }
        return data
    }
}

enum LinuxDoDiscourseParser {
    static func threadDetail(from data: Data) throws -> ForumThread {
        let detail = try JSONDecoder().decode(DiscourseTopicDetailResponse.self, from: data)
        return DiscourseMapper.threadDetail(source: .linuxDo, detail: detail)
    }
}

private enum DiscourseMapper {
    static func channel(_ category: DiscourseCategoryDTO) -> ForumChannel {
        ForumChannel(
            id: category.id,
            title: category.name,
            source: .linuxDo,
            nativeKey: "\(category.slug)/\(category.id)"
        )
    }

    static func payload(
        source: ForumSource,
        channel: ForumChannel,
        listing: DiscourseTopicListResponse,
        titleOverride: String? = nil
    ) -> ForumPayload {
        let users = Dictionary(uniqueKeysWithValues: (listing.users ?? []).map { ($0.id, $0) })
        let categories = Dictionary(uniqueKeysWithValues: (listing.topicList?.categories ?? []).map { ($0.id, $0) })
        let topics = (listing.topicList?.topics ?? []).map { topic in
            thread(source: source, topic: topic, users: users, categories: categories, fallbackChannel: channel)
        }

        return ForumPayload(
            forum: ForumSummary(
                id: channel.id,
                title: titleOverride ?? channel.title,
                subtitle: source == .linuxDo ? "Discourse · \(channel.title)" : channel.title,
                todayPosts: 0,
                onlineUsers: topics.count,
                source: source
            ),
            channels: [],
            pinned: [],
            threads: topics
        )
    }

    static func searchPayload(source: ForumSource, query: String, search: DiscourseSearchResponse) -> ForumPayload {
        let users = Dictionary(uniqueKeysWithValues: (search.users ?? []).map { ($0.id, $0) })
        let categories = Dictionary(uniqueKeysWithValues: (search.categories ?? []).map { ($0.id, $0) })
        let threads = search.topics.map { topic in
            let fallbackChannel = ForumChannel(
                id: topic.categoryID ?? ForumChannel.linuxDoLatest.id,
                title: categories[topic.categoryID ?? 0]?.name ?? "搜索结果",
                source: .linuxDo,
                nativeKey: categories[topic.categoryID ?? 0].map { "\($0.slug)/\($0.id)" } ?? ForumChannel.linuxDoLatest.nativeKey
            )
            return thread(source: source, topic: topic, users: users, categories: categories, fallbackChannel: fallbackChannel)
        }

        return ForumPayload(
            forum: ForumSummary(
                id: -30_003,
                title: "搜索：\(query)",
                subtitle: "LINUX DO 搜索结果",
                todayPosts: 0,
                onlineUsers: threads.count,
                source: source
            ),
            channels: [],
            pinned: [],
            threads: threads
        )
    }

    static func threadDetail(source: ForumSource, detail: DiscourseTopicDetailResponse) -> ForumThread {
        let posts = detail.postStream.posts
        let users = Dictionary(uniqueKeysWithValues: (detail.details?.participants ?? []).map { ($0.id, $0) })
        let firstPost = posts.first
        let author = firstPost?.username ?? "未知作者"
        let authorAvatarURL = avatarURL(template: firstPost?.avatarTemplate, baseURL: detail.baseURL)
        let createdAt = formattedTime(firstPost?.createdAt)
        let channelTitle = detail.categoryName

        let replies = Array(posts.dropFirst()).map { post in
            let replyAvatarTemplate = post.avatarTemplate
                ?? post.userID.flatMap { users[$0]?.avatarTemplate }
            return Reply(
                id: post.id,
                sourcePostID: post.id,
                author: post.username,
                createdAt: formattedTime(post.createdAt),
                body: normalizedContent(post.cooked ?? post.raw ?? ""),
                avatarURL: avatarURL(template: replyAvatarTemplate, baseURL: detail.baseURL)
            )
        }

        return ForumThread(
            id: detail.id,
            title: detail.title,
            summary: detail.excerpt?.cleanedForumText ?? detail.title,
            author: author,
            authorAvatarURL: authorAvatarURL,
            createdAt: createdAt,
            lastReplyAt: formattedTime(detail.lastPostedAt ?? firstPost?.createdAt),
            replyCount: max(detail.postsCount - 1, replies.count),
            viewCount: detail.views ?? 0,
            body: normalizedContent(firstPost?.cooked ?? firstPost?.raw ?? ""),
            replies: replies,
            source: source,
            channelID: detail.categoryID,
            channelTitle: channelTitle
        )
    }

    static func thread(
        source: ForumSource,
        topic: DiscourseTopicDTO,
        users: [Int: DiscourseUserDTO],
        categories: [Int: DiscourseCategoryDTO],
        fallbackChannel: ForumChannel
    ) -> ForumThread {
        let primaryPosterID = topic.posters?.first?.userID ?? topic.posters?.first?.descriptionUserID
        let user = primaryPosterID.flatMap { users[$0] }
        let channelID = topic.categoryID ?? fallbackChannel.id
        let category = categories[channelID]
        let channelTitle = category?.name ?? fallbackChannel.title
        let summary = topic.excerpt?.cleanedForumText ?? topic.title

        return ForumThread(
            id: topic.id,
            title: topic.title,
            summary: summary,
            author: user?.username ?? topic.lastPosterUsername ?? "未知作者",
            authorAvatarURL: avatarURL(template: user?.avatarTemplate, baseURL: nil),
            createdAt: formattedTime(topic.createdAt),
            lastReplyAt: formattedTime(topic.bumpedAt ?? topic.lastPostedAt ?? topic.createdAt),
            replyCount: max((topic.postsCount ?? 1) - 1, 0),
            viewCount: topic.views ?? 0,
            body: summary,
            replies: [],
            source: source,
            channelID: channelID,
            channelTitle: channelTitle
        )
    }

    static func formattedTime(_ rawValue: String?) -> String {
        guard let rawValue, !rawValue.isEmpty else { return "" }
        if let date = iso8601Date(from: rawValue) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "MM-dd HH:mm"
            return formatter.string(from: date)
        }
        return rawValue
    }

    static func normalizedContent(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"<img[^>]+src=[\"']([^\"']+)[\"'][^>]*>"#,
                with: "\n[图片] $1\n",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
            .cleanedForumText
    }

    static func avatarURL(template: String?, baseURL: URL?) -> URL? {
        guard let template, !template.isEmpty else { return nil }
        let rendered = template.replacingOccurrences(of: "{size}", with: "120")
        if rendered.hasPrefix("http://") || rendered.hasPrefix("https://") {
            return URL(string: rendered)
        }
        if rendered.hasPrefix("//") {
            return URL(string: "https:\(rendered)")
        }
        if rendered.hasPrefix("/") {
            if let baseURL {
                return URL(string: rendered, relativeTo: baseURL)?.absoluteURL
            }
            return URL(string: "https://linux.do\(rendered)")
        }
        return URL(string: rendered)
    }

    private static func iso8601Date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }
}

private struct DiscourseSiteResponse: Decodable {
    let categories: [DiscourseCategoryDTO]
}

private struct DiscourseTopicListResponse: Decodable {
    let users: [DiscourseUserDTO]?
    let topicList: DiscourseTopicListDTO?

    enum CodingKeys: String, CodingKey {
        case users
        case topicList = "topic_list"
    }
}

private struct DiscourseTopicListDTO: Decodable {
    let topics: [DiscourseTopicDTO]
    let categories: [DiscourseCategoryDTO]?
}

private struct DiscourseSearchResponse: Decodable {
    let topics: [DiscourseTopicDTO]
    let users: [DiscourseUserDTO]?
    let categories: [DiscourseCategoryDTO]?
}

private struct DiscourseTopicDetailResponse: Decodable {
    let id: Int
    let title: String
    let postsCount: Int
    let views: Int?
    let categoryID: Int?
    let excerpt: String?
    let lastPostedAt: String?
    let details: DiscourseTopicParticipantsDTO?
    let postStream: DiscoursePostStreamDTO
    let baseURL: URL?
    let categoryName: String?

    enum CodingKeys: String, CodingKey {
        case id, title, views, excerpt, details
        case postsCount = "posts_count"
        case categoryID = "category_id"
        case lastPostedAt = "last_posted_at"
        case postStream = "post_stream"
        case baseURL = "base_url"
        case categoryName = "category_name"
    }
}

private struct DiscourseTopicParticipantsDTO: Decodable {
    let participants: [DiscourseUserDTO]?
}

private struct DiscoursePostStreamDTO: Decodable {
    let posts: [DiscoursePostDTO]
}

private struct DiscoursePostDTO: Decodable {
    let id: Int
    let userID: Int?
    let username: String
    let createdAt: String
    let cooked: String?
    let raw: String?
    let avatarTemplate: String?

    enum CodingKeys: String, CodingKey {
        case id, username, cooked, raw
        case userID = "user_id"
        case createdAt = "created_at"
        case avatarTemplate = "avatar_template"
    }
}

private struct DiscourseTopicDTO: Decodable {
    let id: Int
    let title: String
    let excerpt: String?
    let postsCount: Int?
    let views: Int?
    let createdAt: String?
    let bumpedAt: String?
    let lastPostedAt: String?
    let lastPosterUsername: String?
    let categoryID: Int?
    let posters: [DiscoursePosterDTO]?

    enum CodingKeys: String, CodingKey {
        case id, title, excerpt, views, posters
        case postsCount = "posts_count"
        case createdAt = "created_at"
        case bumpedAt = "bumped_at"
        case lastPostedAt = "last_posted_at"
        case lastPosterUsername = "last_poster_username"
        case categoryID = "category_id"
    }
}

private struct DiscoursePosterDTO: Decodable {
    let userID: Int?
    let descriptionUserID: Int?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case descriptionUserID = "description_user_id"
    }
}

private struct DiscourseUserDTO: Decodable {
    let id: Int
    let username: String
    let avatarTemplate: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case avatarTemplate = "avatar_template"
    }
}

private struct DiscourseCategoryDTO: Decodable {
    let id: Int
    let name: String
    let slug: String
    let readRestricted: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case readRestricted = "read_restricted"
    }
}
