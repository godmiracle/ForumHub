import Observation

/// 只保存由滚动位置和滚动交互驱动的展示状态。
/// 远端已加载页、分页边界和页起点仍由 `ThreadDetailPaginationState` 所有。
@MainActor
@Observable
final class ThreadDetailScrollState {
    var visiblePage = 1
    var pendingPageSelection = 1
    var deferredTargetPage: Int?
    var lastAutoLoadedPage: Int?

    func resetPageTracking() {
        visiblePage = 1
        pendingPageSelection = 1
        deferredTargetPage = nil
        lastAutoLoadedPage = nil
    }
}
