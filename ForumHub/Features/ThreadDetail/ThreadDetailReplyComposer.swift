import PhotosUI
import SwiftUI
import UIKit

struct ReplyComposerSheet: View {
    let source: ForumSource
    let capabilities: ForumCapabilities
    @Binding var target: ThreadReplyTarget
    @Binding var text: String
    @Binding var attachments: [ReplyComposerAttachment]
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var imageLoadErrorMessage: String?
    @State private var showsEmojiPicker = false
    @State private var pendingEmojiInsertion: NGAForumEmojiItem?
    @State private var shouldFocusRichEditor = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(target.displayTitle)
                        .font(.headline)
                        .foregroundStyle(PaperTheme.ink)

                    HStack(alignment: .center, spacing: 10) {
                        Text("将作为 \(source.title) \(target.composerDescription)发送。")
                            .font(.footnote)
                            .foregroundStyle(PaperTheme.mutedText)

                        Spacer(minLength: 0)

                        if case .reply = target {
                            Button("改为回复主题") {
                                target = .thread
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PaperTheme.accent)
                            .disabled(isSubmitting)
                        }
                    }
                    .padding(12)
                    .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if case let .reply(targetReply) = target {
                    ForumQuoteBlockCard(
                        quote: ForumQuoteBlock(
                            author: targetReply.author,
                            createdAt: targetReply.createdAt,
                            body: targetReply.bodyPreview
                        ),
                        fontSize: 16
                    )
                }

                if capabilities.supportsImageUpload {
                    HStack(spacing: 12) {
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 9,
                            matching: .images
                        ) {
                            Label("添加图片", systemImage: "photo.on.rectangle.angled")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PaperTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(isSubmitting)

                        Button {
                            showsEmojiPicker = true
                        } label: {
                            Label("添加表情", systemImage: "face.smiling")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PaperTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting)
                    }

                    if !attachments.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(attachments) { attachment in
                                    attachmentPreview(for: attachment)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }

                ReplyComposerRichTextEditor(
                    text: $text,
                    pendingEmojiInsertion: $pendingEmojiInsertion,
                    shouldFocus: $shouldFocusRichEditor,
                    isEditable: !isSubmitting
                )
                .frame(minHeight: 180)
                .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack {
                    Text("\(ReplyComposerRichTextEditor.displayCharacterCount(from: text)) 字")
                        .font(.caption)
                        .foregroundStyle(PaperTheme.mutedText)
                    Spacer()
                    if !attachments.isEmpty {
                        Text("\(attachments.count) 张图片")
                            .font(.caption)
                            .foregroundStyle(PaperTheme.mutedText)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(PaperBackground())
            .navigationTitle("写回复")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await loadSelectedImages(items)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", action: onCancel)
                        .disabled(isSubmitting)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSubmit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("发送")
                        }
                    }
                    .disabled(isSubmitting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("图片处理失败", isPresented: imageLoadErrorBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(imageLoadErrorMessage ?? "请换一张图片重试。")
            }
            .sheet(isPresented: $showsEmojiPicker) {
                NGAEmojiPickerSheet { emoji in
                    pendingEmojiInsertion = emoji
                    shouldFocusRichEditor = true
                    showsEmojiPicker = false
                }
            }
        }
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
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(attachment.filename)
                    .font(.caption2)
                    .foregroundStyle(PaperTheme.mutedText)
                    .lineLimit(1)
                    .frame(width: 96)
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

struct ReplyComposerRichTextEditor: UIViewRepresentable {
    private static let emojiAnchorCharacter = "\u{200B}"
    private static let emojiMarkupAttribute = NSAttributedString.Key("ForumHubEmojiMarkup")
    @Binding var text: String
    @Binding var pendingEmojiInsertion: NGAForumEmojiItem?
    @Binding var shouldFocus: Bool
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, pendingEmojiInsertion: $pendingEmojiInsertion, shouldFocus: $shouldFocus)
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
        context.coordinator.attach(to: textView)
        context.coordinator.synchronizeExternalMarkupIfNeeded(text, to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.isEditable = isEditable
        textView.isSelectable = true
        context.coordinator.attach(to: textView)
        context.coordinator.synchronizeExternalMarkupIfNeeded(text, to: textView)
        context.coordinator.schedulePendingEmojiInsertionIfNeeded(into: textView)
        context.coordinator.updateFocusIfNeeded(for: textView)
    }

    static func displayCharacterCount(from markup: String) -> Int {
        let components = parseComponents(from: markup)
        return components.reduce(0) { partial, component in
            switch component {
            case let .text(text):
                return partial + text.trimmingCharacters(in: .whitespacesAndNewlines).count
            case .emoji:
                return partial + 1
            }
        }
    }

    private static let emojiPattern = #"\[img\](https://img4\.nga\.178\.com/ngabbs/post/smile/([^/\]]+))\[/img\]"#

    static func parseComponents(from markup: String) -> [ReplyComposerComponent] {
        guard let regex = try? NSRegularExpression(pattern: emojiPattern, options: [.caseInsensitive]) else {
            return [.text(markup)]
        }

        let range = NSRange(markup.startIndex..<markup.endIndex, in: markup)
        let matches = regex.matches(in: markup, range: range)
        guard !matches.isEmpty else { return [.text(markup)] }

        var components: [ReplyComposerComponent] = []
        var cursor = markup.startIndex

        for match in matches {
            guard let matchRange = Range(match.range(at: 0), in: markup) else { continue }

            if cursor < matchRange.lowerBound {
                components.append(.text(String(markup[cursor..<matchRange.lowerBound])))
            }

            if let urlRange = Range(match.range(at: 1), in: markup),
               let filenameRange = Range(match.range(at: 2), in: markup),
               let imageURL = URL(string: String(markup[urlRange])),
               let emoji = NGAForumEmojiItem(filename: String(markup[filenameRange]), imageURL: imageURL) {
                components.append(.emoji(emoji))
            } else {
                components.append(.text(String(markup[matchRange])))
            }

            cursor = matchRange.upperBound
        }

        if cursor < markup.endIndex {
            components.append(.text(String(markup[cursor...])))
        }

        return components
    }

    enum ReplyComposerComponent {
        case text(String)
        case emoji(NGAForumEmojiItem)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private static let emojiInsertionRetryDelay: TimeInterval = 0.05
        private static let maximumEmojiInsertionRetryCount = 12
        @Binding private var text: String
        @Binding private var pendingEmojiInsertion: NGAForumEmojiItem?
        @Binding private var shouldFocus: Bool
        private weak var textView: UITextView?
        private var isApplyingProgrammaticChange = false
        private var hasInitializedTextView = false
        private var scheduledEmojiInsertionID: String?
        private var lastCommittedMarkup = ""

        init(
            text: Binding<String>,
            pendingEmojiInsertion: Binding<NGAForumEmojiItem?>,
            shouldFocus: Binding<Bool>
        ) {
            _text = text
            _pendingEmojiInsertion = pendingEmojiInsertion
            _shouldFocus = shouldFocus
        }

        func attach(to textView: UITextView) {
            self.textView = textView
        }

        func synchronizeExternalMarkupIfNeeded(_ markup: String, to textView: UITextView) {
            guard !hasInitializedTextView || markup != lastCommittedMarkup else {
                hasInitializedTextView = true
                return
            }

            let selectedRange = textView.selectedRange
            let font = textView.font ?? .preferredFont(forTextStyle: .body)
            isApplyingProgrammaticChange = true
            textView.attributedText = attributedText(from: markup, font: font, textView: textView)
            textView.typingAttributes = Self.baseAttributes(for: font)
            textView.selectedRange = NSRange(location: min(selectedRange.location, textView.attributedText.length), length: 0)
            isApplyingProgrammaticChange = false
            hasInitializedTextView = true
            lastCommittedMarkup = markup
        }

        func schedulePendingEmojiInsertionIfNeeded(into textView: UITextView) {
            guard let emoji = pendingEmojiInsertion else {
                scheduledEmojiInsertionID = nil
                return
            }
            guard scheduledEmojiInsertionID != emoji.id else { return }

            scheduledEmojiInsertionID = emoji.id
            attemptEmojiInsertion(emoji, into: textView, attempt: 0)
        }

        private func performEmojiInsertion(_ emoji: NGAForumEmojiItem, into textView: UITextView) -> Bool {
            guard textView.window != nil else { return false }

            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            let insertionRange = textView.selectedRange
            let font = textView.font ?? .preferredFont(forTextStyle: .body)
            let replacement = NSMutableAttributedString(attributedString: Self.makeEmojiAttachment(for: emoji, font: font, textView: textView))
            replacement.append(NSAttributedString(string: ReplyComposerRichTextEditor.emojiAnchorCharacter, attributes: Self.baseAttributes(for: font)))
            mutable.replaceCharacters(in: insertionRange, with: replacement)

            isApplyingProgrammaticChange = true
            textView.attributedText = mutable
            textView.typingAttributes = Self.baseAttributes(for: font)
            let nextLocation = min(insertionRange.location + replacement.length, textView.attributedText.length)
            textView.selectedRange = NSRange(location: nextLocation, length: 0)
            isApplyingProgrammaticChange = false
            return true
        }

        private func attemptEmojiInsertion(_ emoji: NGAForumEmojiItem, into textView: UITextView, attempt: Int) {
            let work = { [weak self, weak textView] in
                guard let self, let textView else { return }
                guard self.pendingEmojiInsertion?.id == emoji.id else {
                    self.scheduledEmojiInsertionID = nil
                    return
                }

                if self.performEmojiInsertion(emoji, into: textView) {
                    self.commitMarkup(from: textView)
                    self.pendingEmojiInsertion = nil
                    self.scheduledEmojiInsertionID = nil
                    return
                }

                guard attempt < Self.maximumEmojiInsertionRetryCount else {
                    self.scheduledEmojiInsertionID = nil
                    return
                }

                self.attemptEmojiInsertion(emoji, into: textView, attempt: attempt + 1)
            }

            if attempt == 0 {
                DispatchQueue.main.async(execute: work)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.emojiInsertionRetryDelay, execute: work)
            }
        }

        func updateFocusIfNeeded(for textView: UITextView) {
            guard shouldFocus else { return }
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
            DispatchQueue.main.async { [weak self] in
                self?.shouldFocus = false
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            commitMarkup(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange else { return }
            let adjustedLocation = adjustedCaretLocation(for: textView.selectedRange.location, in: textView.attributedText)
            guard adjustedLocation != textView.selectedRange.location else { return }

            isApplyingProgrammaticChange = true
            textView.selectedRange = NSRange(location: adjustedLocation, length: 0)
            isApplyingProgrammaticChange = false
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText: String
        ) -> Bool {
            guard !isApplyingProgrammaticChange else { return true }

            let adjustedRange = adjustedEditingRange(for: range, replacementText: replacementText, in: textView.attributedText)
            guard adjustedRange != range else { return true }

            let font = textView.font ?? .preferredFont(forTextStyle: .body)
            let replacement = NSAttributedString(string: replacementText, attributes: Self.baseAttributes(for: font))
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            mutable.replaceCharacters(in: adjustedRange, with: replacement)

            isApplyingProgrammaticChange = true
            textView.attributedText = mutable
            textView.typingAttributes = Self.baseAttributes(for: font)
            let nextLocation = min(adjustedRange.location + replacement.length, textView.attributedText.length)
            textView.selectedRange = NSRange(location: nextLocation, length: 0)
            isApplyingProgrammaticChange = false
            commitMarkup(from: textView)
            return false
        }

        private func attributedText(from markup: String, font: UIFont, textView: UITextView) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let baseAttributes = Self.baseAttributes(for: font)

            for component in ReplyComposerRichTextEditor.parseComponents(from: markup) {
                switch component {
                case let .text(text):
                    result.append(NSAttributedString(string: text, attributes: baseAttributes))
                case let .emoji(emoji):
                    result.append(Self.makeEmojiAttachment(for: emoji, font: font, textView: textView))
                    result.append(NSAttributedString(string: ReplyComposerRichTextEditor.emojiAnchorCharacter, attributes: baseAttributes))
                }
            }

            if result.length == 0 {
                result.append(NSAttributedString(string: "", attributes: baseAttributes))
            }
            return result
        }

        private func serialize(_ attributedText: NSAttributedString) -> String {
            let fullRange = NSRange(location: 0, length: attributedText.length)
            var result = ""

            attributedText.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
                if let markup = attributes[ReplyComposerRichTextEditor.emojiMarkupAttribute] as? String {
                    result += markup
                } else {
                    result += attributedText.attributedSubstring(from: range).string
                        .replacingOccurrences(of: ReplyComposerRichTextEditor.emojiAnchorCharacter, with: "")
                }
            }

            return result
        }

        private func commitMarkup(from textView: UITextView) {
            let serialized = serialize(textView.attributedText)
            lastCommittedMarkup = serialized
            text = serialized
            hasInitializedTextView = true
        }

        private func adjustedCaretLocation(for location: Int, in attributedText: NSAttributedString) -> Int {
            let length = attributedText.length
            guard length > 0, location < length else { return location }

            if isEmojiAnchor(at: location, in: attributedText), hasEmojiAttachment(at: location - 1, in: attributedText) {
                return min(location + 1, length)
            }

            return location
        }

        private func adjustedEditingRange(
            for range: NSRange,
            replacementText: String,
            in attributedText: NSAttributedString
        ) -> NSRange {
            guard replacementText.isEmpty, range.length == 1 else { return range }

            let location = range.location
            let length = attributedText.length
            guard location >= 0, location < length else { return range }

            if isEmojiAnchor(at: location, in: attributedText), hasEmojiAttachment(at: location - 1, in: attributedText) {
                return NSRange(location: max(location - 1, 0), length: min(2, length - max(location - 1, 0)))
            }

            if hasEmojiAttachment(at: location, in: attributedText),
               isEmojiAnchor(at: location + 1, in: attributedText) {
                return NSRange(location: location, length: min(2, length - location))
            }

            return range
        }

        private func isEmojiAnchor(at location: Int, in attributedText: NSAttributedString) -> Bool {
            guard location >= 0, location < attributedText.length else { return false }
            let substring = attributedText.attributedSubstring(from: NSRange(location: location, length: 1)).string
            return substring == ReplyComposerRichTextEditor.emojiAnchorCharacter
        }

        private func hasEmojiAttachment(at location: Int, in attributedText: NSAttributedString) -> Bool {
            guard location >= 0, location < attributedText.length else { return false }
            return attributedText.attribute(ReplyComposerRichTextEditor.emojiMarkupAttribute, at: location, effectiveRange: nil) != nil
        }

        static func baseAttributes(for font: UIFont) -> [NSAttributedString.Key: Any] {
            [
                .font: font,
                .foregroundColor: UIColor(PaperTheme.secondaryInk)
            ]
        }

        private static func makeEmojiAttachment(for emoji: NGAForumEmojiItem, font: UIFont, textView: UITextView) -> NSAttributedString {
            let attachment = NSTextAttachment()
            attachment.bounds = CGRect(x: 0, y: -4, width: font.lineHeight + 8, height: font.lineHeight + 8)
            attachment.image = emoji.previewImage ?? placeholderEmojiImage(side: font.lineHeight + 8)
            let result = NSMutableAttributedString(attachment: attachment)
            result.addAttribute(ReplyComposerRichTextEditor.emojiMarkupAttribute, value: emoji.markup, range: NSRange(location: 0, length: result.length))
            if emoji.previewImage == nil {
                loadEmojiImageIfNeeded(for: attachment, emoji: emoji, textView: textView)
            }
            return result
        }

        private static func placeholderEmojiImage(side: CGFloat) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
            return renderer.image { _ in
                let rect = CGRect(origin: .zero, size: CGSize(width: side, height: side))
                UIColor(PaperTheme.paperDeep).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()

                let config = UIImage.SymbolConfiguration(pointSize: side * 0.56, weight: .regular)
                let image = UIImage(systemName: "face.smiling", withConfiguration: config)?
                    .withTintColor(UIColor(PaperTheme.mutedText), renderingMode: .alwaysOriginal)
                let imageRect = CGRect(x: side * 0.2, y: side * 0.2, width: side * 0.6, height: side * 0.6)
                image?.draw(in: imageRect)
            }
        }

        private static func loadEmojiImageIfNeeded(for attachment: NSTextAttachment, emoji: NGAForumEmojiItem, textView: UITextView) {
            Task {
                if let image = try? await NGAImageLoader.load(url: emoji.imageURL) {
                    await MainActor.run {
                        attachment.image = image
                        let fullRange = NSRange(location: 0, length: textView.attributedText.length)
                        textView.layoutManager.invalidateDisplay(forCharacterRange: fullRange)
                        textView.layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
                        textView.setNeedsDisplay()
                    }
                }
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
