import Foundation

enum NGAImageURLResolver {
    private static let imageBaseURL = "https://img.nga.178.com"
    private static let trustedHosts: Set<String> = [
        "img.nga.178.com", "img4.nga.178.com", "bbs.nga.cn", "nga.178.com"
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
            value = imageBaseURL + "/attachments/" + String(value.dropFirst(2))
        } else if value.hasPrefix("/") {
            value = imageBaseURL + value
        }
        guard var components = URLComponents(string: value),
              let host = components.host?.lowercased(),
              components.scheme == "http" || components.scheme == "https"
        else { return nil }
        if components.scheme == "http", trustedHosts.contains(host) {
            components.scheme = "https"
        }
        return components.url
    }

    static func isForumEmoji(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), trustedHosts.contains(host) else { return false }
        return url.path.hasPrefix("/ngabbs/post/smile/")
    }
}
