import Foundation

enum NGAForumEmojiLocalStore {
    private static let bundledResourceDirectory = "NGAEmoji"
    private static let cacheDirectoryName = "ForumEmoji"
    private static let filenamePattern = #"^[A-Za-z0-9_]+\.png$"#

    static func data(
        for url: URL,
        bundle: Bundle = .main,
        cacheDirectory: URL? = nil
    ) -> Data? {
        guard let filename = filename(for: url) else { return nil }

        if let bundledURL = bundledFileURL(forFilename: filename, bundle: bundle),
           let data = try? Data(contentsOf: bundledURL),
           !data.isEmpty {
            return data
        }

        guard let cachedURL = cacheFileURL(forFilename: filename, cacheDirectory: cacheDirectory),
              let data = try? Data(contentsOf: cachedURL),
              !data.isEmpty
        else {
            return nil
        }
        return data
    }

    static func filename(for url: URL) -> String? {
        guard NGAImageURLResolver.isForumEmoji(url) else { return nil }

        let filename = (url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent)
        guard filename.range(of: filenamePattern, options: .regularExpression) != nil else {
            return nil
        }
        guard NGAReplyEmojiCatalog.item(filename: filename) != nil
            || NGAForumEmojiResolver.isKnownFilename(filename)
        else {
            return nil
        }
        return filename
    }

    static func bundledFileURL(for url: URL, bundle: Bundle = .main) -> URL? {
        guard let filename = filename(for: url) else { return nil }
        return bundledFileURL(forFilename: filename, bundle: bundle)
    }

    static func cacheFileURL(for url: URL) -> URL? {
        guard let filename = filename(for: url) else { return nil }
        return cacheFileURL(forFilename: filename, cacheDirectory: nil)
    }

    static func store(_ data: Data, for url: URL, cacheDirectory: URL? = nil) {
        guard !data.isEmpty,
              let cacheURL = cacheFileURL(for: url, cacheDirectory: cacheDirectory)
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // The bundled resource remains the fallback when the cache is unavailable.
        }
    }

    static func clear(cacheDirectory: URL? = nil) {
        guard let directory = cacheDirectory ?? defaultCacheDirectoryURL else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func bundledFileURL(forFilename filename: String, bundle: Bundle) -> URL? {
        let bundles = [bundle, Bundle(identifier: "com.godmiracle.forumhub")]
            .compactMap { $0 }
            .reduce(into: [Bundle]()) { result, candidate in
                guard !result.contains(where: { $0.bundleURL == candidate.bundleURL }) else { return }
                result.append(candidate)
            }

        let resourceName = (filename as NSString).deletingPathExtension
        return bundles.lazy.compactMap { bundle in
            bundle.url(
                forResource: resourceName,
                withExtension: "png",
                subdirectory: bundledResourceDirectory
            ) ?? bundle.url(forResource: resourceName, withExtension: "png")
        }.first
    }

    private static func cacheFileURL(for url: URL, cacheDirectory: URL?) -> URL? {
        guard let filename = filename(for: url) else { return nil }
        return cacheFileURL(forFilename: filename, cacheDirectory: cacheDirectory)
    }

    private static func cacheFileURL(forFilename filename: String, cacheDirectory: URL?) -> URL? {
        (cacheDirectory ?? defaultCacheDirectoryURL)?.appendingPathComponent(filename, isDirectory: false)
    }

    private static var defaultCacheDirectoryURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
    }
}
