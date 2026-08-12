import XCTest

@MainActor
final class EhViewerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRootViewLaunchesWithAccessibleNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseGuestMode", "YES"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.otherElements["ehviewer-root"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["settings-tab"].exists ||
            app.buttons["settings-sidebar"].exists ||
            app.tabBars.firstMatch.exists
        )
    }

    func testSettingsExposesGuestState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseGuestMode", "YES"]
        app.launch()

        let settings = app.buttons["settings-tab"]
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
        } else if app.buttons["settings-sidebar"].waitForExistence(timeout: 5) {
            app.buttons["settings-sidebar"].tap()
        } else if app.tabBars.firstMatch.exists {
            app.tabBars.buttons.element(boundBy: min(3, app.tabBars.buttons.count - 1)).tap()
        }

        XCTAssertTrue(app.staticTexts["站点"].waitForExistence(timeout: 5) || app.staticTexts["Site"].exists)
        let sessionStatus = app.descendants(matching: .any)["session-status"]
        XCTAssertTrue(sessionStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(sessionStatus.value as? String, "游客浏览")
    }

    func testAdvancedSearchCanBeConfiguredAndApplied() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseGuestMode", "YES"]
        app.launch()

        let advancedSearch = app.buttons["advanced-search-action"]
        XCTAssertTrue(advancedSearch.waitForExistence(timeout: 5))
        advancedSearch.tap()

        let form = app.descendants(matching: .any)["advanced-search-form"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let category = app.buttons["advanced-search-category-doujinshi"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()

        let apply = app.buttons["apply-advanced-search"]
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        XCTAssertFalse(form.exists)
    }
}
