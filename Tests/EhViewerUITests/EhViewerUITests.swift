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
        XCTAssertTrue(app.buttons["settings-tab"].exists || app.tabBars.firstMatch.exists)
    }

    func testSettingsExposesGuestAndDemoStateControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseGuestMode", "YES"]
        app.launch()

        let settings = app.buttons["settings-tab"]
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
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
}
