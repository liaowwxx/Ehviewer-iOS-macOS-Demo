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

    func testSettingsExposesGuestAndDemoStateControls() throws {
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
        let demoToggle = app.switches["使用演示数据"].exists
            ? app.switches["使用演示数据"]
            : app.switches["Use demo data"]
        XCTAssertTrue(demoToggle.exists)
        let sessionStatus = app.descendants(matching: .any)["session-status"]
        XCTAssertTrue(sessionStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(sessionStatus.value as? String, "游客浏览")
    }

    func testDetailActionsAndTagSearchStayUsable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseDemoData", "YES"]
        app.launch()

        let galleryTitle = app.staticTexts["Sample Gallery · Browse baseline"]
        XCTAssertTrue(galleryTitle.waitForExistence(timeout: 5))
        galleryTitle.tap()

        XCTAssertTrue(app.buttons["start-reading-action"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["enqueue-download-action"].isHittable)

        let favorite = app.buttons["favorite-action"]
        XCTAssertTrue(favorite.isHittable)
        favorite.tap()
        XCTAssertTrue(favorite.waitForExistence(timeout: 2))

        let tag = app.buttons["tag-search-language:chinese"]
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        XCTAssertTrue(tag.isHittable)
        tag.tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertEqual(searchField.value as? String, "language:chinese")
    }
}
