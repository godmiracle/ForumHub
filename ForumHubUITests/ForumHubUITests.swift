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
        let app = XCUIApplication()
        app.launch()

        app.buttons["tab-community"].tap()
        let ngaButton = app.buttons["community-source-nga"]
        XCTAssertTrue(ngaButton.waitForExistence(timeout: 8))
        ngaButton.tap()
        app.buttons["tab-home"].tap()

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
        let app = XCUIApplication()
        app.launch()

        app.buttons["tab-community"].tap()
        XCTAssertTrue(app.scrollViews["community-screen"].waitForExistence(timeout: 8))
        let v2exButton = app.buttons["community-source-v2ex"]
        XCTAssertTrue(v2exButton.waitForExistence(timeout: 8))
        v2exButton.tap()

        app.buttons["tab-home"].tap()

        XCTAssertTrue(
            app.textFields["forum-search-field"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.textFields["forum-search-field"].isEnabled)
        XCTAssertTrue(app.staticTexts["active-forum-title"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testThreadDetailScrollAutoAdvancesToNextPage() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_PAGED_THREAD")
        app.launch()

        let threadRow = app.otherElements["thread-row-991001"]
        if !threadRow.waitForExistence(timeout: 2) {
            for _ in 0..<4 where !threadRow.exists {
                app.swipeUp()
            }
        }
        XCTAssertTrue(threadRow.waitForExistence(timeout: 5))
        threadRow.tap()

        let detailScrollView = app.scrollViews["thread-detail-scroll"]
        XCTAssertTrue(detailScrollView.waitForExistence(timeout: 8))

        let currentPageLabel = app.staticTexts["thread-detail-current-page"]
        XCTAssertTrue(currentPageLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(currentPageLabel.label, "1 / 7")

        var reachedSecondPage = false
        for _ in 0..<8 {
            detailScrollView.swipeUp()
            if currentPageLabel.waitForExistence(timeout: 1), currentPageLabel.label == "2 / 7" {
                reachedSecondPage = true
                break
            }
        }

        XCTAssertTrue(reachedSecondPage, "继续上滑后应该自动切到第 2 页。")
    }
}
