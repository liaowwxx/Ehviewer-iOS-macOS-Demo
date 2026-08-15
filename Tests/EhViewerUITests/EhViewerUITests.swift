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

        let settingsScreen = app.descendants(matching: .any)["settings-screen"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        let sessionStatus = app.descendants(matching: .any)["session-status"]
        XCTAssertTrue(sessionStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(sessionStatus.value as? String, "游客模式")
    }

    func testSearchOpensIndependentResultsPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseGuestMode", "YES"]
        app.launch()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("blue archive")
        searchField.typeText("\n")

        XCTAssertTrue(app.navigationBars["搜索结果"].waitForExistence(timeout: 5))
    }

    func testSettingsTogglesJapaneseTitlePreference() throws {
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

        let toggle = app.switches["show-japanese-title-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let wasOn = (toggle.value as? String) == "1"
        toggle.tap()
        let isOn = (toggle.value as? String) == "1"
        XCTAssertNotEqual(wasOn, isOn)
    }

    func testGalleryDeepLinkPushesDetailOnIPhone() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseGuestMode", "YES"]
        app.launch()

        XCTAssertTrue(app.otherElements["ehviewer-root"].waitForExistence(timeout: 5))
        app.open(URL(string: "ehviewer://?url=https://e-hentai.org/g/12345/token/")!)

        XCTAssertTrue(app.navigationBars["详情"].waitForExistence(timeout: 5))
    }
}
