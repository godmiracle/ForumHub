import SwiftUI
import UniformTypeIdentifiers

struct CommunityView: View {
    let activeSource: ForumSource
    let channels: [ForumChannel]
    let isLoading: Bool
    @Bindable var subscriptions: ForumSubscriptionStore
    let scrollRequest: TabScrollRequest?
    let onChannelSelect: (ForumChannel) async -> Void
    @State private var searchText = ""
    @State private var draggedChannelKey: String?
    private let topAnchorID = "community-top-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 1)
                    .id(topAnchorID)

                LazyVStack(alignment: .leading, spacing: 20) {
                    header
                    reorderSection
                    channelHeader
                    searchField
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(filteredChannels) { channel in
                            channelRow(channel)
                        }
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
        VStack(alignment: .leading, spacing: 5) {
            Text("栏目管理")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(PaperTheme.ink)
            Text("管理 \(activeSource.title) 在首页展示的栏目")
                .font(.subheadline)
                .foregroundStyle(PaperTheme.mutedText)
        }
    }

    private var channelHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(activeSource.title) 全部栏目")
                    .font(.headline)
                    .foregroundStyle(PaperTheme.ink)
                Text("已选择 \(subscribedChannelCount) 个在首页展示")
                    .font(.caption)
                    .foregroundStyle(PaperTheme.mutedText)
            }
            Spacer()
            if isLoading { ProgressView().tint(PaperTheme.accent) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            TextField("搜索栏目", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .foregroundStyle(PaperTheme.mutedText)
        .padding(12)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var reorderSection: some View {
        let subscribed = subscriptions.visibleChannels(from: channels)

        VStack(alignment: .leading, spacing: 12) {
            Text("首页展示顺序")
                .font(.headline)
                .foregroundStyle(PaperTheme.ink)

            Text("长按并上下拖动已订阅栏目，可以直接调整首页顶部的展示顺序。")
                .font(.caption)
                .foregroundStyle(PaperTheme.mutedText)

            if subscribed.isEmpty {
                Text("至少保留一个栏目后，才会在这里显示可排序项。")
                    .font(.subheadline)
                    .foregroundStyle(PaperTheme.mutedText)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(subscribed) { channel in
                        subscribedChannelRow(channel, allSubscribedChannels: subscribed)
                    }
                }
            }
        }
    }

    private var filteredChannels: [ForumChannel] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return channels }
        return channels.filter {
            $0.title.localizedCaseInsensitiveContains(keyword)
                || $0.nativeKey.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var subscribedChannelCount: Int {
        channels.filter(subscriptions.isSubscribed).count
    }

    private func channelRow(_ channel: ForumChannel) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await onChannelSelect(channel) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(PaperTheme.ink)
                    Text(channel.source == .nga ? "fid \(channel.id)" : channel.nativeKey)
                        .font(.caption)
                        .foregroundStyle(PaperTheme.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: subscriptionBinding(channel))
                .labelsHidden()
                .tint(PaperTheme.accent)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func subscribedChannelRow(_ channel: ForumChannel, allSubscribedChannels: [ForumChannel]) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await onChannelSelect(channel) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(PaperTheme.ink)
                    Text(channel.source == .nga ? "fid \(channel.id)" : channel.nativeKey)
                        .font(.caption)
                        .foregroundStyle(PaperTheme.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PaperTheme.mutedText)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    draggedChannelKey == channelDragKey(channel)
                        ? PaperTheme.accent.opacity(0.3)
                        : PaperTheme.hairline,
                    lineWidth: 1
                )
        }
        .opacity(draggedChannelKey == channelDragKey(channel) ? 0.72 : 1)
        .onDrag {
            draggedChannelKey = channelDragKey(channel)
            return NSItemProvider(object: channelDragKey(channel) as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: CommunityChannelDropDelegate(
                destination: channel,
                channels: allSubscribedChannels,
                subscriptions: subscriptions,
                draggedChannelKey: $draggedChannelKey
            )
        )
    }

    private func channelDragKey(_ channel: ForumChannel) -> String {
        "\(channel.source.rawValue):\(channel.nativeKey)"
    }

    private func subscriptionBinding(_ channel: ForumChannel) -> Binding<Bool> {
        Binding(
            get: { subscriptions.isSubscribed(channel) },
            set: { subscriptions.setSubscribed($0, for: channel) }
        )
    }
}

private struct CommunityChannelDropDelegate: DropDelegate {
    let destination: ForumChannel
    let channels: [ForumChannel]
    let subscriptions: ForumSubscriptionStore
    @Binding var draggedChannelKey: String?

    func dropEntered(info: DropInfo) {
        guard let draggedChannelKey,
              let source = channels.first(where: { channelKey($0) == draggedChannelKey }),
              channelKey(destination) != draggedChannelKey
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

    private func channelKey(_ channel: ForumChannel) -> String {
        "\(channel.source.rawValue):\(channel.nativeKey)"
    }
}
