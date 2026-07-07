import Photos
import SwiftUI
import UIKit
import WebKit

struct ForumRichContentView: View {
    let blocks: [ForumContentBlock]
    let fontSize: CGFloat
    let activeGIFPlaybackImageIDs: Set<UUID>
    let scrollTrackingSpaceName: String?

    init(
        text: String,
        fontSize: CGFloat,
        activeGIFPlaybackImageIDs: Set<UUID> = [],
        scrollTrackingSpaceName: String? = nil
    ) {
        blocks = ForumContentParser.parse(text)
        self.fontSize = fontSize
        self.activeGIFPlaybackImageIDs = activeGIFPlaybackImageIDs
        self.scrollTrackingSpaceName = scrollTrackingSpaceName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                switch block.content {
                case let .text(text):
                    Text(text)
                        .font(.system(size: fontSize, design: .serif))
                        .foregroundStyle(PaperTheme.secondaryInk)
                        .lineSpacing(fontSize >= 18 ? 6 : 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .image(url):
                    InteractiveForumImage(
                        url: url,
                        activeGIFPlaybackImageIDs: activeGIFPlaybackImageIDs,
                        scrollTrackingSpaceName: scrollTrackingSpaceName
                    )
                case let .quote(quote):
                    ForumQuoteBlockCard(quote: quote, fontSize: fontSize)
                }
            }
        }
    }
}

struct ForumQuoteBlockCard: View {
    let quote: ForumQuoteBlock
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text("+ R")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PaperTheme.accent.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("by \(quote.author)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PaperTheme.ink)

                if quote.createdAt.isUsefulForumValue {
                    Text("(\(quote.createdAt))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PaperTheme.mutedText)
                }
            }

            Text(quote.body)
                .font(.system(size: max(fontSize - 1, 15), design: .serif))
                .foregroundStyle(PaperTheme.secondaryInk)
                .lineSpacing(fontSize >= 18 ? 5 : 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )
        )
    }
}

private struct InteractiveForumImage: View {
    let url: URL
    let activeGIFPlaybackImageIDs: Set<UUID>
    let scrollTrackingSpaceName: String?
    @State private var asset: ForumRemoteImageAsset?
    @State private var failed = false
    @State private var showsPreview = false
    @State private var actionErrorMessage: String?
    @State private var isSavingImage = false
    @State private var gifPlaybackID = UUID()

    var body: some View {
        Group {
            if let asset {
                ZStack {
                    ForumImageContent(
                        asset: asset,
                        playsAnimatedGIF: !asset.isAnimatedGIF || activeGIFPlaybackImageIDs.contains(gifPlaybackID)
                    )
                    Color.clear
                        .contentShape(Rectangle())
                }
                .background(gifVisibilityProbe(for: asset))
                .onTapGesture {
                    showsPreview = true
                }
                .contextMenu {
                    Button {
                        Task { await saveImage() }
                    } label: {
                        if isSavingImage {
                            Label("保存中", systemImage: "arrow.down.circle")
                        } else {
                            Label("保存到相册", systemImage: "arrow.down.circle")
                        }
                    }

                    ShareLink(item: url) {
                        Label("分享图片链接", systemImage: "square.and.arrow.up")
                    }

                    Link(destination: url) {
                        Label("打开原图", systemImage: "safari")
                    }
                }
                .disabled(isSavingImage)
                .accessibilityAddTraits(.isButton)
            } else if failed {
                Link(destination: url) {
                    Label("图片加载失败，点击打开原图", systemImage: "photo.badge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(PaperTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(PaperTheme.paperDeep.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            } else {
                ProgressView("图片加载中")
                    .tint(PaperTheme.mutedText)
                    .foregroundStyle(PaperTheme.mutedText)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .background(PaperTheme.paperDeep.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .accessibilityLabel("帖子图片")
        .task(id: url) {
            await loadImage()
        }
        .sheet(isPresented: $showsPreview) {
            if let asset {
                ForumImagePreviewSheet(
                    asset: asset,
                    onSave: {
                        Task { await saveImage() }
                    }
                )
            }
        }
        .alert("图片操作失败", isPresented: actionErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "请稍后重试。")
        }
    }

    @ViewBuilder
    private func gifVisibilityProbe(for asset: ForumRemoteImageAsset) -> some View {
        if asset.isAnimatedGIF, let scrollTrackingSpaceName {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ThreadDetailGIFFramePreferenceKey.self,
                    value: [
                        ThreadDetailGIFFrameCandidate(
                            id: gifPlaybackID,
                            frame: proxy.frame(in: .named(scrollTrackingSpaceName))
                        )
                    ]
                )
            }
        }
    }

    private func loadImage() async {
        let hadPreviousAsset = asset != nil
        if asset == nil {
            failed = false
        }
        failed = false

        do {
            asset = try await NGAImageLoader.loadAsset(url: url)
        } catch is CancellationError {
            if !hadPreviousAsset, asset == nil {
                failed = true
            }
            return
        } catch {
            failed = true
        }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )
    }

    private func saveImage() async {
        guard let asset, !isSavingImage else { return }

        isSavingImage = true
        actionErrorMessage = nil
        defer { isSavingImage = false }

        do {
            try await ForumImageSaver.save(asset: asset)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }
}

private struct ForumImageContent: View {
    let asset: ForumRemoteImageAsset
    var playsAnimatedGIF: Bool = true

    var body: some View {
        Group {
            if asset.isAnimatedGIF, playsAnimatedGIF {
                AnimatedImageView(data: asset.data, mimeType: asset.mimeType, localFileURL: asset.localFileURL)
                    .aspectRatio(asset.displayAspectRatio, contentMode: .fit)
            } else {
                Image(uiImage: asset.previewImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if asset.isAnimatedGIF {
                Text("GIF")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(10)
            }
        }
    }
}

private struct ForumImagePreviewSheet: View {
    let asset: ForumRemoteImageAsset
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoomScale: CGFloat = 1
    @State private var accumulatedZoomScale: CGFloat = 1
    @State private var contentOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.96)
                    .ignoresSafeArea()

                previewContent
            }
            .overlay(alignment: .trailing) {
                VStack(spacing: 14) {
                    previewActionButton(systemImage: "arrow.down.circle") {
                        onSave()
                    }

                    previewActionButton(systemImage: "xmark") {
                        dismiss()
                    }
                }
                .padding(.trailing, 18)
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .presentationBackground(.clear)
    }

    private var previewContent: some View {
        ForumImageContent(asset: asset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(18)
            .scaleEffect(zoomScale)
            .offset(contentOffset)
            .contentShape(Rectangle())
            .gesture(doubleTapGesture)
            .simultaneousGesture(magnificationGesture)
            .simultaneousGesture(dragGesture)
            .animation(.easeInOut(duration: 0.2), value: zoomScale)
    }

    private func previewActionButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(duration: 0.28, bounce: 0.12)) {
                    if zoomScale > 1.01 {
                        resetZoom()
                    } else {
                        zoomScale = 2.5
                        accumulatedZoomScale = 2.5
                    }
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let nextScale = accumulatedZoomScale * value.magnification
                zoomScale = min(max(nextScale, 1), 4)
            }
            .onEnded { _ in
                accumulatedZoomScale = zoomScale
                if zoomScale <= 1.01 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        resetZoom()
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomScale > 1.01 else { return }
                contentOffset = CGSize(
                    width: accumulatedOffset.width + value.translation.width,
                    height: accumulatedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard zoomScale > 1.01 else {
                    resetZoom()
                    return
                }
                accumulatedOffset = contentOffset
            }
    }

    private func resetZoom() {
        zoomScale = 1
        accumulatedZoomScale = 1
        contentOffset = .zero
        accumulatedOffset = .zero
    }
}

private struct AnimatedImageView: UIViewRepresentable {
    let data: Data
    let mimeType: String
    let localFileURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let loadKey = localFileURL?.absoluteString ?? "\(mimeType)-\(data.count)"
        guard context.coordinator.lastLoadKey != loadKey else { return }
        context.coordinator.lastLoadKey = loadKey

        if let localFileURL {
            webView.loadFileURL(localFileURL, allowingReadAccessTo: localFileURL.deletingLastPathComponent())
            return
        }

        webView.load(
            data,
            mimeType: mimeType,
            characterEncodingName: "",
            baseURL: URL(string: "https://bbs.nga.cn/")!
        )
    }

    final class Coordinator {
        var lastLoadKey: String?
    }
}

struct ForumRemoteImageAsset {
    let data: Data
    let mimeType: String
    let previewImage: UIImage
    let localFileURL: URL?

    var isAnimatedGIF: Bool {
        mimeType == "image/gif"
    }

    var displayAspectRatio: CGFloat {
        let size = previewImage.size
        guard size.width > 0, size.height > 0 else { return 1 }
        return size.width / size.height
    }
}

private enum ForumImageSaver {
    static func save(asset: ForumRemoteImageAsset) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let authorized: PHAuthorizationStatus

        if status == .notDetermined {
            authorized = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            authorized = status
        }

        guard authorized == .authorized || authorized == .limited else {
            throw ForumImageSaveError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = asset.isAnimatedGIF ? "com.compuserve.gif" : "public.jpeg"
            request.addResource(with: .photo, data: asset.data, options: options)
        }
    }
}

private enum ForumImageSaveError: LocalizedError {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有相册写入权限，请在系统设置里允许后重试。"
        case .saveFailed:
            return "图片保存失败，请稍后再试。"
        }
    }
}

struct ThreadDetailGIFFrameCandidate: Equatable, Identifiable {
    let id: UUID
    let frame: CGRect
}

struct ThreadDetailGIFFramePreferenceKey: PreferenceKey {
    static var defaultValue: [ThreadDetailGIFFrameCandidate] = []

    static func reduce(value: inout [ThreadDetailGIFFrameCandidate], nextValue: () -> [ThreadDetailGIFFrameCandidate]) {
        value.append(contentsOf: nextValue())
    }
}
