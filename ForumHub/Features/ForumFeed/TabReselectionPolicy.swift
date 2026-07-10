import Foundation

struct TabScrollRequest: Equatable, Identifiable {
    let id: Int
    let target: FeedTab

    func targets(_ tab: FeedTab) -> Bool {
        target == tab
    }
}

enum TabReselectionBehavior: Equatable {
    case scrollToTop
    case scrollToTopAndRefresh
}

enum TabReselectionPolicy {
    static func behavior(for tab: FeedTab) -> TabReselectionBehavior {
        switch tab {
        case .home, .hot:
            return .scrollToTopAndRefresh
        case .community, .history, .user:
            return .scrollToTop
        }
    }
}
