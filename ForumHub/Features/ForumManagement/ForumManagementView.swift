import SwiftUI

struct ForumManagementView: View {
    let channels: [ForumChannel]
    @Bindable var subscriptions: ForumSubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredChannels) { channel in
                        Toggle(isOn: binding(for: channel)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(channel.title)
                                    .foregroundStyle(PaperTheme.ink)
                                Text(channel.source == .nga ? "fid \(channel.id)" : channel.nativeKey)
                                    .font(.caption)
                                    .foregroundStyle(PaperTheme.mutedText)
                            }
                        }
                        .tint(PaperTheme.accent)
                        .listRowBackground(PaperTheme.card)
                    }
                } header: {
                    Text("全部栏目 · 已订阅 \(channels.filter(subscriptions.isSubscribed).count)")
                } footer: {
                    Text("首页顶部按照社区返回的顺序展示已订阅栏目，至少需要保留一个。")
                }

                Section {
                    Button("恢复默认订阅") {
                        subscriptions.restoreDefaults(for: channels)
                    }
                    .foregroundStyle(PaperTheme.accent)
                    .listRowBackground(PaperTheme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .searchable(text: $searchText, prompt: "搜索栏目")
            .navigationTitle("管理栏目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var filteredChannels: [ForumChannel] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return channels }
        return channels.filter {
            $0.title.localizedCaseInsensitiveContains(keyword) || String($0.id).contains(keyword)
        }
    }

    private func binding(for channel: ForumChannel) -> Binding<Bool> {
        Binding(
            get: { subscriptions.isSubscribed(channel) },
            set: { subscriptions.setSubscribed($0, for: channel) }
        )
    }
}
