import Foundation

enum UITestScenario: String, CaseIterable {
    case defaultFeed = "UITEST_DEFAULT_FEED"
    case sourceSwitch = "UITEST_SOURCE_SWITCH"
    case pagedThread = "UITEST_PAGED_THREAD"
    case authenticatedFeed = "UITEST_AUTHENTICATED_FEED"
    case expiredFeed = "UITEST_EXPIRED_FEED"

    static var current: UITestScenario? {
        let arguments = ProcessInfo.processInfo.arguments
        return allCases.first { arguments.contains($0.rawValue) }
    }

    @MainActor
    func makeViewModel() -> ForumViewModel {
        switch self {
        case .pagedThread:
            return .pagedPreview()
        case .defaultFeed, .sourceSwitch, .authenticatedFeed, .expiredFeed:
            let repositories: [ForumSource: any ThreadRepository] = [
                .nga: MockThreadRepository(source: .nga),
                .v2ex: MockThreadRepository(source: .v2ex),
                .linuxDo: MockThreadRepository(source: .linuxDo)
            ]
            let viewModel = ForumViewModel(repositories: repositories, initialSource: .nga)
            switch self {
            case .authenticatedFeed:
                viewModel.isAuthenticated = true
                viewModel.sessionState = .authenticated
            case .expiredFeed:
                viewModel.isAuthenticated = false
                viewModel.sessionState = .expired
            case .defaultFeed, .sourceSwitch:
                viewModel.isAuthenticated = false
                viewModel.sessionState = .signedOut
            case .pagedThread:
                break
            }
            viewModel.loginState = .empty
            viewModel.forum = ForumPayload.mock.forum
            viewModel.channels = ForumPayload.mock.channels
            viewModel.pinnedThreads = ForumPayload.mock.pinned
            viewModel.threads = ForumPayload.mock.threads + (0..<12).map { index in
                ForumThread(
                    id: 91_000 + index,
                    title: "用于验证长列表折叠的主题 \(index + 1)",
                    summary: "固定 UI Test 数据",
                    author: "测试用户",
                    createdAt: "2026-07-16 20:\(String(format: "%02d", index))",
                    lastReplyAt: "2026-07-16 21:\(String(format: "%02d", index))",
                    replyCount: index,
                    viewCount: 100 + index,
                    body: "",
                    replies: []
                )
            }
            viewModel.hasLoadedInitialFeed = true
            return viewModel
        }
    }
}
