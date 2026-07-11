import Foundation

enum UITestScenario: String, CaseIterable {
    case defaultFeed = "UITEST_DEFAULT_FEED"
    case sourceSwitch = "UITEST_SOURCE_SWITCH"
    case pagedThread = "UITEST_PAGED_THREAD"

    static var current: UITestScenario? {
        let arguments = ProcessInfo.processInfo.arguments
        return allCases.first { arguments.contains($0.rawValue) }
    }

    @MainActor
    func makeViewModel() -> ForumViewModel {
        switch self {
        case .pagedThread:
            return .pagedPreview()
        case .defaultFeed, .sourceSwitch:
            let repositories: [ForumSource: any ThreadRepository] = [
                .nga: MockThreadRepository(source: .nga),
                .v2ex: MockThreadRepository(source: .v2ex),
                .linuxDo: MockThreadRepository(source: .linuxDo)
            ]
            let viewModel = ForumViewModel(repositories: repositories, initialSource: .nga)
            viewModel.isAuthenticated = false
            viewModel.loginState = .empty
            viewModel.forum = ForumPayload.mock.forum
            viewModel.channels = ForumPayload.mock.channels
            viewModel.pinnedThreads = ForumPayload.mock.pinned
            viewModel.threads = ForumPayload.mock.threads
            viewModel.hasLoadedInitialFeed = true
            return viewModel
        }
    }
}
