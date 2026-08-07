import Foundation
import WebKit

enum AppCacheManager {
    static func clear() async {
        URLCache.shared.removeAllCachedResponses()
        NGAForumEmojiLocalStore.clear()

        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache
        ]

        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().removeData(
                ofTypes: cacheTypes,
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
    }
}
