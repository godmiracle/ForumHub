import SwiftUI

struct BlockedUsersView: View {
    @Bindable var blockedUsers: BlockedUsersStore
    @State private var showsClearConfirmation = false

    var body: some View {
        List {
            if blockedUsers.blockedUsers.isEmpty {
                ContentUnavailableView(
                    "没有屏蔽用户",
                    systemImage: "person.crop.circle.badge.checkmark",
                    description: Text("长按帖子可将发帖用户加入屏蔽名单。")
                )
                .foregroundStyle(PaperTheme.secondaryInk)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(blockedUsers.blockedUsers) { user in
                        HStack(spacing: 12) {
                            AvatarView(name: user.username)
                                .scaleEffect(0.82)
                                .frame(width: 40, height: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.username)
                                    .font(.system(size: 17, weight: .medium, design: .serif))
                                    .foregroundStyle(PaperTheme.ink)
                                Text(user.source.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PaperTheme.mutedText)
                            }

                            Spacer()

                            Button("解除") {
                                blockedUsers.unblock(user)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PaperTheme.accent)
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(PaperTheme.card)
                        .swipeActions {
                            Button("解除", role: .destructive) {
                                blockedUsers.unblock(user)
                            }
                        }
                    }
                } header: {
                    Text("已屏蔽 \(blockedUsers.blockedUsers.count) 位用户")
                } footer: {
                    Text("这些用户发布的主题会从首页、热门、搜索和收藏列表中隐藏。")
                }

                Section {
                    Button("清空屏蔽名单", role: .destructive) {
                        showsClearConfirmation = true
                    }
                    .listRowBackground(PaperTheme.card)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("我的屏蔽")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("清空全部屏蔽用户？", isPresented: $showsClearConfirmation) {
            Button("清空屏蔽名单", role: .destructive) {
                blockedUsers.removeAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空后，这些用户的帖子会重新显示。")
        }
    }
}
