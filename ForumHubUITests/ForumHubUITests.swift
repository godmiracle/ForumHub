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

    private func tapBottomTab(named title: String, in app: XCUIApplication) {
        let button = app.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "底栏应该展示\(title)按钮。")
        button.tap()
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
