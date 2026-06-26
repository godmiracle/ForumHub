import Foundation
import WebKit

enum AppCacheManager {
    static func clear() async {
        URLCache.shared.removeAllCachedResponses()

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
