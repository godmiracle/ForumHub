import Foundation

enum ForumChannelCatalogItemKind: Equatable {
    case standard
    case authoritativeChild(parentTitle: String)
}

struct ForumChannelCatalogItem: Identifiable, Equatable {
    let channel: ForumChannel
    let kind: ForumChannelCatalogItemKind

    var id: String { channel.canonicalKey }
    var title: String { channel.title }
    var searchableText: String {
        [title, channel.nativeKey, channel.canonicalNativeKey, id, contextTitle]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var contextTitle: String? {
        guard case let .authoritativeChild(parentTitle) = kind else { return nil }
        return "\(parentTitle) › 子版"
    }

    var isAuthoritativeChild: Bool {
        if case .authoritativeChild = kind { return true }
        return false
    }

    func matches(_ query: String) -> Bool {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyword.isEmpty || searchableText.localizedCaseInsensitiveContains(keyword)
    }
}

struct ForumChannelCatalog: Equatable {
    let source: ForumSource
    let items: [ForumChannelCatalogItem]
    let hasConfirmedAuthoritativeChildren: Bool

    var channels: [ForumChannel] { items.map(\.channel) }
    var authoritativeChildren: [ForumChannelCatalogItem] { items.filter(\.isAuthoritativeChild) }
    var standardChannels: [ForumChannelCatalogItem] { items.filter { !$0.isAuthoritativeChild } }

    static func build(
        source: ForumSource,
        channels: [ForumChannel],
        authoritativeDirectory: AuthoritativeChildForumDirectory?
    ) -> ForumChannelCatalog {
        var items: [ForumChannelCatalogItem] = []
        var indexByKey: [String: Int] = [:]

        for channel in channels where channel.source == source {
            guard indexByKey[channel.canonicalKey] == nil else { continue }
            indexByKey[channel.canonicalKey] = items.count
            items.append(ForumChannelCatalogItem(channel: channel, kind: .standard))
        }

        let acceptedDirectory = authoritativeDirectory.flatMap { directory in
            directory.parent.source == source ? directory : nil
        }
        if let directory = acceptedDirectory {
            for child in directory.children {
                let item = ForumChannelCatalogItem(
                    channel: child.channel,
                    kind: .authoritativeChild(parentTitle: directory.parent.title)
                )
                if let index = indexByKey[item.id] {
                    items[index] = item
                } else {
                    indexByKey[item.id] = items.count
                    items.append(item)
                }
            }
        }

        return ForumChannelCatalog(
            source: source,
            items: items,
            hasConfirmedAuthoritativeChildren: acceptedDirectory != nil
        )
    }
}
