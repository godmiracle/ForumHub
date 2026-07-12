import PhotosUI
import SwiftUI
import UIKit

struct ReplyComposerSheet: View {
    let source: ForumSource
    let capabilities: ForumCapabilities
    @Binding var target: ThreadReplyTarget
    @Binding var document: ReplyComposerDocument
    @Binding var attachments: [ReplyComposerAttachment]
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var imageLoadErrorMessage: String?
    @State private var showsEmojiPicker = false
    @State private var shouldFocusRichEditor = false

    private var quickEmojis: [NGAForumEmojiItem] {
        Array(NGAForumEmojiGroup.ng.items.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            composerHeader

            if case let .reply(targetReply) = target {
                ForumQuoteBlockCard(
                    quote: ForumQuoteBlock(
                        author: targetReply.author,
                        createdAt: targetReply.createdAt,
                        body: targetReply.bodyPreview
                    ),
                    fontSize: 14
                )
                .frame(maxHeight: 76)
                .clipped()
            }

            ReplyComposerRichTextEditor(
                document: $document,
                shouldFocus: $shouldFocusRichEditor,
                isEditable: !isSubmitting
            )
            .frame(minHeight: 104, maxHeight: .infinity)
            .padding(.horizontal, 4)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(attachments) { attachment in
                            attachmentPreview(for: attachment)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            composerToolbar
            if source == .nga {
                quickEmojiBar
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .background {
            LinearGradient(
                colors: [PaperTheme.accent.opacity(0.13), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .allowsHitTesting(false)
        }
        .onAppear {
            shouldFocusRichEditor = true
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await loadSelectedImages(items)
            }
        }
        .alert("图片处理失败", isPresented: imageLoadErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(imageLoadErrorMessage ?? "请换一张图片重试。")
        }
        .sheet(isPresented: $showsEmojiPicker) {
            NGAEmojiPickerSheet { emoji in
                insertEmoji(emoji)
                showsEmojiPicker = false
            }
        }
    }

    private var composerHeader: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(PaperTheme.accent)
                .frame(width: 4, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.displayTitle)
                    .font(.headline)
                    .foregroundStyle(PaperTheme.ink)
                    .lineLimit(1)

                Text("通过 \(source.title) 发送")
                    .font(.caption)
                    .foregroundStyle(PaperTheme.mutedText)
            }

            Spacer(minLength: 8)

            if case .reply = target {
                Button("回复主题") {
                    target = .thread
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(PaperTheme.accent)
                .disabled(isSubmitting)
            }

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PaperTheme.mutedText)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .accessibilityLabel("关闭回复编辑器")
        }
    }

    private var composerToolbar: some View {
        HStack(spacing: 18) {
            if source == .nga {
                Button {
                    showsEmojiPicker = true
                } label: {
                    Image(systemName: "face.smiling")
                }
            }

            if capabilities.supportsImageUpload {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: max(1, 9 - attachments.count),
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .disabled(isSubmitting || attachments.count >= 9)
            }

            Button {
                document.insert(text: "@")
                shouldFocusRichEditor = true
            } label: {
                Image(systemName: "at")
            }

            Button {
                document.insert(text: "#")
                shouldFocusRichEditor = true
            } label: {
                Image(systemName: "number")
            }

            Spacer(minLength: 4)

            Text("\(document.displayCharacterCount) 字")
                .font(.caption)
                .foregroundStyle(PaperTheme.mutedText)

            Button(action: onSubmit) {
                Group {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("发布")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .frame(minWidth: 58, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(PaperTheme.accent)
            .disabled(isSubmitting || document.isEmpty)
        }
        .font(.title3)
        .foregroundStyle(PaperTheme.mutedText)
        .buttonStyle(.plain)
    }

    private var quickEmojiBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(quickEmojis) { emoji in
                    ReplyComposerQuickEmojiButton(emoji: emoji) {
                        insertEmoji($0)
                    }
                    .disabled(isSubmitting)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func insertEmoji(_ emoji: NGAForumEmojiItem) {
        document.insert(emoji: ReplyComposerEmoji(emoji))
        shouldFocusRichEditor = true
    }

    private var imageLoadErrorBinding: Binding<Bool> {
        Binding(
            get: { imageLoadErrorMessage != nil },
            set: { if !$0 { imageLoadErrorMessage = nil } }
        )
    }

    private func attachmentPreview(for attachment: ReplyComposerAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Image(uiImage: attachment.previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .offset(x: 6, y: -6)
            .disabled(isSubmitting)
        }
    }

    private func loadSelectedImages(_ items: [PhotosPickerItem]) async {
        var loadedAttachments: [ReplyComposerAttachment] = []

        do {
            for (index, item) in items.enumerated() {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let preparedAttachment = ReplyComposerAttachment.make(from: image, index: attachments.count + index + 1)
                else {
                    throw ReplyComposerAttachmentError.unsupportedImage
                }
                loadedAttachments.append(preparedAttachment)
            }

            var seenKeys = Set(attachments.map(\.deduplicationKey))
            let uniqueAttachments = loadedAttachments.filter { attachment in
                seenKeys.insert(attachment.deduplicationKey).inserted
            }
            attachments.append(contentsOf: uniqueAttachments)
            selectedPhotoItems = []
        } catch {
            imageLoadErrorMessage = error.localizedDescription
            selectedPhotoItems = []
        }
    }
}

private struct ReplyComposerQuickEmojiButton: View {
    let emoji: NGAForumEmojiItem
    let onSelect: (NGAForumEmojiItem) -> Void
    @State private var image: UIImage?

    var body: some View {
        Button {
            onSelect(emoji.withPreviewImage(image))
        } label: {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "face.smiling")
                        .foregroundStyle(PaperTheme.mutedText)
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .task(id: emoji.id) {
            guard image == nil else { return }
            image = try? await NGAImageLoader.load(url: emoji.imageURL)
        }
    }
}

private struct NGAEmojiPickerSheet: View {
    let onSelect: (NGAForumEmojiItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGroup: NGAForumEmojiGroup = .ng

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("表情分组", selection: $selectedGroup) {
                    ForEach(NGAForumEmojiGroup.allCases) { group in
                        Text(group.title).tag(group)
                    }
                }
                .pickerStyle(.segmented)

                Text("一期先按图片表情插入正文，连续点选会依次追加到回帖末尾。")
                    .font(.footnote)
                    .foregroundStyle(PaperTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(selectedGroup.items) { emoji in
                            NGAEmojiPickerItemView(
                                emoji: emoji,
                                onSelect: onSelect
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(20)
            .background(PaperBackground())
            .navigationTitle("添加表情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct NGAEmojiPickerItemView: View {
    let emoji: NGAForumEmojiItem
    let onSelect: (NGAForumEmojiItem) -> Void
    @State private var loadedImage: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Button {
            onSelect(emoji.withPreviewImage(loadedImage))
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let loadedImage {
                        Image(uiImage: loadedImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else if loadFailed {
                        Image(systemName: "face.smiling.inverse")
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                            .foregroundStyle(PaperTheme.mutedText)
                    } else {
                        ProgressView()
                            .tint(PaperTheme.mutedText)
                    }
                }
                .frame(width: 44, height: 44)

                Text(emoji.displayName)
                    .font(.caption2)
                    .foregroundStyle(PaperTheme.mutedText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .task(id: emoji.id) {
            guard loadedImage == nil, !loadFailed else { return }
            do {
                loadedImage = try await NGAImageLoader.load(url: emoji.imageURL)
            } catch {
                loadFailed = true
            }
        }
    }
}

enum NGAForumEmojiGroup: String, CaseIterable, Identifiable {
    case ng
    case ac
    case a2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ng:
            return "NG娘"
        case .ac:
            return "AC娘v1"
        case .a2:
            return "AC娘v2"
        }
    }

    var items: [NGAForumEmojiItem] {
        switch self {
        case .ng:
            return (1...40).map {
                NGAForumEmojiItem(group: self, displayName: "\($0)", filename: "ng_\($0).png")
            }
        case .ac:
            return (1...40).map {
                NGAForumEmojiItem(group: self, displayName: "\($0)", filename: "ac\($0).png")
            }
        case .a2:
            return (1...40).map {
                let name = String(format: "%02d", $0)
                return NGAForumEmojiItem(group: self, displayName: name, filename: "a2_\(name).png")
            }
        }
    }
}

struct NGAForumEmojiItem: Identifiable {
    let group: NGAForumEmojiGroup
    let displayName: String
    let filename: String
    private let imageURLOverride: URL?
    private let previewImageOverride: UIImage?

    init(group: NGAForumEmojiGroup, displayName: String, filename: String) {
        self.group = group
        self.displayName = displayName
        self.filename = filename
        self.imageURLOverride = nil
        self.previewImageOverride = nil
    }

    var id: String { filename }

    var imageURL: URL {
        imageURLOverride ?? URL(string: "https://img4.nga.178.com/ngabbs/post/smile/\(filename)")!
    }

    var markup: String {
        "[img]\(imageURL.absoluteString)[/img]"
    }

    var previewImage: UIImage? {
        previewImageOverride
    }

    func withPreviewImage(_ image: UIImage?) -> NGAForumEmojiItem {
        NGAForumEmojiItem(
            group: group,
            displayName: displayName,
            filename: filename,
            imageURLOverride: imageURLOverride,
            previewImageOverride: image
        )
    }

    init?(filename: String, imageURL: URL) {
        self.filename = filename
        switch true {
        case filename.hasPrefix("ng_"):
            group = .ng
            displayName = filename
                .replacingOccurrences(of: "ng_", with: "")
                .replacingOccurrences(of: ".png", with: "")
        case filename.hasPrefix("ac"):
            group = .ac
            displayName = filename
                .replacingOccurrences(of: "ac", with: "")
                .replacingOccurrences(of: ".png", with: "")
        case filename.hasPrefix("a2_"):
            group = .a2
            displayName = filename
                .replacingOccurrences(of: "a2_", with: "")
                .replacingOccurrences(of: ".png", with: "")
        default:
            return nil
        }
        imageURLOverride = imageURL
        previewImageOverride = nil
    }

    private init(
        group: NGAForumEmojiGroup,
        displayName: String,
        filename: String,
        imageURLOverride: URL?,
        previewImageOverride: UIImage?
    ) {
        self.group = group
        self.displayName = displayName
        self.filename = filename
        self.imageURLOverride = imageURLOverride
        self.previewImageOverride = previewImageOverride
    }
}

struct ReplyComposerEmoji: Equatable {
    let filename: String
    let imageURL: URL

    init(_ item: NGAForumEmojiItem) {
        filename = item.filename
        imageURL = item.imageURL
    }

    var markup: String { "[img]\(imageURL.absoluteString)[/img]" }

    init?(markup: String) {
        guard markup.hasPrefix("[img]"), markup.hasSuffix("[/img]") else { return nil }
        let urlText = String(markup.dropFirst(5).dropLast(6))
        guard let imageURL = URL(string: urlText),
              let filename = imageURL.pathComponents.last,
              let _ = NGAForumEmojiItem(filename: filename, imageURL: imageURL)
        else { return nil }
        self.filename = filename
        self.imageURL = imageURL
    }
}

enum ReplyComposerDocumentComponent: Equatable {
    case text(String)
    case emoji(ReplyComposerEmoji)
}

struct ReplyComposerDocument: Equatable {
    private(set) var components: [ReplyComposerDocumentComponent]
    private(set) var selection: NSRange

    init(text: String = "") {
        components = text.isEmpty ? [] : [.text(text)]
        selection = NSRange(location: (text as NSString).length, length: 0)
    }

    init(components: [ReplyComposerDocumentComponent], selection: NSRange) {
        self.components = Self.normalized(components)
        self.selection = selection
    }

    var markup: String {
        components.map { component in
            switch component {
            case let .text(text): text
            case let .emoji(emoji): emoji.markup
            }
        }.joined()
    }

    var isEmpty: Bool {
        markup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayCharacterCount: Int {
        components.reduce(0) { count, component in
            switch component {
            case let .text(text): count + text.trimmingCharacters(in: .whitespacesAndNewlines).count
            case .emoji: count + 1
            }
        }
    }

    mutating func insert(emoji: ReplyComposerEmoji) {
        let insertionOffset = max(0, min(selection.location, visualLength))
        var remainingOffset = insertionOffset

        for index in components.indices {
            switch components[index] {
            case let .text(text):
                let length = (text as NSString).length
                guard remainingOffset <= length else {
                    remainingOffset -= length
                    continue
                }
                let splitIndex = String.Index(utf16Offset: remainingOffset, in: text)
                let prefix = String(text[..<splitIndex])
                let suffix = String(text[splitIndex...])
                components.replaceSubrange(index...index, with: [
                    prefix.isEmpty ? nil : .text(prefix),
                    .emoji(emoji),
                    suffix.isEmpty ? nil : .text(suffix)
                ].compactMap { $0 })
                selection = NSRange(location: insertionOffset + 2, length: 0)
                components = Self.normalized(components)
                return
            case .emoji:
                guard remainingOffset > 0 else {
                    components.insert(.emoji(emoji), at: index)
                    selection = NSRange(location: insertionOffset + 2, length: 0)
                    return
                }
                remainingOffset -= 2
            }
        }

        components.append(.emoji(emoji))
        selection = NSRange(location: visualLength, length: 0)
    }

    mutating func insert(text insertedText: String) {
        guard !insertedText.isEmpty else { return }

        let insertionOffset = max(0, min(selection.location, visualLength))
        var remainingOffset = insertionOffset

        for index in components.indices {
            switch components[index] {
            case let .text(text):
                let length = (text as NSString).length
                guard remainingOffset <= length else {
                    remainingOffset -= length
                    continue
                }
                let splitIndex = String.Index(utf16Offset: remainingOffset, in: text)
                components[index] = .text(
                    String(text[..<splitIndex]) + insertedText + String(text[splitIndex...])
                )
                components = Self.normalized(components)
                selection = NSRange(
                    location: insertionOffset + (insertedText as NSString).length,
                    length: 0
                )
                return
            case .emoji:
                guard remainingOffset > 0 else {
                    components.insert(.text(insertedText), at: index)
                    components = Self.normalized(components)
                    selection = NSRange(
                        location: insertionOffset + (insertedText as NSString).length,
                        length: 0
                    )
                    return
                }
                remainingOffset -= 2
            }
        }

        components.append(.text(insertedText))
        components = Self.normalized(components)
        selection = NSRange(location: visualLength, length: 0)
    }

    mutating func updateSelection(_ selection: NSRange) {
        self.selection = NSRange(location: max(0, min(selection.location, visualLength)), length: 0)
    }

    var visualLength: Int {
        components.reduce(0) { length, component in
            switch component {
            case let .text(text): length + (text as NSString).length
            case .emoji: length + 2
            }
        }
    }

    private static func normalized(_ components: [ReplyComposerDocumentComponent]) -> [ReplyComposerDocumentComponent] {
        components.reduce(into: []) { result, component in
            switch component {
            case let .text(text) where text.isEmpty:
                break
            case let .text(text):
                if case let .text(previous)? = result.last {
                    result[result.count - 1] = .text(previous + text)
                } else {
                    result.append(.text(text))
                }
            case .emoji:
                result.append(component)
            }
        }
    }
}

struct ReplyComposerRichTextEditor: UIViewRepresentable {
    private static let emojiAnchorCharacter = "\u{200B}"
    private static let emojiMarkupAttribute = NSAttributedString.Key("ForumHubEmojiMarkup")
    @Binding var document: ReplyComposerDocument
    @Binding var shouldFocus: Bool
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(document: $document, shouldFocus: $shouldFocus)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = UIColor(PaperTheme.secondaryInk)
        textView.tintColor = UIColor(PaperTheme.accent)
        textView.allowsEditingTextAttributes = true
        textView.isScrollEnabled = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 6, bottom: 12, right: 6)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.typingAttributes = Coordinator.baseAttributes(for: textView.font ?? .preferredFont(forTextStyle: .body))
        context.coordinator.synchronize(document, to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.isEditable = isEditable
        textView.isSelectable = true
        context.coordinator.synchronize(document, to: textView)
        context.coordinator.updateFocusIfNeeded(for: textView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var document: ReplyComposerDocument
        @Binding private var shouldFocus: Bool
        private var isApplyingProgrammaticChange = false
        private var lastRenderedComponents: [ReplyComposerDocumentComponent]?

        init(document: Binding<ReplyComposerDocument>, shouldFocus: Binding<Bool>) {
            _document = document
            _shouldFocus = shouldFocus
        }

        func synchronize(_ document: ReplyComposerDocument, to textView: UITextView) {
            let font = textView.font ?? .preferredFont(forTextStyle: .body)
            if lastRenderedComponents != document.components {
                isApplyingProgrammaticChange = true
                textView.attributedText = attributedText(from: document, font: font, textView: textView)
                textView.typingAttributes = Self.baseAttributes(for: font)
                textView.selectedRange = boundedSelection(document.selection, textLength: textView.attributedText.length)
                isApplyingProgrammaticChange = false
                lastRenderedComponents = document.components
            } else if textView.selectedRange != document.selection {
                isApplyingProgrammaticChange = true
                textView.selectedRange = boundedSelection(document.selection, textLength: textView.attributedText.length)
                isApplyingProgrammaticChange = false
            }
        }

        func updateFocusIfNeeded(for textView: UITextView) {
            guard shouldFocus else { return }
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
            DispatchQueue.main.async { [weak self] in self?.shouldFocus = false }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            commitDocument(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            let adjustedLocation = adjustedCaretLocation(for: textView.selectedRange.location, in: textView.attributedText)
            if adjustedLocation != textView.selectedRange.location {
                isApplyingProgrammaticChange = true
                textView.selectedRange = NSRange(location: adjustedLocation, length: 0)
                isApplyingProgrammaticChange = false
            }
            document.updateSelection(textView.selectedRange)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText: String) -> Bool {
            guard !isApplyingProgrammaticChange else { return true }
            let adjustedRange = adjustedEditingRange(for: range, replacementText: replacementText, in: textView.attributedText)
            guard adjustedRange != range else { return true }

            let font = textView.font ?? .preferredFont(forTextStyle: .body)
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            mutable.replaceCharacters(in: adjustedRange, with: NSAttributedString(string: replacementText, attributes: Self.baseAttributes(for: font)))
            isApplyingProgrammaticChange = true
            textView.attributedText = mutable
            textView.typingAttributes = Self.baseAttributes(for: font)
            textView.selectedRange = NSRange(location: min(adjustedRange.location + replacementText.utf16.count, textView.attributedText.length), length: 0)
            isApplyingProgrammaticChange = false
            commitDocument(from: textView)
            return false
        }

        private func attributedText(from document: ReplyComposerDocument, font: UIFont, textView: UITextView) -> NSAttributedString {
            let result = NSMutableAttributedString()
            for component in document.components {
                switch component {
                case let .text(text):
                    result.append(NSAttributedString(string: text, attributes: Self.baseAttributes(for: font)))
                case let .emoji(emoji):
                    result.append(Self.makeEmojiAttachment(for: emoji, font: font, textView: textView))
                    result.append(NSAttributedString(string: ReplyComposerRichTextEditor.emojiAnchorCharacter, attributes: Self.baseAttributes(for: font)))
                }
            }
            return result
        }

        private func commitDocument(from textView: UITextView) {
            let fullRange = NSRange(location: 0, length: textView.attributedText.length)
            var components: [ReplyComposerDocumentComponent] = []
            textView.attributedText.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
                if let markup = attributes[ReplyComposerRichTextEditor.emojiMarkupAttribute] as? String,
                   let emoji = ReplyComposerEmoji(markup: markup) {
                    components.append(.emoji(emoji))
                } else {
                    let text = textView.attributedText.attributedSubstring(from: range).string
                        .replacingOccurrences(of: ReplyComposerRichTextEditor.emojiAnchorCharacter, with: "")
                    components.append(.text(text))
                }
            }
            document = ReplyComposerDocument(components: components, selection: textView.selectedRange)
            lastRenderedComponents = document.components
        }

        private func boundedSelection(_ selection: NSRange, textLength: Int) -> NSRange {
            NSRange(location: min(max(selection.location, 0), textLength), length: 0)
        }

        private func adjustedCaretLocation(for location: Int, in attributedText: NSAttributedString) -> Int {
            guard location < attributedText.length,
                  isEmojiAnchor(at: location, in: attributedText),
                  hasEmojiAttachment(at: location - 1, in: attributedText)
            else { return location }
            return min(location + 1, attributedText.length)
        }

        private func adjustedEditingRange(for range: NSRange, replacementText: String, in attributedText: NSAttributedString) -> NSRange {
            guard replacementText.isEmpty, range.length == 1 else { return range }
            if isEmojiAnchor(at: range.location, in: attributedText), hasEmojiAttachment(at: range.location - 1, in: attributedText) {
                return NSRange(location: max(0, range.location - 1), length: 2)
            }
            if hasEmojiAttachment(at: range.location, in: attributedText), isEmojiAnchor(at: range.location + 1, in: attributedText) {
                return NSRange(location: range.location, length: 2)
            }
            return range
        }

        private func isEmojiAnchor(at location: Int, in attributedText: NSAttributedString) -> Bool {
            guard location >= 0, location < attributedText.length else { return false }
            return attributedText.attributedSubstring(from: NSRange(location: location, length: 1)).string == ReplyComposerRichTextEditor.emojiAnchorCharacter
        }

        private func hasEmojiAttachment(at location: Int, in attributedText: NSAttributedString) -> Bool {
            guard location >= 0, location < attributedText.length else { return false }
            return attributedText.attribute(ReplyComposerRichTextEditor.emojiMarkupAttribute, at: location, effectiveRange: nil) != nil
        }

        static func baseAttributes(for font: UIFont) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: UIColor(PaperTheme.secondaryInk)]
        }

        private static func makeEmojiAttachment(for emoji: ReplyComposerEmoji, font: UIFont, textView: UITextView) -> NSAttributedString {
            let attachment = NSTextAttachment()
            attachment.bounds = CGRect(x: 0, y: -4, width: font.lineHeight + 8, height: font.lineHeight + 8)
            attachment.image = placeholderEmojiImage(side: font.lineHeight + 8)
            let result = NSMutableAttributedString(attachment: attachment)
            result.addAttribute(ReplyComposerRichTextEditor.emojiMarkupAttribute, value: emoji.markup, range: NSRange(location: 0, length: result.length))
            Task {
                if let image = try? await NGAImageLoader.load(url: emoji.imageURL) {
                    await MainActor.run {
                        attachment.image = image
                        let range = NSRange(location: 0, length: textView.attributedText.length)
                        textView.layoutManager.invalidateDisplay(forCharacterRange: range)
                        textView.layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                    }
                }
            }
            return result
        }

        private static func placeholderEmojiImage(side: CGFloat) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
            return renderer.image { _ in
                UIColor(PaperTheme.paperDeep).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: CGSize(width: side, height: side)), cornerRadius: 6).fill()
                let config = UIImage.SymbolConfiguration(pointSize: side * 0.56, weight: .regular)
                let image = UIImage(systemName: "face.smiling", withConfiguration: config)?.withTintColor(UIColor(PaperTheme.mutedText), renderingMode: .alwaysOriginal)
                image?.draw(in: CGRect(x: side * 0.2, y: side * 0.2, width: side * 0.6, height: side * 0.6))
            }
        }
    }
}

struct ReplyComposerAttachment: Identifiable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data
    let previewImage: UIImage

    var upload: ReplyAttachmentUpload {
        ReplyAttachmentUpload(filename: filename, mimeType: mimeType, data: data)
    }

    var deduplicationKey: String {
        "\(filename)-\(data.count)"
    }

    static func make(from image: UIImage, index: Int) -> ReplyComposerAttachment? {
        let maxDimension: CGFloat = 2200
        let size = image.size
        let longestEdge = max(size.width, size.height)
        let scale = longestEdge > maxDimension ? maxDimension / longestEdge : 1
        let targetSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let renderedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = renderedImage.jpegData(compressionQuality: 0.85) else {
            return nil
        }

        return ReplyComposerAttachment(
            filename: "forumhub-reply-\(index).jpg",
            mimeType: "image/jpeg",
            data: jpegData,
            previewImage: renderedImage
        )
    }
}

private enum ReplyComposerAttachmentError: LocalizedError {
    case unsupportedImage

    var errorDescription: String? {
        "这张图片暂时无法处理，请换一张重试。"
    }
}
