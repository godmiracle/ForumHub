//
//  ForumHubUITests.swift
//  ForumHubUITests
//
//  Created by CJ on 2026/6/17.
//

import XCTest

final class ForumHubUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testSearchSubmissionOpensResults() throws {
        let app = launch(scenario: "UITEST_DEFAULT_FEED")

        let searchField = app.textFields["forum-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText("SwiftUI")

        let keyboard = app.keyboards.firstMatch
        let searchButton = keyboard.buttons["search"].exists
            ? keyboard.buttons["search"]
            : keyboard.buttons["搜索"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 3))
        searchButton.tap()

        XCTAssertTrue(
            app.scrollViews["search-results-screen"].waitForExistence(timeout: 8),
            "Submitting the forum search field should open the search results screen."
        )
    }

    @MainActor
    func testSwitchesFromNGAToV2EX() throws {
        let app = launch(scenario: "UITEST_SOURCE_SWITCH")

        let sourceMenu = app.buttons["current-community-button"]
        XCTAssertTrue(sourceMenu.waitForExistence(timeout: 8))
        sourceMenu.tap()

        let v2exButton = app.buttons["V2EX"]
        XCTAssertTrue(v2exButton.waitForExistence(timeout: 8))
        v2exButton.tap()

        tapBottomTab(named: "首页", in: app)

        XCTAssertTrue(
            app.textFields["forum-search-field"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.textFields["forum-search-field"].isEnabled)
        XCTAssertTrue(app.buttons["forum-channel--20002"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeShowsActionableSignedOutStateAndUnifiedFilter() throws {
        let app = launch(scenario: "UITEST_DEFAULT_FEED")

        XCTAssertTrue(app.buttons["forum-session-action-button"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["forum-compose-button"].waitForExistence(timeout: 5))

        let filter = app.buttons["feed-filter-button"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()

        let pinnedToggle = app.switches["feed-filter-pinned-toggle"]
        XCTAssertTrue(pinnedToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(pinnedToggle.value as? String, "1")
        pinnedToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let isOff = NSPredicate(format: "value == %@", "0")
        let toggled = XCTNSPredicateExpectation(predicate: isOff, object: pinnedToggle)
        wait(for: [toggled], timeout: 3)
        app.buttons["feed-filter-apply-button"].tap()

        let hasOneActiveFilter = NSPredicate(format: "label == %@", "筛选帖子，已启用 1 项")
        let updated = XCTNSPredicateExpectation(predicate: hasOneActiveFilter, object: filter)
        wait(for: [updated], timeout: 5)
    }

    @MainActor
    func testHomeHidesAuthenticatedCTAAndLabelsExpiredCTA() throws {
        let authenticated = launch(scenario: "UITEST_AUTHENTICATED_FEED")
        XCTAssertTrue(authenticated.buttons["forum-compose-button"].waitForExistence(timeout: 8))
        XCTAssertFalse(authenticated.buttons["forum-session-action-button"].exists)
        authenticated.terminate()

        let expired = launch(scenario: "UITEST_EXPIRED_FEED")
        let action = expired.buttons["forum-session-action-button"]
        XCTAssertTrue(action.waitForExistence(timeout: 8))
        XCTAssertEqual(action.label, "重新登录")
    }

    @MainActor
    func testHomeCollapsesActionsButKeepsNavigationContext() throws {
        let app = launch(scenario: "UITEST_DEFAULT_FEED")
        let search = app.textFields["forum-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))

        for _ in 0..<3 { app.swipeUp() }

        XCTAssertFalse(search.isHittable)
        XCTAssertTrue(app.buttons["forum-channel--7"].exists)
        XCTAssertTrue(app.buttons["feed-filter-button"].exists)

        app.swipeDown()
        let searchIsHittable = NSPredicate(format: "hittable == true")
        let restored = XCTNSPredicateExpectation(predicate: searchIsHittable, object: search)
        wait(for: [restored], timeout: 5)
    }

    @MainActor
    func testHomeAndHotFeedsCompletePullToRefresh() throws {
        let app = launch(scenario: "UITEST_DEFAULT_FEED")

        let homeScroll = app.scrollViews["forum-feed-home-scroll"]
        XCTAssertTrue(homeScroll.waitForExistence(timeout: 8))
        pullToRefresh(homeScroll)
        XCTAssertTrue(app.buttons["thread-row-990101"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["forum-refresh-button"].isHittable)

        tapBottomTab(named: "热门", in: app)
        let hotScroll = app.scrollViews["forum-feed-hot-scroll"]
        XCTAssertTrue(hotScroll.waitForExistence(timeout: 8))
        pullToRefresh(hotScroll)
        XCTAssertTrue(app.buttons["thread-row-990102"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["forum-refresh-button"].isHittable)
    }

    @MainActor
    func testRestoredV2EXHotShortFeedSelectsAndPullsToRefresh() throws {
        let app = launch(scenario: "UITEST_V2EX_RESTORED_HOT")

        let hotChannel = app.buttons["forum-channel--20001"]
        XCTAssertTrue(hotChannel.waitForExistence(timeout: 8))
        XCTAssertEqual(hotChannel.value as? String, "已选择")
        XCTAssertFalse(app.buttons["thread-row-990101"].exists)

        let scroll = app.scrollViews["forum-feed-home-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        pullToRefresh(scroll)

        XCTAssertTrue(
            app.buttons["thread-row-990101"].waitForExistence(timeout: 8),
            "V2EX 最热短列表的下拉手势必须触发现有 reload。"
        )
    }

    @MainActor
    func testV2EXHotLoadsMoreTopicsAtBottom() throws {
        let app = launch(scenario: "UITEST_V2EX_RESTORED_HOT")
        let scroll = app.scrollViews["forum-feed-home-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 8))
        let initial = app.buttons["thread-row-991109"]
        XCTAssertTrue(initial.waitForExistence(timeout: 5))
        XCTAssertTrue(initial.label.contains("问与答"))
        XCTAssertFalse(initial.label.contains("最热"))

        let continuation = app.buttons["thread-row-990202"]
        for _ in 0..<6 where !continuation.exists {
            scroll.swipeUp()
        }

        XCTAssertTrue(
            continuation.waitForExistence(timeout: 8),
            "V2EX 最热滚动到列表末尾后应加载 recent 续页的新帖子。"
        )
        XCTAssertTrue(continuation.label.contains("二手交易"))
        XCTAssertFalse(continuation.label.contains("最热"))
    }

    @MainActor
    func testHomeActionsRemainReachableAtAccessibilityTextSize() throws {
        let app = launch(
            scenario: "UITEST_DEFAULT_FEED",
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        )

        for identifier in [
            "current-community-button",
            "forum-refresh-button",
            "forum-compose-button",
            "forum-channel--7",
            "feed-sort-lastReply",
            "feed-sort-latestPost",
            "feed-filter-button",
            "forum-session-action-button"
        ] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 8), "\(identifier) 应在大号动态字体下存在")
            XCTAssertTrue(button.isHittable, "\(identifier) 应在大号动态字体下可点击")
        }
    }

    @MainActor
    func testHomePassesFocusedAccessibilityAudit() throws {
        let app = launch(scenario: "UITEST_DEFAULT_FEED")
        XCTAssertTrue(app.buttons["feed-filter-button"].waitForExistence(timeout: 8))

        try app.performAccessibilityAudit(for: [.hitRegion, .trait])
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            _ = launch(scenario: "UITEST_DEFAULT_FEED")
        }
    }

    @MainActor
    func testThreadDetailScrollAutoAdvancesToNextPage() throws {
        let app = launch(scenario: "UITEST_PAGED_THREAD")

        let threadRow = app.buttons["thread-row-991001"]
        if !threadRow.waitForExistence(timeout: 2) {
            for _ in 0..<4 where !threadRow.exists {
                app.swipeUp()
            }
        }
        XCTAssertTrue(threadRow.waitForExistence(timeout: 5))
        threadRow.tap()

        let detailScrollView = app.scrollViews["thread-detail-scroll"]
        XCTAssertTrue(detailScrollView.waitForExistence(timeout: 8))

        let currentPageControl = app.buttons["thread-detail-current-page"]
        XCTAssertTrue(currentPageControl.waitForExistence(timeout: 5))
        XCTAssertEqual(currentPageControl.value as? String, "1 / 7")

        var reachedSecondPage = false
        for _ in 0..<8 {
            detailScrollView.swipeUp()
            if currentPageControl.waitForExistence(timeout: 1), currentPageControl.value as? String == "2 / 7" {
                reachedSecondPage = true
                break
            }
        }

        XCTAssertTrue(reachedSecondPage, "继续上滑后应该自动切到第 2 页。")
    }

    @MainActor
    func testThreadDetailScrollToTopReturnsToFirstPage() throws {
        let app = launch(scenario: "UITEST_PAGED_THREAD")

        let threadRow = app.buttons["thread-row-991001"]
        if !threadRow.waitForExistence(timeout: 2) {
            for _ in 0..<4 where !threadRow.exists {
                app.swipeUp()
            }
        }
        XCTAssertTrue(threadRow.waitForExistence(timeout: 5))
        threadRow.tap()

        let detailScrollView = app.scrollViews["thread-detail-scroll"]
        XCTAssertTrue(detailScrollView.waitForExistence(timeout: 8))

        let currentPageControl = app.buttons["thread-detail-current-page"]
        XCTAssertTrue(currentPageControl.waitForExistence(timeout: 5))

        var reachedSecondPage = false
        for _ in 0..<8 {
            detailScrollView.swipeUp()
            if currentPageControl.waitForExistence(timeout: 1), currentPageControl.value as? String == "2 / 7" {
                reachedSecondPage = true
                break
            }
        }
        XCTAssertTrue(reachedSecondPage, "继续上滑后应该自动切到第 2 页。")

        let scrollToTopButton = app.buttons["thread-detail-scroll-to-top"]
        XCTAssertTrue(scrollToTopButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToTopButton.isHittable, "回顶按钮出现后必须可点击。")
        scrollToTopButton.tap()

        let returnsToFirstPage = NSPredicate(format: "value == %@", "1 / 7")
        let firstReturn = XCTNSPredicateExpectation(
            predicate: returnsToFirstPage,
            object: currentPageControl
        )
        wait(for: [firstReturn], timeout: 5)

        var reachedSecondPageAgain = false
        for _ in 0..<8 {
            detailScrollView.swipeUp()
            if currentPageControl.waitForExistence(timeout: 1), currentPageControl.value as? String == "2 / 7" {
                reachedSecondPageAgain = true
                break
            }
        }
        XCTAssertTrue(reachedSecondPageAgain, "第二次下滑后应该再次切到第 2 页。")

        XCTAssertTrue(scrollToTopButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToTopButton.isHittable, "第二次回顶按钮出现后必须可点击。")
        scrollToTopButton.tap()

        let secondReturn = XCTNSPredicateExpectation(
            predicate: returnsToFirstPage,
            object: currentPageControl
        )
        wait(for: [secondReturn], timeout: 5)
    }

    @MainActor
    func testNGAReplyComposerSwitchesInlineEmojiGroupsAndReturnsToKeyboard() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(scenario: "UITEST_AUTHENTICATED_FEED")

        let threadRow = app.buttons["thread-row-90002"]
        XCTAssertTrue(threadRow.waitForExistence(timeout: 8))
        threadRow.tap()

        let replyAction = app.buttons["thread-detail-reply-action"]
        XCTAssertTrue(replyAction.waitForExistence(timeout: 8))
        replyAction.tap()

        XCTAssertTrue(app.buttons["reply-composer-close"].waitForExistence(timeout: 5))
        let targetTitle = app.staticTexts["reply-composer-target-title"]
        XCTAssertTrue(targetTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(targetTitle.isHittable, "回复目标标题不应被 Sheet 顶部遮挡")

        let quickEmoji = app.buttons["reply-composer-quick-emoji-ng_1.png"]
        XCTAssertTrue(quickEmoji.waitForExistence(timeout: 5))
        XCTAssertTrue(quickEmoji.isHittable, "键盘模式下快捷表情不应被 Sheet 底部遮挡")

        let editor = app.textViews["reply-composer-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()

        let emojiToggle = app.buttons["reply-composer-emoji-toggle"]
        XCTAssertTrue(emojiToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(emojiToggle.label, "打开表情")
        emojiToggle.tap()

        let emojiPanelAnchor = app.buttons["reply-composer-emoji-group-ng"]
        XCTAssertTrue(emojiPanelAnchor.waitForExistence(timeout: 5))
        XCTAssertEqual(emojiToggle.label, "返回键盘")

        for (group, filename) in [("pt", "pt00.png"), ("dt", "dt01.png"), ("pg", "pg01.png")] {
            let groupButton = app.buttons["reply-composer-emoji-group-\(group)"]
            XCTAssertTrue(groupButton.waitForExistence(timeout: 3))
            groupButton.tap()

            let emojiButton = app.buttons["reply-composer-emoji-\(filename)"]
            XCTAssertTrue(emojiButton.waitForExistence(timeout: 5))
            emojiButton.tap()
            XCTAssertTrue(emojiPanelAnchor.exists, "连续选择表情时面板必须保持打开")
        }

        emojiToggle.tap()
        let returnsToKeyboardMode = NSPredicate(format: "label == %@", "打开表情")
        let keyboardModeExpectation = XCTNSPredicateExpectation(
            predicate: returnsToKeyboardMode,
            object: emojiToggle
        )
        wait(for: [keyboardModeExpectation], timeout: 5)
        XCTAssertFalse(emojiPanelAnchor.exists)
        XCTAssertTrue(app.buttons["reply-composer-submit"].isEnabled)
    }

    @MainActor
    func testNGAReplyComposerClosesWhileKeyboardIsVisible() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(scenario: "UITEST_AUTHENTICATED_FEED")

        let threadRow = app.buttons["thread-row-90002"]
        XCTAssertTrue(threadRow.waitForExistence(timeout: 8))
        threadRow.tap()

        let replyAction = app.buttons["thread-detail-reply-action"]
        XCTAssertTrue(replyAction.waitForExistence(timeout: 8))
        replyAction.tap()

        let closeButton = app.buttons["reply-composer-close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(closeButton.isHittable, "键盘可见时关闭按钮应可点击")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "初次打开回复页应自动显示键盘")
        closeReplyComposer(closeButton, in: app, returningTo: replyAction)
    }

    @MainActor
    func testNGAReplyComposerClosesAfterTypingText() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(scenario: "UITEST_AUTHENTICATED_FEED")

        let threadRow = app.buttons["thread-row-90002"]
        XCTAssertTrue(threadRow.waitForExistence(timeout: 8))
        threadRow.tap()

        let replyAction = app.buttons["thread-detail-reply-action"]
        XCTAssertTrue(replyAction.waitForExistence(timeout: 8))
        replyAction.tap()

        let editor = app.textViews["reply-composer-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText("typed reply")

        let submitButton = app.buttons["reply-composer-submit"]
        XCTAssertTrue(submitButton.isEnabled, "键盘输入正文后发布按钮应立即启用")
        closeReplyComposer(
            app.buttons["reply-composer-close"],
            in: app,
            returningTo: replyAction
        )
    }

    @MainActor
    func testNGAReplyComposerSubmitsAfterTypingText() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(scenario: "UITEST_AUTHENTICATED_FEED")

        let threadRow = app.buttons["thread-row-90002"]
        XCTAssertTrue(threadRow.waitForExistence(timeout: 8))
        threadRow.tap()

        let replyAction = app.buttons["thread-detail-reply-action"]
        XCTAssertTrue(replyAction.waitForExistence(timeout: 8))
        replyAction.tap()

        let editor = app.textViews["reply-composer-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText("typed reply")

        let submitButton = app.buttons["reply-composer-submit"]
        XCTAssertTrue(submitButton.isEnabled)
        submitButton.tap()

        XCTAssertTrue(
            app.alerts["回复已发送"].waitForExistence(timeout: 8),
            "输入正文后点击发布应执行 Mock Repository 并显示成功反馈"
        )
        XCTAssertFalse(app.textViews["reply-composer-editor"].exists)
    }

    @MainActor
    func testNGAReplyComposerClosesFromEmojiAndReturnedKeyboardModes() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(scenario: "UITEST_AUTHENTICATED_FEED")

        let threadRow = app.buttons["thread-row-90002"]
        XCTAssertTrue(threadRow.waitForExistence(timeout: 8))
        threadRow.tap()

        let replyAction = app.buttons["thread-detail-reply-action"]
        XCTAssertTrue(replyAction.waitForExistence(timeout: 8))
        replyAction.tap()

        let emojiToggle = app.buttons["reply-composer-emoji-toggle"]
        XCTAssertTrue(emojiToggle.waitForExistence(timeout: 5))
        emojiToggle.tap()
        XCTAssertTrue(app.buttons["reply-composer-emoji-group-ng"].waitForExistence(timeout: 5))
        closeReplyComposer(app.buttons["reply-composer-close"], in: app, returningTo: replyAction)

        replyAction.tap()
        XCTAssertTrue(emojiToggle.waitForExistence(timeout: 5))
        emojiToggle.tap()
        XCTAssertTrue(app.buttons["reply-composer-emoji-group-ng"].waitForExistence(timeout: 5))
        emojiToggle.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "从表情模式返回后应恢复键盘")
        closeReplyComposer(app.buttons["reply-composer-close"], in: app, returningTo: replyAction)
    }

    @MainActor
    func testNGAReplyComposerSupportsThreeConsecutiveOpenCloseCycles() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(scenario: "UITEST_AUTHENTICATED_FEED")

        let threadRow = app.buttons["thread-row-90002"]
        XCTAssertTrue(threadRow.waitForExistence(timeout: 8))
        threadRow.tap()

        let replyAction = app.buttons["thread-detail-reply-action"]
        XCTAssertTrue(replyAction.waitForExistence(timeout: 8))

        for cycle in 1...3 {
            replyAction.tap()
            let closeButton = app.buttons["reply-composer-close"]
            XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "第 \(cycle) 次打开回复页应成功")
            closeReplyComposer(closeButton, in: app, returningTo: replyAction)
        }
    }

    @MainActor
    private func closeReplyComposer(
        _ closeButton: XCUIElement,
        in app: XCUIApplication,
        returningTo replyAction: XCUIElement
    ) {
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(closeButton.isHittable)
        closeButton.tap()

        let composerDismissed = NSPredicate(format: "exists == false")
        let dismissExpectation = XCTNSPredicateExpectation(
            predicate: composerDismissed,
            object: closeButton
        )
        wait(for: [dismissExpectation], timeout: 5)
        XCTAssertFalse(app.textViews["reply-composer-editor"].exists)
        XCTAssertTrue(replyAction.isHittable)
    }

    @MainActor
    func testNGAReplyComposerRemainsAccessibleAtLargestTextSize() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(
            scenario: "UITEST_AUTHENTICATED_FEED",
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        )

        let threadRow = app.buttons["thread-row-90002"]
        XCTAssertTrue(threadRow.waitForExistence(timeout: 8))
        threadRow.tap()

        let replyAction = app.buttons["thread-detail-reply-action"]
        XCTAssertTrue(replyAction.waitForExistence(timeout: 8))
        replyAction.tap()

        for identifier in [
            "reply-composer-close",
            "reply-composer-emoji-toggle",
            "reply-composer-submit"
        ] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(identifier) 应在最大辅助字体下存在")
            XCTAssertTrue(button.isHittable, "\(identifier) 应在最大辅助字体下可点击")
        }

        let editor = app.textViews["reply-composer-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(editor.isHittable, "正文编辑区应在最大辅助字体下可点击")

        app.buttons["reply-composer-emoji-toggle"].tap()
        let groupScroller = app.scrollViews["reply-composer-emoji-groups"]
        XCTAssertTrue(groupScroller.waitForExistence(timeout: 5))
        for group in ["ng", "ac", "a2", "pt", "dt", "pg"] {
            let button = app.buttons["reply-composer-emoji-group-\(group)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "表情分类 \(group) 应可访问")
            var swipeCount = 0
            while !button.isHittable, swipeCount < 6 {
                groupScroller.swipeLeft()
                swipeCount += 1
            }
            XCTAssertTrue(button.isHittable, "表情分类 \(group) 应可点击")
            button.tap()
        }

        var auditFailures: [String] = []
        try app.performAccessibilityAudit(for: [.hitRegion, .trait]) { issue in
            auditFailures.append(
                "\(issue.compactDescription): \(issue.detailedDescription) element=\(String(describing: issue.element))"
            )
            return true
        }
        XCTAssertTrue(auditFailures.isEmpty, auditFailures.joined(separator: "\n"))

        let closeButton = app.buttons["reply-composer-close"]
        XCTAssertTrue(closeButton.isHittable, "最大辅助字体下关闭按钮应保持可点击")
        closeReplyComposer(closeButton, in: app, returningTo: replyAction)
    }

    private func tapBottomTab(named title: String, in app: XCUIApplication) {
        let button = app.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "底栏应该展示\(title)按钮。")
        button.tap()
    }

    private func pullToRefresh(_ scrollView: XCUIElement) {
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func launch(scenario: String, contentSizeCategory: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(scenario)
        if let contentSizeCategory {
            app.launchArguments.append(contentsOf: ["-UIPreferredContentSizeCategoryName", contentSizeCategory])
        }
        app.launch()
        return app
    }
}
