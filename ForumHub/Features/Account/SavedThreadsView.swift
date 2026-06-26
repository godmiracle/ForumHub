import SwiftUI

struct SavedThreadsView: View {
    @Bindable var favorites: FavoriteThreadsStore
    @Bindable var blockedUsers: BlockedUsersStore
    let repositoryForSource: (ForumSource) -> any ThreadRepository
    @State private var showsClearConfirmation = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header

                if favorites.entries.isEmpty {
                    ContentUnavailableView(
                        "还没有收藏帖子",
                        systemImage: "star",
                        description: Text("在帖子列表或详情页点击收藏后，会显示在这里。")
                    )
                    .foregroundStyle(PaperTheme.mutedText)
                    .padding(.top, 90)
                } else if visibleEntries.isEmpty {
                    BlockedThreadsNotice()
                        .padding(.vertical, 60)
                } else {
                    ForEach(visibleEntries) { entry in
                        BlockableThreadLink(
                            thread: entry.thread,
                            repository: repositoryForSource(entry.source),
                            blockedUsers: blockedUsers,
                            favoriteThreads: favorites
                        )
                    }
                }

                Color.clear.frame(height: 112)
            }
        }
        .confirmationDialog("清空本地收藏？", isPresented: $showsClearConfirmation) {
            Button("清空", role: .destructive) { favorites.clear() }
            Button("取消", role: .cancel) {}
        }
        .navigationTitle("本地收藏")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("本地收藏")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(PaperTheme.ink)
                Text("跨社区保存你想稍后再看的帖子")
                    .font(.subheadline)
                    .foregroundStyle(PaperTheme.mutedText)
            }
            Spacer()
            if !favorites.entries.isEmpty {
                Button("清空", role: .destructive) { showsClearConfirmation = true }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var visibleEntries: [SavedForumThread] {
        favorites.entries.filter {
            !blockedUsers.isBlocked(source: $0.source, username: $0.author)
        }
    }
}
