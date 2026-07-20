import Foundation

enum NGAForumEmojiGroup: String, CaseIterable, Identifiable, Sendable {
    case ng
    case ac
    case a2
    case pt
    case dt
    case pg

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ng: "NG娘"
        case .ac: "AC娘 v1"
        case .a2: "AC娘 v2"
        case .pt: "潘斯特"
        case .dt: "外域"
        case .pg: "企鹅"
        }
    }

    var items: [NGAForumEmojiItem] {
        NGAReplyEmojiCatalog.items(in: self)
    }
}

struct NGAForumEmojiItem: Identifiable, Equatable, Sendable {
    let group: NGAForumEmojiGroup
    let displayName: String
    let filename: String

    var id: String { filename }

    var imageURL: URL {
        NGAReplyEmojiCatalog.imageURL(for: filename)
    }

    var markup: String {
        "[img]\(imageURL.absoluteString)[/img]"
    }
}

enum NGAReplyEmojiCatalog {
    private static let baseURL = URL(string: "https://img4.nga.178.com/ngabbs/post/smile/")!

    static func items(in group: NGAForumEmojiGroup) -> [NGAForumEmojiItem] {
        switch group {
        case .ng:
            numberedItems(group: group, range: 1...40, prefix: "ng_", padsToTwoDigits: false)
        case .ac:
            numberedItems(group: group, range: 1...40, prefix: "ac", padsToTwoDigits: false)
        case .a2:
            numberedItems(group: group, range: 1...40, prefix: "a2_", padsToTwoDigits: true)
        case .pt:
            numberedItems(group: group, range: 0...64, prefix: "pt", padsToTwoDigits: true)
        case .dt:
            numberedItems(group: group, range: 1...33, prefix: "dt", padsToTwoDigits: true)
        case .pg:
            numberedItems(group: group, range: 1...15, prefix: "pg", padsToTwoDigits: true)
        }
    }

    static func item(filename: String) -> NGAForumEmojiItem? {
        allItemsByFilename[filename]
    }

    static func item(imageURL: URL) -> NGAForumEmojiItem? {
        guard imageURL.host == baseURL.host,
              imageURL.path.hasPrefix(baseURL.path),
              let filename = imageURL.pathComponents.last
        else { return nil }
        return item(filename: filename)
    }

    static func imageURL(for filename: String) -> URL {
        baseURL.appendingPathComponent(filename)
    }

    private static let allItemsByFilename: [String: NGAForumEmojiItem] = {
        Dictionary(
            uniqueKeysWithValues: NGAForumEmojiGroup.allCases
                .flatMap { items(in: $0) }
                .map { ($0.filename, $0) }
        )
    }()

    private static func numberedItems(
        group: NGAForumEmojiGroup,
        range: ClosedRange<Int>,
        prefix: String,
        padsToTwoDigits: Bool
    ) -> [NGAForumEmojiItem] {
        range.map { value in
            let number = padsToTwoDigits ? String(format: "%02d", value) : String(value)
            return NGAForumEmojiItem(
                group: group,
                displayName: number,
                filename: "\(prefix)\(number).png"
            )
        }
    }
}
