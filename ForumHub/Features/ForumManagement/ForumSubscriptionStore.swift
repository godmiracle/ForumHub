import Foundation
import Observation

@MainActor
@Observable
final class ForumSubscriptionStore {
    static let defaultChannelOrder = [-7, 706, -7_955_747]
    static let defaultChannelIDs = Set(defaultChannelOrder)
    private static let legacyDefaultChannelIDs: Set<Int> = [722, 7, 510]

    private(set) var subscribedChannelKeys: Set<String>
    private(set) var orderedChannelKeys: [String]
    var subscribedIDs: Set<Int> {
        Set(subscribedChannelKeys.compactMap { key in
            guard key.hasPrefix("nga:") else { return nil }
            return Int(key.dropFirst(4))
        })
    }
    private let defaults: UserDefaults
    private let storageKey = "subscribed-forum-channel-ids"
    private let sourceStorageKey = "subscribed-forum-channel-keys-v3"
    private let orderStorageKey = "subscribed-forum-channel-order-v1"
    private let migrationKey = "forum-subscriptions-defaults-v2"
    private let v2exHotMigrationKey = "forum-subscriptions-v2ex-hot-default-v1"
    private let schemaVersionKey = "forum-subscriptions-schema-version"
    private let schemaVersion = 1

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let savedKeys = defaults.stringArray(forKey: sourceStorageKey) {
            let validKeys = savedKeys.filter(Self.isValidChannelKey)
            subscribedChannelKeys = validKeys.isEmpty
                ? Set(Self.defaultChannelIDs.map { "nga:\($0)" })
                : Set(validKeys)
        } else if let savedIDs = defaults.array(forKey: storageKey)?
            .compactMap({ ($0 as? NSNumber)?.intValue }), !savedIDs.isEmpty {
            var restoredIDs = Set(savedIDs)

            if !defaults.bool(forKey: migrationKey),
               !restoredIDs.isDisjoint(with: Self.legacyDefaultChannelIDs) {
                restoredIDs.subtract(Self.legacyDefaultChannelIDs)
                restoredIDs.formUnion(Self.defaultChannelIDs)
            }

            subscribedChannelKeys = Set(restoredIDs.map { "nga:\($0)" })
        } else {
            subscribedChannelKeys = Set(Self.defaultChannelIDs.map { "nga:\($0)" })
        }

        if let savedOrder = defaults.stringArray(forKey: orderStorageKey) {
            orderedChannelKeys = savedOrder.filter(Self.isValidChannelKey)
        } else {
            orderedChannelKeys = Self.defaultChannelOrder.map { "nga:\($0)" }
        }

        defaults.set(true, forKey: migrationKey)
        defaults.set(schemaVersion, forKey: schemaVersionKey)
        normalizeOrder()
        persist()
    }

    func isSubscribed(_ channel: ForumChannel) -> Bool {
        subscribedChannelKeys.contains(key(for: channel))
    }

    func setSubscribed(_ subscribed: Bool, for channel: ForumChannel) {
        let channelKey = key(for: channel)
        if subscribed {
            subscribedChannelKeys.insert(channelKey)
            if !orderedChannelKeys.contains(channelKey) {
                orderedChannelKeys.append(channelKey)
            }
        } else {
            let sourceCount = subscribedChannelKeys.filter { $0.hasPrefix("\(channel.source.rawValue):") }.count
            guard sourceCount > 1 else { return }
            subscribedChannelKeys.remove(channelKey)
            orderedChannelKeys.removeAll { $0 == channelKey }
        }

        normalizeOrder()
        persist()
    }

    func visibleChannels(from channels: [ForumChannel]) -> [ForumChannel] {
        let channelsByKey = Dictionary(uniqueKeysWithValues: channels.map { (key(for: $0), $0) })
        let orderedVisible = orderedChannelKeys.compactMap { key -> ForumChannel? in
            guard subscribedChannelKeys.contains(key) else { return nil }
            return channelsByKey[key]
        }
        let includedKeys = Set(orderedVisible.map(key))
        let fallbackVisible = channels.filter { channel in
            isSubscribed(channel) && !includedKeys.contains(key(for: channel))
        }
        return orderedVisible + fallbackVisible
    }

    func restoreDefaults() {
        subscribedChannelKeys = subscribedChannelKeys.filter { !$0.hasPrefix("nga:") }
        subscribedChannelKeys.formUnion(Self.defaultChannelIDs.map { "nga:\($0)" })
        orderedChannelKeys.removeAll { $0.hasPrefix("nga:") }
        orderedChannelKeys.append(contentsOf: Self.defaultChannelOrder.map { "nga:\($0)" })
        normalizeOrder()
        persist()
    }

    func restoreDefaults(for channels: [ForumChannel]) {
        guard let source = channels.first?.source else { return }
        let sourcePrefix = "\(source.rawValue):"
        subscribedChannelKeys = subscribedChannelKeys.filter { !$0.hasPrefix(sourcePrefix) }
        let sourceDefaults = source == .nga
            ? channels.filter { Self.defaultChannelIDs.contains($0.id) }
            : preferredDefaultChannels(for: channels)
        subscribedChannelKeys.formUnion(sourceDefaults.map(key))
        orderedChannelKeys.removeAll { $0.hasPrefix(sourcePrefix) }
        orderedChannelKeys.append(contentsOf: sourceDefaults.map(key))
        normalizeOrder()
        persist()
    }

    func prepareDefaults(for channels: [ForumChannel]) {
        guard let source = channels.first?.source, !channels.isEmpty else { return }

        if !subscribedChannelKeys.contains(where: { $0.hasPrefix("\(source.rawValue):") }) {
            let defaults = source == .nga
                ? channels.filter { Self.defaultChannelIDs.contains($0.id) }
                : preferredDefaultChannels(for: channels)
            subscribedChannelKeys.formUnion(defaults.map(key))
            orderedChannelKeys.append(contentsOf: defaults.map(key).filter { !orderedChannelKeys.contains($0) })
            normalizeOrder()
            persist()
            return
        }

        migrateV2EXHotDefaultIfNeeded(for: channels)
    }

    func moveSubscribedChannel(
        source sourceChannel: ForumChannel,
        before targetChannel: ForumChannel,
        in channels: [ForumChannel]
    ) {
        let orderedSourceKeys = visibleChannels(from: channels).map(key)
        guard let sourceIndex = orderedSourceKeys.firstIndex(of: key(for: sourceChannel)),
              let targetIndex = orderedSourceKeys.firstIndex(of: key(for: targetChannel)),
              sourceIndex != targetIndex
        else { return }

        var reorderedKeys = orderedSourceKeys
        let movedKey = reorderedKeys.remove(at: sourceIndex)
        let destinationIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        reorderedKeys.insert(movedKey, at: destinationIndex)

        replaceOrderedKeys(for: sourceChannel.source, with: reorderedKeys)
    }

    func moveSubscribedChannelToEnd(_ sourceChannel: ForumChannel, in channels: [ForumChannel]) {
        var orderedSourceKeys = visibleChannels(from: channels).map(key)
        let sourceKey = key(for: sourceChannel)
        guard let sourceIndex = orderedSourceKeys.firstIndex(of: sourceKey),
              sourceIndex != orderedSourceKeys.count - 1
        else { return }

        orderedSourceKeys.remove(at: sourceIndex)
        orderedSourceKeys.append(sourceKey)
        replaceOrderedKeys(for: sourceChannel.source, with: orderedSourceKeys)
    }

    private func persist() {
        defaults.set(subscribedIDs.sorted(), forKey: storageKey)
        defaults.set(subscribedChannelKeys.sorted(), forKey: sourceStorageKey)
        defaults.set(orderedChannelKeys, forKey: orderStorageKey)
    }

    private func key(for channel: ForumChannel) -> String {
        "\(channel.source.rawValue):\(channel.nativeKey)"
    }

    private func replaceOrderedKeys(for source: ForumSource, with reorderedSourceKeys: [String]) {
        let sourcePrefix = "\(source.rawValue):"
        orderedChannelKeys.removeAll {
            $0.hasPrefix(sourcePrefix) && subscribedChannelKeys.contains($0)
        }
        orderedChannelKeys.append(contentsOf: reorderedSourceKeys)
        normalizeOrder()
        persist()
    }

    private func normalizeOrder() {
        var seen = Set<String>()
        orderedChannelKeys = orderedChannelKeys.filter { key in
            guard subscribedChannelKeys.contains(key), !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }

        let missingKeys = subscribedChannelKeys.subtracting(seen).sorted()
        orderedChannelKeys.append(contentsOf: missingKeys)
    }

    private static func isValidChannelKey(_ key: String) -> Bool {
        guard let separator = key.firstIndex(of: ":"),
              ForumSource(rawValue: String(key[..<separator])) != nil
        else { return false }
        return !key[key.index(after: separator)...].isEmpty
    }

    private func preferredDefaultChannels(for channels: [ForumChannel]) -> [ForumChannel] {
        guard let source = channels.first?.source else { return [] }

        switch source {
        case .nga:
            return channels.filter { Self.defaultChannelIDs.contains($0.id) }
        case .v2ex:
            let hotChannels = channels.filter { $0.nativeKey == "hot" }
            let remaining = channels.filter { $0.nativeKey != "hot" }
            return hotChannels + remaining.prefix(max(0, 8 - hotChannels.count))
        case .linuxDo:
            return Array(channels.prefix(8))
        }
    }

    private func migrateV2EXHotDefaultIfNeeded(for channels: [ForumChannel]) {
        guard channels.first?.source == .v2ex,
              !defaults.bool(forKey: v2exHotMigrationKey),
              let hotChannel = channels.first(where: { $0.nativeKey == "hot" })
        else { return }

        let hotKey = key(for: hotChannel)
        subscribedChannelKeys.insert(hotKey)
        orderedChannelKeys.removeAll { $0 == hotKey }
        orderedChannelKeys.insert(hotKey, at: 0)
        defaults.set(true, forKey: v2exHotMigrationKey)
        normalizeOrder()
        persist()
    }
}
