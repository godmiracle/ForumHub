import Foundation

enum V2EXRequestBuilder {
    static func publicRequest(
        url: URL,
        accept: String,
        handlesCookies: Bool = true
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("ForumHub/1.0 iOS", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = handlesCookies
        return request
    }

    static func authenticatedAPIRequest(url: URL, token: String) throws -> URLRequest {
        guard url.scheme == "https",
              url.host?.lowercased() == "www.v2ex.com",
              url.path.hasPrefix("/api/v2/")
        else {
            throw ForumProviderError.invalidResponse
        }

        var request = publicRequest(
            url: url,
            accept: "application/json",
            handlesCookies: false
        )
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func publicNodePageRequest(
        baseURL: URL,
        nodeName: String,
        page: Int
    ) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("go").appendingPathComponent(nodeName),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "p", value: String(page))]
        guard let url = components.url else { throw ForumProviderError.invalidResponse }
        return publicRequest(
            url: url,
            accept: "text/html,application/xhtml+xml",
            handlesCookies: false
        )
    }

    static func publicRecentPageRequest(baseURL: URL, page: Int) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("recent"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "p", value: String(page))]
        guard let url = components.url else { throw ForumProviderError.invalidResponse }
        return publicRequest(
            url: url,
            accept: "text/html,application/xhtml+xml",
            handlesCookies: false
        )
    }
}

struct V2EXThreadRepository: ThreadRepository {
    let source = ForumSource.v2ex
    let capabilities = ForumCapabilities(
        supportsSearch: false,
        supportsFavorites: true,
        supportsReply: false,
        supportsReplyTargeting: false,
        supportsAuthentication: true,
        supportsFeedPagination: true
    )
    let defaultChannel = ForumChannel.v2exHot

    private let session: URLSession
    private let baseURL = URL(string: "https://www.v2ex.com/api/")!
    private let v2BaseURL = URL(string: "https://www.v2ex.com/api/v2/")!
    private let webBaseURL = URL(string: "https://www.v2ex.com/")!
    private let tokenProvider: () -> String?

    init(
        session: URLSession = .shared,
        tokenProvider: @escaping () -> String? = { try? V2EXTokenKeychainStore().loadToken() }
    ) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func fetchChannels() async throws -> [ForumChannel] {
        let fixedChannels = [ForumChannel.v2exHot]
        let data = try await get(
            path: "nodes/list.json",
            queryItems: [
                URLQueryItem(name: "fields", value: "id,name,title,topics"),
                URLQueryItem(name: "sort_by", value: "topics"),
                URLQueryItem(name: "reverse", value: "1")
            ]
        )
        let nodes = try JSONDecoder().decode([V2EXNodeDTO].self, from: data)
        let channels = nodes
            .filter { ($0.topics ?? 0) > 0 }
            .prefix(60)
            .map(V2EXMapper.channel)

        let fixedKeys = Set(fixedChannels.map(\.nativeKey))
        return fixedChannels + channels.filter { !fixedKeys.contains($0.nativeKey) }
    }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        if channel.nativeKey == "hot" {
            return try await fetchHotThreads(page: page)
        }

        if channel.nativeKey == "latest" {
            let data = try await getRecentTopics(page: page)
            let recentPage = V2EXRecentPageParser.parse(data: data)
            return ThreadFetchResult(
                payload: V2EXMapper.payload(title: channel.title, channel: channel, topics: recentPage.topics),
                rawText: String(decoding: data, as: UTF8.self),
                hasMore: recentPage.hasNextPage
            )
        }

        let data = try await getWebNodeTopics(channel.nativeKey, page: page)
        let pagePayload = V2EXRecentPageParser.parse(data: data)
        return ThreadFetchResult(
            payload: V2EXMapper.payload(title: channel.title, channel: channel, topics: pagePayload.topics),
            rawText: String(decoding: data, as: UTF8.self),
            hasMore: pagePayload.hasNextPage
        )
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult {
        guard page <= 1 else {
            let recentPageNumber = page - 1
            let data = try await getRecentTopics(page: recentPageNumber)
            let recentPage = V2EXRecentPageParser.parse(data: data)
            return ThreadFetchResult(
                payload: V2EXMapper.payload(
                    title: "V2EX 热门",
                    channel: defaultChannel,
                    topics: recentPage.topics
                ),
                rawText: String(decoding: data, as: UTF8.self),
                hasMore: recentPage.hasNextPage
            )
        }

        let data = try await get(path: "topics/hot.json")
        let topics = try V2EXTopicResponseParser.topics(from: data)
        let threads = topics.map(V2EXMapper.thread)
        let payload = ForumPayload(
            forum: ForumSummary(
                id: defaultChannel.id,
                title: "V2EX 热门",
                subtitle: "V2EX 当前热门主题",
                todayPosts: 0,
                onlineUsers: threads.count,
                source: .v2ex
            ),
            channels: [],
            pinned: [],
            threads: threads
        )
        return ThreadFetchResult(
            payload: payload,
            rawText: String(decoding: data, as: UTF8.self),
            hasMore: true
        )
    }

    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult {
        let resolvedPage = max(page, 1)
        let data = try await getAuthenticatedWebPage(
            path: "my/topics",
            queryItems: [URLQueryItem(name: "p", value: String(resolvedPage))]
        )
        let favoritePage = V2EXFavoritePageParser.parse(data: data, page: resolvedPage)
        return ThreadFetchResult(
            payload: V2EXMapper.payload(
                title: "V2EX 收藏",
                channel: defaultChannel,
                topics: favoritePage.topics
            ),
            rawText: String(decoding: data, as: UTF8.self),
            hasMore: favoritePage.hasNextPage
        )
    }

    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult {
        throw ForumProviderError.unsupported("V2EX 官方接口暂不提供全站主题搜索。")
    }

    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult {
        guard page == 1 else {
            return ThreadDetailFetchResult(
                thread: ForumThread(
                    id: tid,
                    title: "V2EX 主题 \(tid)",
                    summary: "",
                    author: "未知作者",
                    lastReplyAt: "",
                    replyCount: 0,
                    viewCount: 0,
                    body: "",
                    replies: [],
                    source: .v2ex
                ),
                rawText: "[]"
            )
        }

        async let topicData = get(
            path: "topics/show.json",
            queryItems: [URLQueryItem(name: "id", value: String(tid))]
        )
        async let replyData = get(
            path: "replies/show.json",
            queryItems: [URLQueryItem(name: "topic_id", value: String(tid))]
        )

        let (resolvedTopicData, resolvedReplyData) = try await (topicData, replyData)
        let topic = try JSONDecoder().decode([V2EXTopicDTO].self, from: resolvedTopicData).first
        guard let topic else {
            throw ForumProviderError.invalidResponse
        }
        let replies = try JSONDecoder().decode([V2EXReplyDTO].self, from: resolvedReplyData)
        let thread = V2EXMapper.threadDetail(topic: topic, replies: replies)
        return ThreadDetailFetchResult(
            thread: thread,
            rawText: String(decoding: resolvedTopicData, as: UTF8.self)
        )
    }

    func addFavoriteThread(tid: Int) async throws {
        try await updateFavorite(tid: tid, action: .add)
    }

    func removeFavoriteThread(tid: Int) async throws {
        try await updateFavorite(tid: tid, action: .remove)
    }

    func replyThread(
        tid: Int,
        target: ThreadReplyTarget,
        content: String,
        attachments: [ReplyAttachmentUpload]
    ) async throws {
        throw ForumProviderError.unsupported("V2EX 当前官方 API 未提供主题回复接口。")
    }

    private func get(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw ForumProviderError.invalidResponse }

        let request = V2EXRequestBuilder.publicRequest(
            url: url,
            accept: "application/json",
            handlesCookies: false
        )
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ForumProviderError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ForumProviderError.httpStatus(response.statusCode)
        }
        return data
    }

    private func getV2NodeTopics(_ nodeName: String, page: Int, token: String) async throws -> Data {
        let url = v2BaseURL
            .appendingPathComponent("nodes")
            .appendingPathComponent(nodeName)
            .appendingPathComponent("topics")
        return try await get(url: url, queryItems: [URLQueryItem(name: "p", value: String(page))], token: token)
    }

    private func getRecentTopics(page: Int) async throws -> Data {
        let request = try V2EXRequestBuilder.publicRecentPageRequest(baseURL: webBaseURL, page: page)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ForumProviderError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ForumProviderError.httpStatus(response.statusCode)
        }
        return data
    }

    private func getWebNodeTopics(_ nodeName: String, page: Int) async throws -> Data {
        let request = try V2EXRequestBuilder.publicNodePageRequest(
            baseURL: webBaseURL,
            nodeName: nodeName,
            page: page
        )
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ForumProviderError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ForumProviderError.httpStatus(response.statusCode)
        }
        return data
    }

    private func updateFavorite(tid: Int, action: V2EXFavoriteAction) async throws {
        let topicData = try await getAuthenticatedWebPage(path: "t/\(tid)")
        if V2EXFavoriteActionParser.isAlreadyApplied(action, threadID: tid, data: topicData) {
            return
        }
        guard let actionURL = V2EXFavoriteActionParser.actionURL(
            action,
            threadID: tid,
            data: topicData
        ) else {
            throw ForumProviderError.invalidResponse
        }

        _ = try await getAuthenticatedWebPage(url: actionURL)
        let refreshedTopicData = try await getAuthenticatedWebPage(path: "t/\(tid)")
        guard V2EXFavoriteActionParser.isAlreadyApplied(
            action,
            threadID: tid,
            data: refreshedTopicData
        ) else {
            throw ForumProviderError.invalidResponse
        }
    }

    private func getAuthenticatedWebPage(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        var components = URLComponents(
            url: webBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw ForumProviderError.invalidResponse }
        return try await getAuthenticatedWebPage(url: url)
    }

    private func getAuthenticatedWebPage(url: URL) async throws -> Data {
        guard url.scheme == "https", url.host?.lowercased() == "www.v2ex.com" else {
            throw ForumProviderError.invalidResponse
        }

        let request = V2EXRequestBuilder.publicRequest(
            url: url,
            accept: "text/html,application/xhtml+xml"
        )
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ForumProviderError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ForumProviderError.httpStatus(response.statusCode)
        }
        guard response.url?.host?.lowercased() == "www.v2ex.com",
              response.url?.path != "/signin"
        else {
            throw ForumProviderError.unsupported("请先在用户页完成 V2EX 网页登录。")
        }
        return data
    }

    private func get(url: URL, queryItems: [URLQueryItem], token: String) async throws -> Data {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        guard let requestURL = components.url else { throw ForumProviderError.invalidResponse }

        let request = try V2EXRequestBuilder.authenticatedAPIRequest(url: requestURL, token: token)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ForumProviderError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw ForumProviderError.unsupported("V2EX Token 已失效，请在用户页重新登录。")
            }
            throw ForumProviderError.httpStatus(response.statusCode)
        }
        return data
    }
}

enum ForumProviderError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "论坛返回了无法识别的数据。"
        case let .httpStatus(code):
            return "论坛请求失败（\(code)），请稍后重试。"
        case let .unsupported(message):
            return message
        }
    }
}

extension ForumProviderError: ForumErrorConvertible {
    var forumError: ForumError {
        switch self {
        case .invalidResponse:
            return .malformedResponse
        case let .httpStatus(statusCode):
            return ForumError.fromHTTPStatus(statusCode)
        case let .unsupported(message):
            return .unsupported(message)
        }
    }
}

enum V2EXMapper {
    static func channel(_ node: V2EXNodeDTO) -> ForumChannel {
        ForumChannel(
            id: node.id ?? stableID(node.name),
            title: node.title ?? node.name,
            source: .v2ex,
            nativeKey: node.name
        )
    }

    static func payload(
        title: String,
        channel: ForumChannel,
        topics: [V2EXTopicDTO]
    ) -> ForumPayload {
        let threads = topics.map { thread($0) }
        return ForumPayload(
            forum: ForumSummary(
                id: channel.id,
                title: title,
                subtitle: "V2EX · \(title)",
                todayPosts: 0,
                onlineUsers: threads.count,
                source: .v2ex
            ),
            channels: [channel],
            pinned: [],
            threads: threads
        )
    }

    static func thread(_ topic: V2EXTopicDTO) -> ForumThread {
        let contentDocument = contentDocument(
            rawContent: topic.content,
            renderedContent: topic.contentRendered
        )
        let body = contentDocument.bodyText
        let thread = ForumThread(
            id: topic.id,
            title: topic.title ?? "V2EX 主题 \(topic.id)",
            summary: String(body.prefix(180)),
            author: topic.member?.username ?? "未知作者",
            authorAvatarURL: avatarURL(from: topic.member?.avatarNormal),
            createdAt: formattedTime(topic.created),
            lastReplyAt: formattedTime(topic.lastTouched ?? topic.created),
            createdAtDate: date(topic.created),
            lastReplyAtDate: date(topic.lastTouched ?? topic.created),
            replyCount: topic.replies ?? 0,
            viewCount: 0,
            body: body,
            contentDocument: contentDocument,
            replies: [],
            source: .v2ex
        )
        guard let node = topic.node else { return thread }
        return thread.withChannel(channel(node))
    }

    static func threadDetail(topic: V2EXTopicDTO, replies: [V2EXReplyDTO]) -> ForumThread {
        let summary = thread(topic)
        let mappedCandidates = replies.enumerated().map { index, reply in
            let referenceSource = reply.content ?? reply.contentRendered ?? ""
            let contentDocument = contentDocument(
                rawContent: reply.content,
                renderedContent: reply.contentRendered
            )
            return V2EXMappedReplyCandidate(
                reply: Reply(
                    id: reply.id,
                    sourcePostID: reply.id,
                    author: reply.member?.username ?? "未知作者",
                    createdAt: formattedTime(reply.created),
                    body: contentDocument.bodyText,
                    contentDocument: contentDocument,
                    avatarURL: avatarURL(from: reply.member?.avatarNormal),
                    floorNumber: index + 1
                ),
                reference: V2EXReplyReferenceExtractor.extract(from: referenceSource)
            )
        }
        let mappedReplies = V2EXReplyRelationshipResolver.resolve(mappedCandidates)
        return ForumThread(
            id: summary.id,
            title: summary.title,
            summary: summary.summary,
            author: summary.author,
            authorAvatarURL: summary.authorAvatarURL,
            createdAt: summary.createdAt,
            lastReplyAt: summary.lastReplyAt,
            createdAtDate: summary.createdAtDate,
            lastReplyAtDate: summary.lastReplyAtDate,
            replyCount: max(summary.replyCount, mappedReplies.count),
            viewCount: 0,
            body: summary.body,
            contentDocument: summary.contentDocument,
            replies: mappedReplies,
            source: .v2ex,
            channelID: summary.channelID,
            channelTitle: summary.channelTitle
        )
    }

    static func decodeTopics(_ data: Data) throws -> [ForumThread] {
        try JSONDecoder().decode([V2EXTopicDTO].self, from: data).map { thread($0) }
    }

    private static func contentDocument(
        rawContent: String?,
        renderedContent: String?
    ) -> ForumPostDocument {
        if let renderedContent,
           !renderedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return V2EXHTMLContentParser.parse(renderedContent)
        }
        return .plainText(rawContent ?? "")
    }

    private static func formattedTime(_ timestamp: Int?) -> String {
        guard let timestamp else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static func date(_ timestamp: Int?) -> Date? {
        timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    private static func stableID(_ value: String) -> Int {
        value.utf8.reduce(2_166_136_261) { hash, byte in
            (hash ^ Int(byte)) &* 16_777_619
        } & 0x7fff_ffff
    }

    private static func avatarURL(from value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            return URL(string: "https:\(value)")
        }
        if value.hasPrefix("/") {
            return URL(string: "https://www.v2ex.com\(value)")
        }
        return URL(string: value)
    }
}

enum V2EXHTMLContentParser {
    private static let baseURL = URL(string: "https://www.v2ex.com/")!

    static func parse(_ html: String) -> ForumPostDocument {
        guard let imageExpression = try? NSRegularExpression(
            pattern: #"(?is)<img\b[^>]*\b(?:src|data-src|data-original)\s*=\s*['\"]([^'\"]+)['\"][^>]*>"#
        ) else {
            return .plainText(html.cleanedForumText)
        }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = imageExpression.matches(in: html, range: fullRange)
        var blocks: [ForumContentBlock] = []
        var diagnostics: [ForumContentDiagnostic] = []
        var cursor = html.startIndex

        func appendText(_ fragment: Substring) {
            let text = normalizedText(String(fragment))
            guard !text.isEmpty else { return }
            blocks.append(ForumContentBlock(id: blocks.count, content: .text(text)))
        }

        for match in matches {
            guard let matchRange = Range(match.range, in: html),
                  let sourceRange = Range(match.range(at: 1), in: html)
            else { continue }

            appendText(html[cursor..<matchRange.lowerBound])
            let rawSource = String(html[sourceRange]).decodedHTMLEntities
            if let url = resolvedImageURL(rawSource) {
                blocks.append(ForumContentBlock(id: blocks.count, content: .image(url)))
            } else {
                blocks.append(ForumContentBlock(id: blocks.count, content: .unsupported("[图片] \(rawSource)")))
                diagnostics.append(
                    ForumContentDiagnostic(
                        code: .malformedMarkup,
                        severity: .warning,
                        safeMessage: "V2EX rendered content contained an invalid image URL."
                    )
                )
            }
            cursor = matchRange.upperBound
        }

        appendText(html[cursor..<html.endIndex])
        let representation = ForumContentRepresentation(
            origin: .remote(.v2ex),
            rawMarkup: html,
            markupFormat: .html,
            sourceURL: baseURL,
            parserVersion: 1
        )
        let fallbackText = ForumContentProjector.plainText(from: blocks)
        return ForumPostDocument(
            rawMarkup: html,
            fallbackText: fallbackText,
            markupFormat: .html,
            sourceURL: baseURL,
            representations: [representation],
            blocks: blocks,
            diagnostics: diagnostics,
            quality: blocks.isEmpty ? .unusable : .valid
        )
    }

    private static func normalizedText(_ html: String) -> String {
        html
            .replacingOccurrences(
                of: #"(?i)<br\s*/?>"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)</?(?:p|div|li|blockquote|pre|h[1-6])(?:\s+[^>]*)?>"#,
                with: "\n",
                options: .regularExpression
            )
            .cleanedForumText
    }

    private static func resolvedImageURL(_ rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            return URL(string: "https:\(value)")
        }
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }
}

struct V2EXReplyReference: Equatable {
    let mentionedUsernames: [String]
    let referencedFloors: [Int]
    let leadingPrefix: String?
}

struct V2EXMappedReplyCandidate {
    let reply: Reply
    let reference: V2EXReplyReference
}

enum V2EXReplyReferenceExtractor {
    static func extract(from rawContent: String) -> V2EXReplyReference {
        let usernames = uniqueUsernames(
            matches(in: rawContent, pattern: #"@([A-Za-z0-9]+)"#).map(\.value)
        )
        let floors = matches(in: rawContent, pattern: #"#(\d+)"#).compactMap { Int($0.value) }
        let leadingPrefix = leadingPrefix(in: rawContent)
        return V2EXReplyReference(
            mentionedUsernames: usernames,
            referencedFloors: floors,
            leadingPrefix: leadingPrefix
        )
    }

    private static func uniqueUsernames(_ usernames: [String]) -> [String] {
        var seen: Set<String> = []
        return usernames.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func matches(in value: String, pattern: String) -> [(value: String, range: Range<String.Index>)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: value)
            else { return nil }
            return (String(value[captureRange]), captureRange)
        }
    }

    private static func leadingPrefix(in value: String) -> String? {
        let pattern = #"^\s*@[A-Za-z0-9]+(?:\s+#\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value)
        else { return nil }
        return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum V2EXReplyRelationshipResolver {
    static func resolve(_ candidates: [V2EXMappedReplyCandidate]) -> [Reply] {
        var priorReplyByFloor: [Int: Reply] = [:]
        var nearestPriorReplyByAuthor: [String: Reply] = [:]
        var resolved: [Reply] = []

        for candidate in candidates {
            let reply = candidate.reply
            var conversation: ReplyConversation?
            let usernames = candidate.reference.mentionedUsernames
            let explicitMatches = candidate.reference.referencedFloors.compactMap { floor -> (Reply, String, Int)? in
                guard let parent = priorReplyByFloor[floor],
                      let username = usernames.first(where: {
                          parent.author.caseInsensitiveCompare($0) == .orderedSame
                      })
                else { return nil }
                return (parent, username, floor)
            }
            let uniqueExplicitMatches = Dictionary(
                explicitMatches.map { ($0.0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values

            if uniqueExplicitMatches.count == 1,
               let (parent, username, floor) = uniqueExplicitMatches.first {
                conversation = ReplyConversation(
                    parentReplyID: parent.id,
                    referencedUsername: username,
                    referencedFloor: floor,
                    resolution: .explicitFloorAndAuthor,
                    verifiedLeadingPrefix: usernames.count == 1
                        ? candidate.reference.leadingPrefix
                        : nil
                )
            } else if usernames.count == 1,
                      candidate.reference.referencedFloors.isEmpty,
                      let username = usernames.first,
                      let parent = nearestPriorReplyByAuthor[username.lowercased()] {
                conversation = ReplyConversation(
                    parentReplyID: parent.id,
                    referencedUsername: username,
                    referencedFloor: nil,
                    resolution: .nearestPreviousAuthor,
                    verifiedLeadingPrefix: candidate.reference.leadingPrefix
                )
            } else if usernames.count == 1,
                      let username = usernames.first,
                      let floor = candidate.reference.referencedFloors.first,
                      floor < (reply.floorNumber ?? Int.max),
                      priorReplyByFloor[floor] != nil,
                      let parent = nearestPriorReplyByAuthor[username.lowercased()] {
                conversation = ReplyConversation(
                    parentReplyID: parent.id,
                    referencedUsername: username,
                    referencedFloor: floor,
                    resolution: .floorAuthorMismatchFallback,
                    verifiedLeadingPrefix: nil
                )
            }

            let resolvedReply = reply.replacingConversation(with: conversation)
            resolved.append(resolvedReply)
            if let floor = reply.floorNumber {
                priorReplyByFloor[floor] = resolvedReply
            }
            nearestPriorReplyByAuthor[reply.author.lowercased()] = resolvedReply
        }

        return resolved
    }
}

struct V2EXNodeDTO: Decodable {
    let id: Int?
    let name: String
    let title: String?
    let topics: Int?
}

struct V2EXMemberDTO: Decodable {
    let id: Int?
    let username: String
    let avatarNormal: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case avatarNormal = "avatar_normal"
    }
}

struct V2EXTopicDTO: Decodable {
    let id: Int
    let title: String?
    let content: String?
    let contentRendered: String?
    let replies: Int?
    let created: Int?
    let lastTouched: Int?
    let member: V2EXMemberDTO?
    let node: V2EXNodeDTO?

    init(
        id: Int,
        title: String?,
        content: String?,
        contentRendered: String?,
        replies: Int?,
        created: Int?,
        lastTouched: Int?,
        member: V2EXMemberDTO?,
        node: V2EXNodeDTO? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.contentRendered = contentRendered
        self.replies = replies
        self.created = created
        self.lastTouched = lastTouched
        self.member = member
        self.node = node
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, replies, created, member, node
        case contentRendered = "content_rendered"
        case lastTouched = "last_touched"
    }
}

struct V2EXReplyDTO: Decodable {
    let id: Int
    let content: String?
    let contentRendered: String?
    let created: Int?
    let member: V2EXMemberDTO?

    enum CodingKeys: String, CodingKey {
        case id, content, created, member
        case contentRendered = "content_rendered"
    }
}

enum V2EXTopicResponseParser {
    static func topics(from data: Data) throws -> [V2EXTopicDTO] {
        let decoder = JSONDecoder()
        if let topics = try? decoder.decode([V2EXTopicDTO].self, from: data) {
            return topics
        }
        if let envelope = try? decoder.decode(V2EXTopicsEnvelope.self, from: data) {
            return envelope.result
        }
        throw ForumProviderError.invalidResponse
    }
}

private struct V2EXTopicsEnvelope: Decodable {
    let result: [V2EXTopicDTO]
}

struct V2EXRecentPage {
    let topics: [V2EXTopicDTO]
    let hasNextPage: Bool
}

enum V2EXFavoriteAction {
    case add
    case remove

    fileprivate var pathComponent: String {
        switch self {
        case .add: return "favorite"
        case .remove: return "unfavorite"
        }
    }

    fileprivate var appliedPageAction: V2EXFavoriteAction {
        switch self {
        case .add: return .remove
        case .remove: return .add
        }
    }
}

enum V2EXFavoriteActionParser {
    private static let baseURL = URL(string: "https://www.v2ex.com/")!

    static func actionURL(
        _ action: V2EXFavoriteAction,
        threadID: Int,
        data: Data
    ) -> URL? {
        let html = String(decoding: data, as: UTF8.self)
        let hrefs = html.matches(
            pattern: #"href=["']([^"']+)["']"#,
            options: .caseInsensitive
        ).map { $0[1].replacingOccurrences(of: "&amp;", with: "&") }

        return hrefs.compactMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
            .first { url in
                guard url.scheme == "https",
                      url.host?.lowercased() == "www.v2ex.com",
                      url.path == "/\(action.pathComponent)/topic/\(threadID)",
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                else { return false }
                return components.queryItems?.contains {
                    $0.name == "once" && !($0.value ?? "").isEmpty
                } == true
            }
    }

    static func isAlreadyApplied(
        _ action: V2EXFavoriteAction,
        threadID: Int,
        data: Data
    ) -> Bool {
        actionURL(action.appliedPageAction, threadID: threadID, data: data) != nil
    }
}

enum V2EXFavoritePageParser {
    static func parse(data: Data, page: Int) -> V2EXRecentPage {
        let parsed = V2EXRecentPageParser.parse(data: data)
        let html = String(decoding: data, as: UTF8.self)
        let nextPage = max(page, 1) + 1
        let hasNextPage = parsed.hasNextPage || html.range(
            of: #"href=["']/my/topics\?p=\#(nextPage)["']"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        return V2EXRecentPage(topics: parsed.topics, hasNextPage: hasNextPage)
    }
}

enum V2EXRecentPageParser {
    static func parse(data: Data) -> V2EXRecentPage {
        let html = String(decoding: data, as: UTF8.self)
        let topics = topicSections(in: html).compactMap { section in
            parseTopic(section)
        }
        let hasNextPage = html.range(
            of: #"\btitle\s*=\s*["']Next Page["']"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        return V2EXRecentPage(topics: topics, hasNextPage: hasNextPage)
    }

    private static func topicSections(in html: String) -> [String] {
        let topicsNode = html.range(
            of: #"<div\b[^>]*\bid\s*=\s*["']TopicsNode["'][^>]*>"#,
            options: [.regularExpression, .caseInsensitive]
        )
        let topicsHTML = topicsNode.map { String(html[$0.upperBound...]) } ?? html
        let requiresTopicIDClass = topicsNode != nil
        let source = topicsHTML as NSString
        guard let divPattern = try? NSRegularExpression(
            pattern: #"<div\b([^>]*)>"#,
            options: [.caseInsensitive]
        ) else { return [] }

        let itemStarts = divPattern.matches(
            in: topicsHTML,
            range: NSRange(location: 0, length: source.length)
        ).compactMap { match -> Int? in
            guard match.numberOfRanges > 1 else { return nil }
            let attributes = source.substring(with: match.range(at: 1))
            guard let classValue = attributes.matches(
                pattern: #"\bclass\s*=\s*["']([^"']+)["']"#,
                options: .caseInsensitive
            ).first?[1] else { return nil }
            let classTokens = classValue.split(whereSeparator: \.isWhitespace).map(String.init)
            guard classTokens.contains(where: { $0.caseInsensitiveCompare("cell") == .orderedSame }) else {
                return nil
            }
            if requiresTopicIDClass {
                guard classTokens.contains(where: {
                    $0.range(of: #"^t_\d+$"#, options: .regularExpression) != nil
                }) else { return nil }
            } else {
                guard classTokens.contains(where: { $0.caseInsensitiveCompare("item") == .orderedSame }) else {
                    return nil
                }
            }
            return match.range.location
        }

        return itemStarts.enumerated().map { index, start in
            let end = index + 1 < itemStarts.count ? itemStarts[index + 1] : source.length
            return source.substring(with: NSRange(location: start, length: end - start))
        }
    }

    private static func parseTopic(_ value: String) -> V2EXTopicDTO? {
        let containerTopicID = value.matches(
            pattern: #"^<div\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ).first?[1].matches(
            pattern: #"\bt_(\d+)\b"#,
            options: .caseInsensitive
        ).first.flatMap { Int($0[1]) }
        let anchors = value.matches(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        guard let topicAnchor = anchors.compactMap({ anchor -> (Int, String)? in
            guard let href = anchor[1].matches(
                pattern: #"\bhref\s*=\s*[\"']([^\"']+)[\"']"#,
                options: .caseInsensitive
            ).first?[1],
                  let match = href.matches(
                    pattern: #"^/t/(\d+)(?:[/?#]|$)"#,
                    options: .caseInsensitive
                  ).first,
                  let id = Int(match[1]),
                  containerTopicID == nil || containerTopicID == id
            else { return nil }
            return (id, anchor[2])
        }).first
        else { return nil }

        let avatarTag = value.matches(
            pattern: #"<img[^>]*class="avatar"[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ).first?[0]
        let author = avatarTag?.matches(
            pattern: #"alt="([^"]+)""#,
            options: .caseInsensitive
        ).first?[1].cleanedForumText
            ?? value.matches(pattern: #"/member/([A-Za-z0-9_-]+)"#).first?[1]
            ?? "未知作者"
        let avatar = avatarTag?.matches(
            pattern: #"src="([^"]+)""#,
            options: .caseInsensitive
        ).first?[1]
        let replyCount = value.matches(
            pattern: #"class="count_(?:livid|orange)"[^>]*>(\d+)</a>"#,
            options: .caseInsensitive
        ).first.flatMap { Int($0[1]) } ?? 0
        let node = anchors.compactMap { anchor -> V2EXNodeDTO? in
            guard let href = anchor[1].matches(
                pattern: #"\bhref\s*=\s*[\"']([^\"']+)[\"']"#,
                options: .caseInsensitive
            ).first?[1],
                  let match = href.matches(
                    pattern: #"^/go/([^/?#]+)(?:[/?#]|$)"#,
                    options: .caseInsensitive
                  ).first
            else { return nil }
            let name = match[1].removingPercentEncoding ?? match[1]
            let title = anchor[2].cleanedForumText
            return V2EXNodeDTO(
                id: nil,
                name: name,
                title: title.isEmpty ? name : title,
                topics: nil
            )
        }.first

        return V2EXTopicDTO(
            id: topicAnchor.0,
            title: topicAnchor.1.cleanedForumText,
            content: nil,
            contentRendered: nil,
            replies: replyCount,
            created: nil,
            lastTouched: nil,
            member: V2EXMemberDTO(id: nil, username: author, avatarNormal: avatar),
            node: node
        )
    }
}
