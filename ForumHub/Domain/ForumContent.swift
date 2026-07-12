import Foundation

struct ForumContentBlock: Identifiable, Equatable {
    enum Content: Equatable {
        case text(String)
        case image(URL)
        case smile(NGAForumSmile)
        case quote(ForumQuoteBlock)
    }

    let id: Int
    let content: Content
}

struct NGAForumSmile: Equatable {
    let name: String
    let url: URL

    init?(markup: String) {
        let pattern = #"^\[s:([a-zA-Z0-9_]+):([^\]\r\n]+)\]$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: markup, range: NSRange(markup.startIndex..<markup.endIndex, in: markup)),
              let groupRange = Range(match.range(at: 1), in: markup),
              let nameRange = Range(match.range(at: 2), in: markup)
        else {
            return nil
        }

        let group = String(markup[groupRange])
        name = String(markup[nameRange])
        guard let filename = Self.filenames[group]?[name],
              let url = URL(string: "https://img4.nga.178.com/ngabbs/post/smile/\(filename)")
        else {
            return nil
        }
        self.url = url
    }

    /// 取自 NGA `js_bbscode_core.js` 的标准 smile 表，和回复编辑器使用同一资源目录。
    private static let filenames: [String: [String: String]] = [
        "ac": [
            "blink": "ac0.png", "goodjob": "ac1.png", "上": "ac2.png", "中枪": "ac3.png",
            "偷笑": "ac4.png", "冷": "ac5.png", "凌乱": "ac6.png", "反对": "ac7.png",
            "吓": "ac8.png", "吻": "ac9.png", "呆": "ac10.png", "咦": "ac11.png",
            "哦": "ac12.png", "哭": "ac13.png", "哭1": "ac14.png", "哭笑": "ac15.png",
            "哼": "ac16.png", "喘": "ac17.png", "喷": "ac18.png", "嘲笑": "ac19.png",
            "嘲笑1": "ac20.png", "囧": "ac21.png", "委屈": "ac22.png", "心": "ac23.png",
            "忧伤": "ac24.png", "怒": "ac25.png", "怕": "ac26.png", "惊": "ac27.png",
            "愁": "ac28.png", "抓狂": "ac29.png", "抠鼻": "ac30.png", "擦汗": "ac31.png",
            "无语": "ac32.png", "晕": "ac33.png", "汗": "ac34.png", "瞎": "ac35.png",
            "羞": "ac36.png", "羡慕": "ac37.png", "花痴": "ac38.png", "茶": "ac39.png",
            "衰": "ac40.png", "计划通": "ac41.png", "赞同": "ac42.png", "闪光": "ac43.png",
            "黑枪": "ac44.png"
        ],
        "a2": [
            "goodjob": "a2_02.png", "偷笑": "a2_03.png", "怒": "a2_04.png", "诶嘿": "a2_05.png",
            "笑": "a2_07.png", "那个…": "a2_08.png", "哦嗬嗬嗬": "a2_09.png", "舔": "a2_10.png",
            "有何贵干": "a2_11.png", "病娇": "a2_12.png", "lucky": "a2_13.png", "鬼脸": "a2_14.png",
            "大哭": "a2_15.png", "冷": "a2_16.png", "哭": "a2_17.png", "妮可妮可妮": "a2_18.png",
            "惊": "a2_19.png", "poi": "a2_20.png", "恨": "a2_21.png", "囧2": "a2_22.png",
            "中枪": "a2_23.png", "囧": "a2_24.png", "你看看你": "a2_25.png", "yes": "a2_26.png",
            "doge": "a2_27.png", "自戳双目": "a2_28.png", "偷吃": "a2_30.png", "冷笑": "a2_31.png",
            "壁咚": "a2_32.png", "不活了": "a2_33.png", "不明觉厉": "a2_36.png", "jojo立": "a2_37.png",
            "jojo立2": "a2_38.png", "jojo立3": "a2_39.png", "jojo立5": "a2_40.png", "jojo立4": "a2_41.png",
            "威吓": "a2_42.png", "你已经死了": "a2_45.png", "异议": "a2_47.png", "认真": "a2_48.png",
            "你这种人…": "a2_49.png", "是在下输了": "a2_51.png", "抢镜头": "a2_52.png", "你为猴这么": "a2_53.png",
            "干杯": "a2_54.png", "干杯2": "a2_55.png"
        ],
        "ng": [
            "呲牙笑": "ng_1.png", "奸笑": "ng_2.png", "问号": "ng_3.png", "茶": "ng_4.png",
            "笑指": "ng_5.png", "燃尽": "ng_6.png", "晕": "ng_7.png", "扇笑": "ng_8.png",
            "寄": "ng_9.png", "别急": "ng_10.png", "doge": "ng_11.png", "丧": "ng_12.png",
            "汗": "ng_13.png", "叹气": "ng_15.png", "吃饼": "ng_16.png", "吃瓜": "ng_17.png",
            "吐舌": "ng_18.png", "哭": "ng_19.png", "喘": "ng_20.png", "心": "ng_21.png",
            "喷": "ng_22.png", "困": "ng_24.png", "大哭": "ng_25.png", "大惊": "ng_26.png",
            "害怕": "ng_27.png", "惊": "ng_28.png", "暴怒": "ng_30.png", "气愤": "ng_31.png",
            "热": "ng_32.png", "瓜不熟": "ng_33.png", "瞎": "ng_34.png", "色": "ng_35.png",
            "斜眼": "ng_37.png", "问号大": "ng_38.png"
        ]
    ]
}

struct ForumQuoteBlock: Equatable {
    let author: String
    let createdAt: String
    let body: String
}

enum ForumContentParser {
    private static let tokenPattern = #"(?ms)\[引用 author="(.*?)" time="(.*?)"\](.*?)\[/引用\]|(?:\[图片\]\s*|\[img(?:=[^\]]+)?\]\s*)((?:https?:)?//[^\s\[\]<>"']+|\.?/[^\s\[\]<>"']+)(?:\s*\[/img\])?|\[s:[a-zA-Z0-9_]+:[^\]\r\n]+\]"#
    private static let expression = try? NSRegularExpression(pattern: tokenPattern)
    private static let legacyLeadingQuotePattern = #"(?ms)\AReply(?: to Reply)? Post by (.*?) \((.*?)\)\s*(.*)\z"#
    private static let legacyLeadingQuoteExpression = try? NSRegularExpression(pattern: legacyLeadingQuotePattern)
    private static let cache = NSCache<NSString, ForumContentBlockArrayBox>()

    static func parse(_ text: String) -> [ForumContentBlock] {
        let cacheKey = text as NSString
        if let cachedBlocks = cache.object(forKey: cacheKey)?.blocks {
            return cachedBlocks
        }

        if let legacyBlocks = parseLegacyLeadingQuote(in: text) {
            cache.setObject(ForumContentBlockArrayBox(legacyBlocks), forKey: cacheKey)
            return legacyBlocks
        }

        guard let expression else {
            return text.isEmpty ? [] : [ForumContentBlock(id: 0, content: .text(text))]
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = expression.matches(in: text, range: fullRange)
        guard !matches.isEmpty else {
            let blocks = text.isEmpty ? [] : [ForumContentBlock(id: 0, content: .text(text))]
            cache.setObject(ForumContentBlockArrayBox(blocks), forKey: cacheKey)
            return blocks
        }

        var blocks: [ForumContentBlock] = []
        var cursor = text.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }

            appendText(String(text[cursor..<matchRange.lowerBound]), to: &blocks)

            if let authorRange = Range(match.range(at: 1), in: text),
               let timeRange = Range(match.range(at: 2), in: text),
               let bodyRange = Range(match.range(at: 3), in: text) {
                blocks.append(
                    ForumContentBlock(
                        id: blocks.count,
                        content: .quote(
                            ForumQuoteBlock(
                                author: String(text[authorRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                                createdAt: String(text[timeRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                                body: String(text[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        )
                    )
                )
            } else if let urlRange = Range(match.range(at: 4), in: text),
                      let url = ForumImageURLResolver.resolve(String(text[urlRange])) {
                blocks.append(ForumContentBlock(id: blocks.count, content: .image(url)))
            } else if let smile = NGAForumSmile(markup: String(text[matchRange])) {
                blocks.append(ForumContentBlock(id: blocks.count, content: .smile(smile)))
            } else {
                appendText(String(text[matchRange]), to: &blocks)
            }
            cursor = matchRange.upperBound
        }

        appendText(String(text[cursor...]), to: &blocks)
        cache.setObject(ForumContentBlockArrayBox(blocks), forKey: cacheKey)
        return blocks
    }

    private static func appendText(_ text: String, to blocks: inout [ForumContentBlock]) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        blocks.append(ForumContentBlock(id: blocks.count, content: .text(value)))
    }

    static func containsQuoteBlock(in text: String) -> Bool {
        parse(text).contains {
            if case .quote = $0.content {
                return true
            }
            return false
        }
    }

    private static func parseLegacyLeadingQuote(in text: String) -> [ForumContentBlock]? {
        guard let legacyLeadingQuoteExpression else { return nil }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = legacyLeadingQuoteExpression.firstMatch(in: text, range: fullRange),
              let authorRange = Range(match.range(at: 1), in: text),
              let timeRange = Range(match.range(at: 2), in: text),
              let bodyRange = Range(match.range(at: 3), in: text)
        else {
            return nil
        }

        let author = String(text[authorRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt = String(text[timeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(text[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !author.isEmpty, !body.isEmpty else { return nil }

        return [
            ForumContentBlock(
                id: 0,
                content: .quote(
                    ForumQuoteBlock(
                        author: author,
                        createdAt: createdAt,
                        body: body
                    )
                )
            )
        ]
    }
}

enum ForumImageURLResolver {
    private static let ngaImageBaseURL = "https://img.nga.178.com"
    private static let trustedNGAHosts: Set<String> = [
        "img.nga.178.com",
        "img4.nga.178.com",
        "bbs.nga.cn",
        "nga.178.com"
    ]

    static func resolve(_ rawValue: String) -> URL? {
        var value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")

        if value.hasPrefix("//") {
            value = "https:" + value
        } else if value.hasPrefix("./") {
            value = ngaImageBaseURL + "/attachments/" + String(value.dropFirst(2))
        } else if value.hasPrefix("/") {
            value = ngaImageBaseURL + value
        }

        guard var components = URLComponents(string: value),
              let host = components.host?.lowercased(),
              components.scheme == "http" || components.scheme == "https"
        else {
            return nil
        }

        if components.scheme == "http", trustedNGAHosts.contains(host) {
            components.scheme = "https"
        }
        return components.url
    }

    static func isNGAForumEmoji(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), trustedNGAHosts.contains(host) else {
            return false
        }
        return url.path.hasPrefix("/ngabbs/post/smile/")
    }
}

private final class ForumContentBlockArrayBox: NSObject {
    let blocks: [ForumContentBlock]

    init(_ blocks: [ForumContentBlock]) {
        self.blocks = blocks
    }
}
