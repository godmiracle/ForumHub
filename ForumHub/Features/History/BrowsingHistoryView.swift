import SwiftUI

struct BrowsingHistoryView: View {
    @Bindable var history: BrowsingHistoryStore
    @Bindable var blockedUsers: BlockedUsersStore
    @Bindable var favoriteThreads: FavoriteThreadsStore
    let scrollToTopTrigger: Int
    let repositoryForSource: (ForumSource) -> any ThreadRepository
    @State private var showsClearConfirmation = false
    private let topAnchorID = "history-top-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 1)
                    .id(topAnchorID)

                LazyVStack(alignment: .leading, spacing: 0) {
                    header

                    if history.entries.isEmpty {
                        ContentUnavailableView(
                            "还没有浏览足迹",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("打开帖子后会自动记录，最多保留最近 50 条。")
                        )
                        .foregroundStyle(PaperTheme.mutedText)
                        .padding(.top, 90)
                    } else {
                        ForEach(visibleEntries) { entry in
                            NavigationLink {
                                ThreadDetailView(
                                    thread: entry.thread,
                                    repository: repositoryForSource(entry.source),
                                    blockedUsers: blockedUsers,
                                    favoriteThreads: favoriteThreads
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(entry.source.title)
                                            .font(.caption.bold())
                                            .foregroundStyle(PaperTheme.accent)
                                        Spacer()
                                        Text(entry.visitedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(PaperTheme.mutedText)
                                    }
                                    Text(entry.title)
                                        .font(.system(size: 18, weight: .semibold, design: .serif))
                                        .foregroundStyle(PaperTheme.ink)
                                        .multilineTextAlignment(.leading)
                                    Text(entry.author)
                                        .font(.subheadline)
                                        .foregroundStyle(PaperTheme.mutedText)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 15)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(PaperTheme.card)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(PaperTheme.hairline).frame(height: 0.7)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Color.clear.frame(height: 112)
                }
            }
            .onChange(of: scrollToTopTrigger) {
                withAnimation(.snappy(duration: 0.28)) {
                    proxy.scrollTo(topAnchorID, anchor: .top)
                }
            }
        }
        .confirmationDialog("清空浏览足迹？", isPresented: $showsClearConfirmation) {
            Button("清空", role: .destructive) { history.clear() }
            Button("取消", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("浏览足迹")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(PaperTheme.ink)
                Text("跨社区保存最近打开的帖子")
                    .font(.subheadline)
                    .foregroundStyle(PaperTheme.mutedText)
            }
            Spacer()
            if !history.entries.isEmpty {
                Button("清空", role: .destructive) { showsClearConfirmation = true }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var visibleEntries: [BrowsingHistoryEntry] {
        history.entries.filter {
            !blockedUsers.isBlocked(source: $0.source, username: $0.author)
        }
    }
}
