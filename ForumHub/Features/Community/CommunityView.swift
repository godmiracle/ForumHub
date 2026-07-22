import SwiftUI
import UniformTypeIdentifiers

struct CommunityView: View {
    let catalog: ForumChannelCatalog
    let isLoading: Bool
    let pendingNewChildKeys: Set<String>
    let cancelledSubscriptionNotice: String?
    @Bindable var subscriptions: ForumSubscriptionStore
    let scrollRequest: TabScrollRequest?
    let onChannelSelect: (ForumChannel) async -> Void
    let onCancelledSubscriptionNoticeDismiss: () -> Void
    @State private var searchText = ""
    @State private var isEditingOrder = false
    @State private var draggedChannelKey: String?
    private let topAnchorID = "community-top-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 1)
                    .id(topAnchorID)

                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    searchField

                    if let cancelledSubscriptionNotice {
                        statusBanner(cancelledSubscriptionNotice)
                    }

                    if normalizedSearchText.isEmpty {
                        subscribedSection
                        browseSection
                    } else {
                        searchResultsSection
                    }

                    Color.clear.frame(height: 112)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .onChange(of: scrollRequest) { _, request in
                guard request?.targets(.community) == true else { return }
                withAnimation(.snappy(duration: 0.28)) {
                    proxy.scrollTo(topAnchorID, anchor: .top)
                }
            }
        }
        .accessibilityIdentifier("community-screen")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("栏目")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(PaperTheme.ink)
                Text("管理 \(catalog.source.title) 首页展示内容")
                    .font(.subheadline)
                    .foregroundStyle(PaperTheme.mutedText)
            }
            Spacer(minLength: 8)
            if isLoading {
                ProgressView()
                    .tint(PaperTheme.accent)
                    .accessibilityLabel("正在更新栏目")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
            TextField("搜索栏目、子版或编号", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空栏目搜索")
            }
        }
        .foregroundStyle(PaperTheme.mutedText)
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(PaperTheme.hairline, lineWidth: 1)
        }
        .accessibilityIdentifier("community-search-field")
    }

    private var subscribedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("已添加到首页", subtitle: "\(subscribedItems.count) 个栏目")
                Spacer()
                if subscribedItems.count > 1 {
                    Button(isEditingOrder ? "完成" : "编辑排序") {
                        withAnimation(.snappy(duration: 0.22)) {
                            isEditingOrder.toggle()
                            if !isEditingOrder { draggedChannelKey = nil }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PaperTheme.accent)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("community-reorder-button")
                }
            }

            if subscribedItems.isEmpty {
                Text("至少保留一个栏目后，才会在这里显示首页顺序。")
                    .font(.subheadline)
                    .foregroundStyle(PaperTheme.mutedText)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(subscribedItems) { item in
                        if isEditingOrder {
                            reorderRow(item)
                        } else {
                            channelRow(item)
                        }
                    }
                }
            }
        }
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("浏览全部栏目", subtitle: "点击栏目打开，使用右侧按钮添加")

            if catalog.source == .nga {
                VStack(alignment: .leading, spacing: 10) {
                    groupTitle("网事杂谈子版", count: catalog.authoritativeChildren.count)
                    if catalog.hasConfirmedAuthoritativeChildren {
                        itemList(catalog.authoritativeChildren)
                    } else {
                        Text("权威子版目录暂时无法更新；普通栏目仍可使用。")
                            .font(.subheadline)
                            .foregroundStyle(PaperTheme.mutedText)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityIdentifier("community-child-directory-unavailable")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                groupTitle(catalog.source == .nga ? "其他 NGA 栏目" : "全部栏目", count: catalog.standardChannels.count)
                itemList(catalog.standardChannels)
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("搜索结果", subtitle: "匹配 \(filteredItems.count) 个栏目")
            if filteredItems.isEmpty {
                ContentUnavailableView.search(text: normalizedSearchText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("community-search-empty")
            } else {
                itemList(filteredItems)
            }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .foregroundStyle(PaperTheme.ink)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(PaperTheme.mutedText)
        }
    }

    private func groupTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PaperTheme.secondaryInk)
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(PaperTheme.mutedText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(PaperTheme.paperDeep.opacity(0.55), in: Capsule())
        }
        .padding(.horizontal, 2)
    }

    private func itemList(_ items: [ForumChannelCatalogItem]) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(items) { item in
                channelRow(item)
            }
        }
    }

    private func channelRow(_ item: ForumChannelCatalogItem) -> some View {
        HStack(spacing: 12) {
            channelOpenButton(item)
            subscriptionButton(item)
        }
        .padding(.leading, 15)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PaperTheme.hairline, lineWidth: 1)
        }
        .accessibilityIdentifier("community-channel-\(item.id)")
    }

    private func reorderRow(_ item: ForumChannelCatalogItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PaperTheme.mutedText)
                .frame(width: 28, height: 44)
                .accessibilityHidden(true)
            channelText(item)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(draggedChannelKey == item.id ? PaperTheme.accent.opacity(0.35) : PaperTheme.hairline, lineWidth: 1)
        }
        .opacity(draggedChannelKey == item.id ? 0.72 : 1)
        .onDrag {
            draggedChannelKey = item.id
            return NSItemProvider(object: item.id as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: CommunityChannelDropDelegate(
                destination: item.channel,
                channels: subscribedItems.map(\.channel),
                subscriptions: subscriptions,
                draggedChannelKey: $draggedChannelKey
            )
        )
        .accessibilityLabel("\(item.title)，可重新排序")
        .accessibilityIdentifier("community-reorder-\(item.id)")
    }

    private func channelOpenButton(_ item: ForumChannelCatalogItem) -> some View {
        Button {
            Task { await onChannelSelect(item.channel) }
        } label: {
            channelText(item)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(openAccessibilityLabel(item))
        .accessibilityHint("打开该栏目")
        .frame(minHeight: 44)
    }

    private func channelText(_ item: ForumChannelCatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(item.title)
                    .font(.system(.body, design: .serif, weight: .semibold))
                    .foregroundStyle(PaperTheme.ink)
                    .multilineTextAlignment(.leading)
                if pendingNewChildKeys.contains(item.channel.nativeKey) {
                    Text("新")
                        .font(.caption2.bold())
                        .foregroundStyle(PaperTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PaperTheme.accent.opacity(0.1), in: Capsule())
                }
            }
            Text(item.contextTitle ?? displayIdentifier(item.channel))
                .font(.caption)
                .foregroundStyle(PaperTheme.mutedText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subscriptionButton(_ item: ForumChannelCatalogItem) -> some View {
        let isSubscribed = subscriptions.isSubscribed(item.channel)
        let cannotRemove = isSubscribed && subscribedItems.count <= 1
        return Button {
            subscriptions.setSubscribed(!isSubscribed, for: item.channel)
        } label: {
            Image(systemName: isSubscribed ? "checkmark" : "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isSubscribed ? Color.white : PaperTheme.accent)
                .frame(width: 44, height: 44)
                .background(isSubscribed ? PaperTheme.accent : PaperTheme.accent.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(cannotRemove)
        .opacity(cannotRemove ? 0.55 : 1)
        .accessibilityLabel("\(item.title)，\(isSubscribed ? "已添加到首页" : "添加到首页")")
        .accessibilityHint(cannotRemove ? "当前来源至少保留一个栏目" : isSubscribed ? "从首页移除" : "添加到首页")
        .accessibilityIdentifier("community-subscription-\(item.id)")
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(PaperTheme.accent)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(PaperTheme.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("知道了", action: onCancelledSubscriptionNoticeDismiss)
                .font(.caption.bold())
                .foregroundStyle(PaperTheme.accent)
        }
        .padding(14)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .accessibilityIdentifier("community-cancelled-subscription-notice")
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredItems: [ForumChannelCatalogItem] {
        catalog.items.filter { $0.matches(normalizedSearchText) }
    }

    private var subscribedItems: [ForumChannelCatalogItem] {
        let byKey = Dictionary(uniqueKeysWithValues: catalog.items.map { ($0.id, $0) })
        return subscriptions.visibleChannels(from: catalog.channels).compactMap { byKey[$0.canonicalKey] }
    }

    private func displayIdentifier(_ channel: ForumChannel) -> String {
        channel.source == .nga ? channel.canonicalNativeKey : channel.nativeKey
    }

    private func openAccessibilityLabel(_ item: ForumChannelCatalogItem) -> String {
        [item.title, item.contextTitle, displayIdentifier(item.channel)]
            .compactMap { $0 }
            .joined(separator: "，")
    }
}

private struct CommunityChannelDropDelegate: DropDelegate {
    let destination: ForumChannel
    let channels: [ForumChannel]
    let subscriptions: ForumSubscriptionStore
    @Binding var draggedChannelKey: String?

    func dropEntered(info: DropInfo) {
        guard let draggedChannelKey,
              let source = channels.first(where: { $0.canonicalKey == draggedChannelKey }),
              destination.canonicalKey != draggedChannelKey
        else { return }

        subscriptions.moveSubscribedChannel(source: source, before: destination, in: channels)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedChannelKey = nil
        return true
    }
}
