import Foundation
import ImageIO
import SwiftUI
import UIKit

enum ThreadSnapshotScope {
    case mainPost
    case loadedContent
}

@MainActor
enum ThreadSnapshotRenderer {
    static let repliesPerImage = 6

    static func render(
        thread: ForumThread,
        replies: [Reply],
        scope: ThreadSnapshotScope
    ) async throws -> [UIImage] {
        let includedReplies = scope == .mainPost ? [] : replies
        let imageURLs = collectImageURLs(thread: thread, replies: includedReplies)
        let loadedImages = await loadImages(from: imageURLs)
        let chunks = replyChunks(includedReplies)

        return try chunks.enumerated().map { index, replies in
            let content = ThreadSnapshotPageView(
                thread: thread,
                replies: replies,
                loadedImages: loadedImages,
                includesMainPost: index == 0,
                pageNumber: index + 1,
                pageCount: chunks.count
            )
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            renderer.proposedSize = ProposedViewSize(width: 390, height: nil)

            guard let image = renderer.uiImage else {
                throw ThreadSnapshotError.renderFailed
            }
            return image
        }
    }

    static func replyChunks(_ replies: [Reply]) -> [[Reply]] {
        guard !replies.isEmpty else { return [[]] }

        return stride(from: 0, to: replies.count, by: repliesPerImage).map { start in
            Array(replies[start..<min(start + repliesPerImage, replies.count)])
        }
    }

    private static func collectImageURLs(thread: ForumThread, replies: [Reply]) -> [URL] {
        let texts = [thread.body] + replies.map(\.body)
        var seen = Set<URL>()
        return texts.flatMap(ForumContentParser.parse).compactMap { block in
            guard case let .image(url) = block.content, seen.insert(url).inserted else {
                return nil
            }
            return url
        }
    }

    private static func loadImages(from urls: [URL]) async -> [URL: UIImage] {
        var images: [URL: UIImage] = [:]
        for url in urls {
            if let image = try? await NGAImageLoader.load(url: url) {
                images[url] = image
            }
        }
        return images
    }
}

enum ThreadSnapshotError: LocalizedError {
    case renderFailed

    var errorDescription: String? {
        "长图生成失败，请减少已加载回帖后重试。"
    }
}

private struct ThreadSnapshotPageView: View {
    let thread: ForumThread
    let replies: [Reply]
    let loadedImages: [URL: UIImage]
    let includesMainPost: Bool
    let pageNumber: Int
    let pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(thread.source.title)
                    .font(.system(size: 15, weight: .black, design: .serif))
                    .foregroundStyle(PaperTheme.accent)
                Spacer()
                if pageCount > 1 {
                    Text("\(pageNumber) / \(pageCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PaperTheme.mutedText)
                }
            }

            if includesMainPost {
                VStack(alignment: .leading, spacing: 12) {
                    Text(thread.title)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(PaperTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        snapshotChip(thread.author)
                        snapshotChip("\(thread.replyCount) 回复")
                        if thread.viewCount > 0 {
                            snapshotChip("\(thread.viewCount) 浏览")
                        }
                    }

                    SnapshotRichContent(
                        text: thread.body,
                        fontSize: 18,
                        loadedImages: loadedImages
                    )
                }
                .padding(18)
                .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Text(thread.title)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(PaperTheme.ink)
                    .lineLimit(2)
            }

            ForEach(replies) { reply in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(reply.author)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PaperTheme.ink)
                        Spacer()
                        Text(reply.createdAt)
                            .font(.caption)
                            .foregroundStyle(PaperTheme.mutedText)
                    }

                    SnapshotRichContent(
                        text: reply.body,
                        fontSize: 17,
                        loadedImages: loadedImages
                    )
                }
                .padding(16)
                .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Text("由社区阅读器生成 · 当前已加载内容")
                .font(.caption2)
                .foregroundStyle(PaperTheme.mutedText.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(18)
        .frame(width: 390)
        .background(
            LinearGradient(
                colors: [PaperTheme.paper, PaperTheme.paperDeep.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func snapshotChip(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(PaperTheme.secondaryInk)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(PaperTheme.paperDeep.opacity(0.55), in: Capsule())
    }
}

private struct SnapshotRichContent: View {
    let text: String
    let fontSize: CGFloat
    let loadedImages: [URL: UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ForumContentParser.parse(text)) { block in
                switch block.content {
                case let .text(text):
                    Text(text)
                        .font(.system(size: fontSize, design: .serif))
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                case let .image(url):
                    if let image = loadedImages[url] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 480)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Label("图片未能加载", systemImage: "photo.badge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(PaperTheme.mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(PaperTheme.paperDeep.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }
}

enum NGAImageLoader {
    private static let previewImageMaxPixelSize = max(
        Int(UIScreen.main.bounds.width * UIScreen.main.scale * 2),
        1_600
    )

    static func loadAsset(url: URL) async throws -> ForumRemoteImageAsset {
        try await ForumImagePipeline.shared.loadAsset(url: url)
    }

    static func load(url: URL) async throws -> UIImage {
        try await loadAsset(url: url).previewImage
    }

    fileprivate static func fetchAsset(url: URL) async throws -> ForumRemoteImageAsset {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 30
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 NGAPrototype/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://bbs.nga.cn/", forHTTPHeaderField: "Referer")

        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let mimeType = response.mimeType?.lowercased()
            ?? NGAImageLoader.inferredMimeType(from: url, data: data)

        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let previewImage = downsampledPreviewImage(from: data)
        else {
            throw URLError(.cannotDecodeContentData)
        }

        let fileURL = mimeType == "image/gif" ? ForumImagePipeline.cachedFileURL(for: url, pathExtension: "gif") : nil

        if let fileURL {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }

        return ForumRemoteImageAsset(
            data: data,
            mimeType: mimeType,
            previewImage: previewImage,
            localFileURL: fileURL
        )
    }

    private static func inferredMimeType(from url: URL, data: Data) -> String {
        if data.starts(with: [0x47, 0x49, 0x46]) {
            return "image/gif"
        }

        switch url.pathExtension.lowercased() {
        case "gif":
            return "image/gif"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        default:
            return "image/jpeg"
        }
    }

    private static func downsampledPreviewImage(from data: Data) -> UIImage? {
        let options: CFDictionary = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options) else {
            return UIImage(data: data)
        }

        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: previewImageMaxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: cgImage)
    }
}

@MainActor
private final class ForumImagePipeline {
    static let shared = ForumImagePipeline()

    private let cache = NSCache<NSURL, ForumRemoteImageAssetBox>()
    private var inFlightTasks: [URL: Task<ForumRemoteImageAsset, Error>] = [:]

    func loadAsset(url: URL) async throws -> ForumRemoteImageAsset {
        if let cached = cache.object(forKey: url as NSURL)?.asset {
            return cached
        }

        if let task = inFlightTasks[url] {
            return try await task.value
        }

        let task = Task { try await NGAImageLoader.fetchAsset(url: url) }
        inFlightTasks[url] = task

        defer {
            inFlightTasks[url] = nil
        }

        do {
            let asset = try await task.value
            cache.setObject(ForumRemoteImageAssetBox(asset: asset), forKey: url as NSURL)
            return asset
        } catch {
            throw error
        }
    }

    static func cachedFileURL(for url: URL, pathExtension: String) -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let filename = url.absoluteString
            .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
            .prefix(120)
        return directory
            .appendingPathComponent("ForumImageCache", isDirectory: true)
            .appendingPathComponent(String(filename))
            .appendingPathExtension(pathExtension)
    }
}

private final class ForumRemoteImageAssetBox: NSObject {
    let asset: ForumRemoteImageAsset

    init(asset: ForumRemoteImageAsset) {
        self.asset = asset
    }
}

struct ActivityShareView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
