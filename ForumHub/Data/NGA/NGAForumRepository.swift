import Foundation
import CoreFoundation

protocol ThreadRepository {
    var source: ForumSource { get }
    var capabilities: ForumCapabilities { get }
    var defaultChannel: ForumChannel { get }
    func fetchChannels() async throws -> [ForumChannel]
    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult
    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult
    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult
    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult
    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult
    func addFavoriteThread(tid: Int) async throws
    func removeFavoriteThread(tid: Int) async throws
    func replyThread(
        tid: Int,
        target: ThreadReplyTarget,
        content: String,
        attachments: [ReplyAttachmentUpload]
    ) async throws
}

struct NGALiveThreadRepository: ThreadRepository {
    let source = ForumSource.nga
    let capabilities = ForumCapabilities(
        supportsSearch: true,
        supportsFavorites: true,
        supportsReply: true,
        supportsReplyTargeting: true,
        supportsAuthentication: true,
        supportsFeedPagination: true,
        threadPaginationStyle: .numbered(pageSize: 20),
        supportsImageUpload: true,
        supportsWebFallback: true,
        requiresImageReferer: true
    )
    let defaultChannel = ForumChannel.defaultForum

    func fetchChannels() async throws -> [ForumChannel] {
        let attempts: [(URL, [String: String])] = [
            (
                URL(string: "https://bbs.nga.cn/app_api.php?__lib=favorforum&__act=sync")!,
                ["_v": "2", "__output": "14"]
            ),
            (
                URL(string: "https://bbs.nga.cn/app_api.php?__lib=home&__act=category")!,
                ["_v": "2", "__output": "14"]
            ),
            (
                URL(string: "https://bbs.nga.cn/app_api.php?__lib=home&__act=tagforums")!,
                ["_v": "2", "__output": "14"]
            )
        ]

        var collected: [ForumChannel] = []

        for (url, form) in attempts {
            do {
                let (data, rawText) = try await post(url: url, form: form)
                let channels = ForumChannelParser.parse(data: data, fallbackText: rawText)
                collected.append(contentsOf: channels)
            } catch {
                continue
            }
        }

        let unique = collected.uniquedByChannelID()
        if unique.isEmpty {
            throw NGARequestError.unparsedResponse("没有从收藏版块或首页分类接口解析到版面。")
        }

        return unique
    }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        let fid = channel.id
        let url = URL(string: "https://bbs.nga.cn/app_api.php?__lib=subject&__act=list")!
        let (data, rawText) = try await post(
            url: url,
            form: [
                "fid": "\(fid)",
                "page": "\(page)",
                "_v": "2",
                "__output": "14"
            ]
        )
        let apiPayload = ForumPayloadParser.parse(data: data, fallbackText: rawText, fid: fid)

        if let apiPayload, !apiPayload.threads.isEmpty {
            return ThreadFetchResult(payload: apiPayload, rawText: rawText)
        }

        try Task.checkCancellation()
        let webResult = try await fetchWebForum(fid: fid, page: page)
        let combinedRawText = """
        app_api.php 没有解析出主题，已尝试网页兜底。

        ===== app_api.php =====
        \(rawText)

        ===== thread.php =====
        \(webResult.rawText)
        """
        return ThreadFetchResult(payload: webResult.payload, rawText: combinedRawText)
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult {
        let attempts: [(String, URL, [String: String])] = [
            (
                "home/recmthreads",
                URL(string: "https://bbs.nga.cn/app_api.php?__lib=home&__act=recmthreads")!,
                ["page": "\(page)", "_v": "3", "__output": "14"]
            ),
            (
                "subject/hot",
                URL(string: "https://bbs.nga.cn/app_api.php?__lib=subject&__act=hot")!,
                ["page": "\(page)", "_v": "2", "__output": "14"]
            ),
            (
                "subject/list recommend",
                URL(string: "https://bbs.nga.cn/app_api.php?__lib=subject&__act=list")!,
                ["recommend": "1", "page": "\(page)", "_v": "2", "__output": "14"]
            )
        ]

        var rawSections: [String] = []

        for (name, url, form) in attempts {
            try Task.checkCancellation()
            do {
                let (data, rawText) = try await post(url: url, form: form)
                rawSections.append("===== \(name) =====\n\(rawText)")

                if let payload = ForumPayloadParser.parse(data: data, fallbackText: rawText, fid: -1),
                   !payload.threads.isEmpty {
                    let hotPayload = ForumPayload(
                        forum: ForumSummary(
                            id: -1,
                            title: "热门",
                            subtitle: "来自 \(name) 接口。",
                            todayPosts: 0,
                            onlineUsers: payload.threads.count
                        ),
                        channels: channelsForHot(payload.channels),
                        pinned: [],
                        threads: payload.threads
                    )
                    return ThreadFetchResult(payload: hotPayload, rawText: rawSections.joined(separator: "\n\n"))
                }
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                rawSections.append("===== \(name) error =====\n\(error.localizedDescription)")
            }
        }

        throw NGARequestError.unparsedResponse(rawSections.joined(separator: "\n\n"))
    }

    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult {
        let url = URL(string: "https://bbs.nga.cn/app_api.php?__lib=favor&__act=all")!
        let (data, rawText) = try await post(
            url: url,
            form: [
                "page": "\(page)",
                "_v": "2",
                "__output": "14"
            ]
        )
        guard let parsed = ForumPayloadParser.parse(
            data: data,
            fallbackText: rawText,
            fid: -2
        ) else {
            throw NGARequestError.unparsedResponse(rawText)
        }

        let payload = ForumPayload(
            forum: ForumSummary(
                id: -2,
                title: "我的收藏",
                subtitle: "当前 NGA 账号收藏的主题。",
                todayPosts: 0,
                onlineUsers: parsed.threads.count
            ),
            channels: [],
            pinned: [],
            threads: parsed.threads
        )
        return ThreadFetchResult(payload: payload, rawText: rawText)
    }

    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            return ThreadFetchResult(payload: searchPayload(query: query, threads: []), rawText: "")
        }

        let scopes: [(name: String, fidGroup: String?)] = [
            ("普通版面", nil),
            ("用户版面", "user")
        ]
        var threads: [ForumThread] = []
        var rawSections: [String] = []
        var lastError: Error?

        for scope in scopes {
            do {
                let result = try await searchScope(
                    query: keyword,
                    page: page,
                    fidGroup: scope.fidGroup
                )
                threads.append(contentsOf: result.threads)
                rawSections.append("===== \(scope.name) =====\n\(result.rawText)")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                rawSections.append("===== \(scope.name) error =====\n\(error.localizedDescription)")
            }
        }

        let uniqueThreads = threads.uniquedByThreadID()
        if uniqueThreads.isEmpty, let lastError, rawSections.allSatisfy({ $0.contains(" error =====") }) {
            throw lastError
        }

        return ThreadFetchResult(
            payload: searchPayload(query: keyword, threads: uniqueThreads),
            rawText: rawSections.joined(separator: "\n\n")
        )
    }

    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult {
        let url = URL(string: "https://bbs.nga.cn/app_api.php?__lib=post&__act=list")!
        let (data, rawText) = try await post(
            url: url,
            form: [
                "tid": "\(tid)",
                "page": "\(page)",
                "_v": "2",
                "__output": "14"
            ]
        )
        if let apiThread = ThreadDetailParser.parse(
            data: data,
            fallbackText: rawText,
            tid: tid,
            page: page
        ) {
            guard NGAThreadParseQuality.needsWebEnrichment(thread: apiThread, rawText: rawText) else {
                return ThreadDetailFetchResult(thread: apiThread, rawText: rawText)
            }

            do {
                let webResult = try await fetchWebThread(tid: tid, page: page, apiRawText: rawText)
                return ThreadDetailFetchResult(
                    thread: NGAThreadDetailMerger.merge(apiThread: apiThread, webThread: webResult.thread),
                    rawText: webResult.rawText
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // API data remains usable when the optional web enrichment fails.
                return ThreadDetailFetchResult(thread: apiThread, rawText: rawText)
            }
        }

        return try await fetchWebThread(tid: tid, page: page, apiRawText: rawText)
    }

    func addFavoriteThread(tid: Int) async throws {
        let url = URL(string: "https://bbs.nga.cn/nuke.php")!
        let (data, rawText) = try await post(
            url: url,
            form: [
                "__lib": "topic_favor",
                "__act": "topic_favor",
                "action": "add",
                "tid": "\(tid)",
                "__output": "14"
            ]
        )

        if let message = apiErrorMessage(data: data, fallbackText: rawText) {
            throw NGARequestError.apiMessage(message)
        }
    }

    func removeFavoriteThread(tid: Int) async throws {
        let favoritePage = try await favoritePageContainingThread(tid: tid) ?? 1
        let url = URL(string: "https://bbs.nga.cn/nuke.php")!
        let (data, rawText) = try await post(
            url: url,
            form: [
                "__lib": "topic_favor",
                "__act": "topic_favor",
                "action": "del",
                "tidarray": "\(tid)",
                "page": "\(favoritePage)",
                "__output": "14"
            ]
        )

        if let message = apiErrorMessage(data: data, fallbackText: rawText) {
            throw NGARequestError.apiMessage(message)
        }
    }

    func replyThread(
        tid: Int,
        target: ThreadReplyTarget,
        content: String,
        attachments: [ReplyAttachmentUpload]
    ) async throws {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw NGARequestError.apiMessage("回复内容不能为空。")
        }
        if case let .reply(targetReply) = target,
           targetReply.sourcePostID == nil {
            throw NGARequestError.apiMessage("当前楼层暂时缺少可回复的帖子标识。")
        }

        let context = try await fetchReplyContext(tid: tid, target: target)
        let uploadedAttachments = try await uploadAttachments(attachments, context: context)
        let url = URL(string: "https://bbs.nga.cn/post.php")!
        let composedContent = composedPostContent(trimmedContent, context: context)
        var form = NGAReplySubmissionForm.make(
            action: context.action.rawValue,
            tid: tid,
            fid: context.fid,
            content: composedContent,
            auth: context.auth
        )
        if case let .reply(targetReply) = target,
           let sourcePostID = targetReply.sourcePostID {
            form["pid"] = "\(sourcePostID)"
        }
        if !uploadedAttachments.attachments.isEmpty {
            form["attachments"] = uploadedAttachments.attachments.joined(separator: "\t")
            form["attachments_check"] = uploadedAttachments.attachmentChecks.joined(separator: "\t")
        }

        let (_, rawText) = try await post(
            url: url,
            form: form
        )

        if let message = postFailureMessage(from: rawText) {
            throw NGARequestError.apiMessage(message)
        }
    }

    private func fetchWebForum(fid: Int, page: Int) async throws -> ThreadFetchResult {
        var components = URLComponents(string: "https://bbs.nga.cn/thread.php")!
        components.queryItems = [
            URLQueryItem(name: "fid", value: "\(fid)"),
            URLQueryItem(name: "page", value: "\(page)")
        ]

        let (_, rawText) = try await get(url: components.url!)
        let payload = WebForumParser.parseForumHTML(rawText, fid: fid, page: page)
        return ThreadFetchResult(payload: payload, rawText: rawText)
    }

    private func searchScope(
        query: String,
        page: Int,
        fidGroup: String?
    ) async throws -> (threads: [ForumThread], rawText: String) {
        let apiURL = URL(string: "https://bbs.nga.cn/app_api.php?__lib=subject&__act=search")!
        var form = [
            "key": query,
            "page": "\(page)",
            "_v": "2",
            "__output": "14"
        ]
        if let fidGroup {
            form["fidgroup"] = fidGroup
        }

        do {
            let (data, rawText) = try await post(url: apiURL, form: form)
            if let message = apiErrorMessage(data: data, fallbackText: rawText) {
                throw NGARequestError.apiMessage(message)
            }
            if let payload = ForumPayloadParser.parse(
                data: data,
                fallbackText: rawText,
                fid: -3
            ), !payload.threads.isEmpty {
                return (payload.threads, rawText)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NGARequestError {
            if case .apiMessage = error {
                throw error
            }
        } catch {
            // The documented web endpoint is more stable across NGA API versions.
        }

        var components = URLComponents(string: "https://bbs.nga.cn/thread.php")!
        components.queryItems = [
            URLQueryItem(name: "key", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "__output", value: "14")
        ]
        if let fidGroup {
            components.queryItems?.append(URLQueryItem(name: "fidgroup", value: fidGroup))
        }

        let (data, rawText) = try await get(url: components.url!)
        let payload = ForumPayloadParser.parse(data: data, fallbackText: rawText, fid: -3)
        return (payload?.threads ?? [], rawText)
    }

    private func searchPayload(query: String, threads: [ForumThread]) -> ForumPayload {
        ForumPayload(
            forum: ForumSummary(
                id: -3,
                title: "搜索：\(query)",
                subtitle: "NGA 全站主题标题搜索。",
                todayPosts: 0,
                onlineUsers: threads.count
            ),
            channels: [],
            pinned: [],
            threads: threads
        )
    }

    private func fetchReplyContext(tid: Int, target: ThreadReplyTarget) async throws -> NGAReplyContext {
        let action: NGAReplyPostAction = {
            switch target {
            case .thread:
                return .reply
            case .reply:
                return .quote
            }
        }()
        var components = URLComponents(string: "https://bbs.nga.cn/post.php")!
        var queryItems = [
            URLQueryItem(name: "action", value: action.rawValue),
            URLQueryItem(name: "tid", value: "\(tid)"),
            URLQueryItem(name: "lite", value: "js")
        ]
        if case let .reply(targetReply) = target,
           let sourcePostID = targetReply.sourcePostID {
            queryItems.append(URLQueryItem(name: "pid", value: "\(sourcePostID)"))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw NGARequestError.invalidResponse
        }

        let (data, rawText) = try await get(url: url)
        guard let object = NGAJSONParser.object(from: data, fallbackText: rawText) as? [String: Any],
              let dataDictionary = object["data"] as? [String: Any],
              let fid = (dataDictionary["fid"] as? NSNumber)?.intValue
                ?? (dataDictionary["fid"] as? String).flatMap(Int.init)
        else {
            if let message = postFailureMessage(from: rawText) {
                throw NGARequestError.apiMessage(message)
            }
            throw NGARequestError.unparsedResponse(rawText)
        }

        let auth = dataDictionary["auth"] as? String
        let prefilledContent = (dataDictionary["content"] as? String)?.decodedUnicodeEscapes
        let attachURLRawValue = dataDictionary["attach_url"] as? String
        let attachURLBase = URL(string: "https://bbs.nga.cn/")
        let attachURL: URL?
        if let attachURLRawValue {
            if let absoluteURL = URL(string: attachURLRawValue), absoluteURL.scheme != nil {
                attachURL = absoluteURL
            } else if let attachURLBase {
                attachURL = URL(string: attachURLRawValue, relativeTo: attachURLBase)?.absoluteURL
            } else {
                attachURL = nil
            }
        } else {
            attachURL = nil
        }

        return NGAReplyContext(
            fid: fid,
            auth: auth,
            attachURL: attachURL,
            action: action,
            prefilledContent: prefilledContent
        )
    }

    private func composedPostContent(_ trimmedContent: String, context: NGAReplyContext) -> String {
        guard let prefilledContent = context.prefilledContent?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prefilledContent.isEmpty
        else {
            return trimmedContent
        }

        return "\(prefilledContent)\n\n\(trimmedContent)"
    }

    private func uploadAttachments(
        _ attachments: [ReplyAttachmentUpload],
        context: NGAReplyContext
    ) async throws -> NGAUploadedAttachments {
        guard !attachments.isEmpty else {
            return NGAUploadedAttachments(attachments: [], attachmentChecks: [])
        }

        guard let auth = context.auth,
              !auth.isEmpty,
              let uploadURL = context.attachURL
        else {
            throw NGARequestError.apiMessage("当前帖子暂时无法上传图片。")
        }

        var uploadedAttachmentKeys: [String] = []
        var uploadedAttachmentChecks: [String] = []

        for attachment in attachments {
            let responseText = try await uploadAttachment(
                attachment,
                uploadURL: uploadURL,
                fid: context.fid,
                auth: auth
            )
            guard let object = NGAJSONParser.object(from: Data(), fallbackText: responseText) as? [String: Any],
                  let attachmentKey = object["attachments"] as? String,
                  let attachmentCheck = object["attachments_check"] as? String,
                  !attachmentKey.isEmpty,
                  !attachmentCheck.isEmpty
            else {
                if let message = postFailureMessage(from: responseText) {
                    throw NGARequestError.apiMessage(message)
                }
                throw NGARequestError.unparsedResponse(responseText)
            }

            uploadedAttachmentKeys.append(attachmentKey)
            uploadedAttachmentChecks.append(attachmentCheck)
        }

        return NGAUploadedAttachments(
            attachments: uploadedAttachmentKeys,
            attachmentChecks: uploadedAttachmentChecks
        )
    }

    private func uploadAttachment(
        _ attachment: ReplyAttachmentUpload,
        uploadURL: URL,
        fid: Int,
        auth: String
    ) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        appendMultipartField(named: "v2", value: "1", boundary: boundary, to: &body)
        appendMultipartField(named: "fid", value: "\(fid)", boundary: boundary, to: &body)
        appendMultipartField(named: "func", value: "upload", boundary: boundary, to: &body)
        appendMultipartField(named: "auth", value: auth, boundary: boundary, to: &body)
        appendMultipartField(named: "__output", value: "14", boundary: boundary, to: &body)
        appendMultipartField(named: "__inchst", value: "UTF8", boundary: boundary, to: &body)
        appendMultipartField(
            named: "attachment_file1_url_utf8_name",
            value: percentEncode(attachment.filename),
            boundary: boundary,
            to: &body
        )
        appendMultipartField(named: "attachment_file1_dscp", value: "", boundary: boundary, to: &body)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"attachment_file1\"; filename=\"\(attachment.filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(attachment.mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(attachment.data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 NGAPrototype/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://bbs.nga.cn/post.php", forHTTPHeaderField: "Referer")

        let cookies = HTTPCookieStorage.shared.cookies(for: uploadURL) ?? []
        let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
        for (field, value) in cookieHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NGARequestError.invalidResponse
        }

        let rawText = decodeNGAData(data)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NGARequestError.httpStatus(httpResponse.statusCode, rawText)
        }

        return rawText
    }

    private func appendMultipartField(
        named name: String,
        value: String,
        boundary: String,
        to body: inout Data
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func apiErrorMessage(data: Data, fallbackText: String) -> String? {
        guard let object = NGAJSONParser.object(from: data, fallbackText: fallbackText) as? [String: Any]
        else {
            return nil
        }

        let code = (object["code"] as? NSNumber)?.intValue
            ?? (object["code"] as? String).flatMap(Int.init)
            ?? 0
        guard code != 0 else { return nil }

        if let message = object["msg"] as? String {
            let cleanedMessage = message.cleanedForumText
            if !cleanedMessage.isEmpty {
                return cleanedMessage
            }
        }

        return "NGA 暂时无法执行搜索（错误码 \(code)）。"
    }

    private func postFailureMessage(from rawText: String) -> String? {
        let normalized = rawText.cleanedForumText
        let patterns = [
            #"alert\(["']([^"']+)["']\)"#,
            #"showError\(["']([^"']+)["']\)"#,
            #"<h2[^>]*>(.*?)</h2>"#,
            #"<title>(.*?)</title>"#
        ]

        for pattern in patterns {
            if let match = rawText.matches(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ).first?[1].cleanedForumText,
               !match.isEmpty,
               !match.contains("发表回复") {
                return match
            }
        }

        let failureHints = ["错误", "失败", "权限", "登录", "发言", "回复", "发表", "灌水", "验证码"]
        if failureHints.contains(where: { normalized.contains($0) }),
           !normalized.contains("操作成功") {
            return normalized
        }

        return nil
    }

    private func favoritePageContainingThread(tid: Int) async throws -> Int? {
        for page in 1...10 {
            let result = try await fetchFavoriteThreads(page: page)
            guard let threads = result.payload?.threads, !threads.isEmpty else {
                return nil
            }

            if threads.contains(where: { $0.id == tid }) {
                return page
            }
        }

        return nil
    }

    private func fetchWebThread(tid: Int, page: Int, apiRawText: String) async throws -> ThreadDetailFetchResult {
        var components = URLComponents(string: "https://bbs.nga.cn/read.php")!
        components.queryItems = [
            URLQueryItem(name: "tid", value: "\(tid)"),
            URLQueryItem(name: "page", value: "\(page)")
        ]

        let (_, rawText) = try await get(url: components.url!)
        if let thread = WebForumParser.parseThreadHTML(rawText, tid: tid, page: page) {
            return ThreadDetailFetchResult(
                thread: thread,
                rawText: """
                app_api.php:
                \(apiRawText)

                read.php:
                \(rawText)
                """
            )
        }

        throw NGARequestError.unparsedResponse("""
        app_api.php:
        \(apiRawText)

        read.php:
        \(rawText)
        """)
    }

    private func get(url: URL) async throws -> (Data, String) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 NGAPrototype/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://bbs.nga.cn/", forHTTPHeaderField: "Referer")

        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
        for (field, value) in cookieHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NGARequestError.invalidResponse
        }

        let rawText = decodeNGAData(data)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NGARequestError.httpStatus(httpResponse.statusCode, rawText)
        }

        return (data, rawText)
    }

    private func post(url: URL, form: [String: String]) async throws -> (Data, String) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = form
            .map { key, value in "\(percentEncode(key))=\(percentEncode(value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 NGAPrototype/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://bbs.nga.cn/", forHTTPHeaderField: "Referer")

        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
        for (field, value) in cookieHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NGARequestError.invalidResponse
        }

        let rawText = decodeNGAData(data)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NGARequestError.httpStatus(httpResponse.statusCode, rawText)
        }

        return (data, rawText)
    }

    private func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private func decodeNGAData(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
            return utf8
        }

        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringConvertIANACharSetNameToEncoding("gb18030" as CFString)
        )
        let nsEncoding = String.Encoding(rawValue: cfEncoding)
        return String(data: data, encoding: nsEncoding) ?? "<无法解码响应>"
    }

    private func channelsForHot(_ parsedChannels: [ForumChannel]) -> [ForumChannel] {
        parsedChannels.isEmpty ? [.defaultForum] : parsedChannels
    }
}

private enum NGAThreadParseQuality {
    private static let rawImageMarkerPattern = #"(?i)(?:\[图片\]|\[img\]|<img\b)"#

    static func needsWebEnrichment(thread: ForumThread, rawText: String) -> Bool {
        let body = thread.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawImageCount = rawText.matches(pattern: rawImageMarkerPattern).count
        let parsedImageCount = ForumContentParser.parse(thread.body).reduce(into: 0) { count, block in
            if case .image = block.content {
                count += 1
            }
        }

        return body.isEmpty
            || (thread.replyCount > 0 && thread.replies.isEmpty)
            || parsedImageCount < rawImageCount
    }
}

enum NGAThreadDetailMerger {
    nonisolated static func merge(apiThread: ForumThread, webThread: ForumThread) -> ForumThread {
        let resolvedBody = mergedBody(apiBody: apiThread.body, webBody: webThread.body)
        // 网页正则会命中引用区块，不能把它当作楼层数据源。
        // API 已成功解析时，帖子身份、顺序和作者均必须以 API 回帖集合为准。
        let resolvedReplies = apiThread.replies

        return ForumThread(
            id: apiThread.id,
            title: apiThread.title.isUsefulForumValue ? apiThread.title : webThread.title,
            summary: apiThread.summary.isUsefulForumValue ? apiThread.summary : webThread.summary,
            author: apiThread.author.isUsefulForumValue ? apiThread.author : webThread.author,
            authorAvatarURL: apiThread.authorAvatarURL ?? webThread.authorAvatarURL,
            createdAt: apiThread.createdAt.isUsefulForumValue ? apiThread.createdAt : webThread.createdAt,
            lastReplyAt: apiThread.lastReplyAt.isUsefulForumValue ? apiThread.lastReplyAt : webThread.lastReplyAt,
            replyCount: max(apiThread.replyCount, webThread.replyCount, resolvedReplies.count),
            viewCount: max(apiThread.viewCount, webThread.viewCount),
            body: resolvedBody,
            replies: resolvedReplies,
            source: apiThread.source,
            channelID: apiThread.channelID,
            channelTitle: apiThread.channelTitle
        )
    }

    private nonisolated static func mergedBody(apiBody: String, webBody: String) -> String {
        let apiValue = apiBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let webValue = webBody.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiValue.isEmpty else { return webValue }
        guard !webValue.isEmpty else { return apiValue }

        let normalizedAPI = normalized(apiValue)
        let normalizedWeb = normalized(webValue)
        if normalizedAPI.contains(normalizedWeb) {
            return apiValue
        }
        if normalizedWeb.contains(normalizedAPI) {
            return webValue
        }

        var knownUnits = Set(contentUnits(in: apiValue).map(normalized))
        var missingUnits: [String] = []
        for unit in contentUnits(in: webValue) {
            let key = normalized(unit)
            guard !key.isEmpty,
                  !normalizedAPI.contains(key),
                  knownUnits.insert(key).inserted
            else {
                continue
            }
            missingUnits.append(unit)
        }

        guard !missingUnits.isEmpty else { return apiValue }
        return ([apiValue] + missingUnits).joined(separator: "\n")
    }

    private nonisolated static func contentUnits(in body: String) -> [String] {
        body
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .lowercased()
    }

}

private enum NGAReplyPostAction: String {
    case reply
    case quote
}

enum NGAReplySubmissionForm {
    static func make(
        action: String,
        tid: Int,
        fid: Int,
        content: String,
        auth: String?
    ) -> [String: String] {
        var form = [
            "step": "2",
            "action": action,
            "tid": "\(tid)",
            "fid": "\(fid)",
            "post_content": content,
            "lite": "js",
            "__inchst": "UTF8",
            "__output": "14"
        ]

        if let auth = auth?.trimmingCharacters(in: .whitespacesAndNewlines), !auth.isEmpty {
            form["auth"] = auth
        }
        return form
    }
}

private struct NGAReplyContext {
    let fid: Int
    let auth: String?
    let attachURL: URL?
    let action: NGAReplyPostAction
    let prefilledContent: String?
}

struct MockThreadRepository: ThreadRepository {
    let source: ForumSource
    let defaultChannel: ForumChannel

    var capabilities: ForumCapabilities {
        switch source {
        case .nga:
            ForumCapabilities(
                supportsSearch: true,
                supportsFavorites: true,
                supportsReply: true,
                supportsReplyTargeting: true,
                supportsAuthentication: true,
                supportsFeedPagination: true
            )
        case .v2ex:
            ForumCapabilities(
                supportsSearch: false,
                supportsFavorites: false,
                supportsReply: false,
                supportsReplyTargeting: false,
                supportsAuthentication: true,
                supportsFeedPagination: true
            )
        case .linuxDo:
            ForumCapabilities(
                supportsSearch: true,
                supportsFavorites: false,
                supportsReply: false,
                supportsReplyTargeting: false,
                supportsAuthentication: true,
                supportsFeedPagination: true
            )
        }
    }

    init(source: ForumSource = .nga) {
        self.source = source
        switch source {
        case .nga:
            defaultChannel = .defaultForum
        case .v2ex:
            defaultChannel = .v2exLatest
        case .linuxDo:
            defaultChannel = .linuxDoLatest
        }
    }

    func fetchChannels() async throws -> [ForumChannel] {
        switch source {
        case .nga:
            ForumPayload.mock.channels
        case .v2ex:
            [.v2exLatest, .v2exHot]
        case .linuxDo:
            [.linuxDoLatest]
        }
    }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        ThreadFetchResult(
            payload: .mock,
            rawText: #"{"items":[{"tid":90002,"subject":"SwiftUI 做论坛首页"}]}"#
        )
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult {
        let payload = ForumPayload(
            forum: ForumSummary(
                id: -1,
                title: "热门",
                subtitle: "Preview 热门数据。",
                todayPosts: 0,
                onlineUsers: ForumPayload.mock.threads.count
            ),
            channels: ForumPayload.mock.channels,
            pinned: [],
            threads: ForumPayload.mock.threads
        )
        return ThreadFetchResult(payload: payload, rawText: #"{"hot":true}"#)
    }

    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult {
        ThreadFetchResult(
            payload: ForumPayload(
                forum: ForumSummary(
                    id: -2,
                    title: "我的收藏",
                    subtitle: "Preview 收藏数据。",
                    todayPosts: 0,
                    onlineUsers: ForumPayload.mock.threads.count
                ),
                channels: [],
                pinned: [],
                threads: ForumPayload.mock.threads
            ),
            rawText: #"{"favorites":true}"#
        )
    }

    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult {
        ThreadFetchResult(
            payload: ForumPayload(
                forum: ForumSummary(
                    id: -3,
                    title: "搜索：\(query)",
                    subtitle: "Preview 搜索数据。",
                    todayPosts: 0,
                    onlineUsers: ForumPayload.mock.threads.count
                ),
                channels: [],
                pinned: [],
                threads: ForumPayload.mock.threads.filter {
                    $0.title.localizedCaseInsensitiveContains(query)
                        || $0.summary.localizedCaseInsensitiveContains(query)
                }
            ),
            rawText: #"{"search":true}"#
        )
    }

    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult {
        let thread = ForumPayload.mock.pinned.first(where: { $0.id == tid })
            ?? ForumPayload.mock.threads.first(where: { $0.id == tid })
            ?? ForumPayload.mock.threads[0]
        return ThreadDetailFetchResult(thread: thread, rawText: #"{"postusername":"CJ","subject":"Preview"}"#)
    }

    func addFavoriteThread(tid: Int) async throws {}

    func removeFavoriteThread(tid: Int) async throws {}

    func replyThread(
        tid: Int,
        target: ThreadReplyTarget,
        content: String,
        attachments: [ReplyAttachmentUpload]
    ) async throws {}
}

struct MockPagedThreadRepository: ThreadRepository {
    let source = ForumSource.nga
    let capabilities = ForumCapabilities(
        supportsSearch: true,
        supportsFavorites: true,
        supportsReply: true,
        supportsReplyTargeting: true,
        supportsAuthentication: false,
        supportsFeedPagination: true,
        threadPaginationStyle: .numbered(pageSize: 20)
    )
    let defaultChannel = ForumChannel.defaultForum
    private let detailPageSize = 20
    private let totalReplyCount = 139

    var previewThread: ForumThread {
        pagedThread(page: 1)
    }

    func fetchChannels() async throws -> [ForumChannel] {
        ForumPayload.mock.channels
    }

    func fetchForum(channel: ForumChannel, page: Int) async throws -> ThreadFetchResult {
        let primaryThread = previewThread
        let secondaryThread = ForumPayload.mock.threads[1]
        let payload = ForumPayload(
            forum: ForumPayload.mock.forum,
            channels: ForumPayload.mock.channels,
            pinned: ForumPayload.mock.pinned,
            threads: [
                primaryThread.withChannel(channel),
                secondaryThread.withChannel(channel)
            ]
        )
        return ThreadFetchResult(
            payload: payload,
            rawText: #"{"mockPagedThread":true}"#
        )
    }

    func fetchHotThreads(page: Int) async throws -> ThreadFetchResult {
        try await fetchForum(channel: defaultChannel, page: page)
    }

    func fetchFavoriteThreads(page: Int) async throws -> ThreadFetchResult {
        try await fetchForum(channel: defaultChannel, page: page)
    }

    func searchThreads(query: String, page: Int) async throws -> ThreadFetchResult {
        let result = try await fetchForum(channel: defaultChannel, page: page)
        guard let payload = result.payload else { return result }
        let filtered = payload.threads.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
        }
        return ThreadFetchResult(
            payload: ForumPayload(
                forum: payload.forum,
                channels: payload.channels,
                pinned: payload.pinned,
                threads: filtered
            ),
            rawText: result.rawText
        )
    }

    func fetchThread(tid: Int, page: Int) async throws -> ThreadDetailFetchResult {
        ThreadDetailFetchResult(
            thread: pagedThread(page: page),
            rawText: #"{"mockPagedThreadDetail":true,"page":\#(page)}"#
        )
    }

    func addFavoriteThread(tid: Int) async throws {}

    func removeFavoriteThread(tid: Int) async throws {}

    func replyThread(
        tid: Int,
        target: ThreadReplyTarget,
        content: String,
        attachments: [ReplyAttachmentUpload]
    ) async throws {}

    private func pagedThread(page: Int) -> ForumThread {
        let clampedPage = max(page, 1)
        let startFloor = ((clampedPage - 1) * detailPageSize) + 2
        let endFloor = min(startFloor + detailPageSize - 1, totalReplyCount + 1)
        let replies = (startFloor...endFloor).map { floor in
            Reply(
                id: floor,
                sourcePostID: floor,
                author: floor % 3 == 0 ? "CJ" : "测试用户\(floor)",
                createdAt: "2026-06-30 12:\(String(format: "%02d", floor % 60))",
                body: "这是第 \(floor) 楼，用于分页与下滑翻页调试。",
                floorNumber: floor
            )
        }

        return ForumThread(
            id: 991001,
            title: "分页调试主题",
            summary: "用于 UI 测试的多页帖子",
            author: "CJ",
            createdAt: "2026-06-30 12:00",
            lastReplyAt: replies.last?.createdAt ?? "2026-06-30 12:00",
            replyCount: totalReplyCount,
            viewCount: 4096,
            body: "这是一个专门给自动翻页调试准备的 mock 主楼。",
            replies: replies
        )
    }
}

struct ThreadFetchResult {
    let payload: ForumPayload?
    let rawText: String
    let hasMore: Bool

    init(payload: ForumPayload?, rawText: String, hasMore: Bool = true) {
        self.payload = payload
        self.rawText = rawText
        self.hasMore = hasMore
    }
}

struct ThreadDetailFetchResult {
    let thread: ForumThread
    let rawText: String
}

private struct NGAUploadedAttachments {
    let attachments: [String]
    let attachmentChecks: [String]
}

enum NGARequestError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)
    case unparsedResponse(String)
    case apiMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "没有拿到有效的 HTTP 响应。"
        case let .httpStatus(code, _):
            if code == 403 {
                return "NGA 暂时拒绝了请求，请登录后重试或稍后刷新。"
            }
            return "NGA 请求失败（\(code)），请稍后重试。"
        case .unparsedResponse:
            return "请求成功，但暂时无法解析内容，请稍后重试。"
        case let .apiMessage(message):
            return message
        }
    }
}

extension NGARequestError: ForumErrorConvertible {
    var forumError: ForumError {
        switch self {
        case .invalidResponse, .unparsedResponse:
            return .malformedResponse
        case let .httpStatus(statusCode, _):
            return ForumError.fromHTTPStatus(statusCode)
        case .apiMessage:
            return .sourceUnavailable
        }
    }
}
