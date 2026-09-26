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

    func testCompactDockSeparatesLibraryTabsAndKeepsDownloadsUnderLocal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseGuestMode", "YES"]
        app.launch()

        XCTAssertTrue(app.otherElements["ehviewer-root"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["history-tab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["favorites-tab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-tab"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        XCTAssertTrue(app.buttons["local-downloads-link"].waitForExistence(timeout: 5))
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
            app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1).tap()
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
            app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1).tap()
        }

        let browsing = app.buttons["settings-browsing-link"]
        XCTAssertTrue(browsing.waitForExistence(timeout: 5))
        browsing.tap()

        let customization = app.buttons["settings-browsing-customization-link"]
        XCTAssertTrue(customization.waitForExistence(timeout: 5))
        customization.tap()
        XCTAssertTrue(app.descendants(matching: .any)["gallery-card-settings-preview"].waitForExistence(timeout: 5))

        let toggle = app.switches["show-japanese-title-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let wasOn = (toggle.value as? String) == "1"
        toggle.tap()
        let isOn = (toggle.value as? String) == "1"
        XCTAssertNotEqual(wasOn, isOn)
    }

    func testSettingsOpensLocalUsageDocumentation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseGuestMode", "YES"]
        app.launch()

        let settings = app.descendants(matching: .any)["settings-tab"]
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
        } else if app.descendants(matching: .any)["settings-sidebar"].waitForExistence(timeout: 5) {
            app.descendants(matching: .any)["settings-sidebar"].tap()
        } else {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
            let tabButtons = app.tabBars.buttons
            XCTAssertGreaterThan(tabButtons.count, 0)
            tabButtons.element(boundBy: tabButtons.count - 1).tap()
        }

        XCTAssertTrue(app.descendants(matching: .any)["settings-screen"].waitForExistence(timeout: 5))
        let documentationLink = app.descendants(matching: .any)["usage-documentation-link"]
        XCTAssertTrue(documentationLink.waitForExistence(timeout: 5))
        documentationLink.tap()

        XCTAssertTrue(app.descendants(matching: .any)["documentation-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["使用说明"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["documentation-menu"].waitForExistence(timeout: 5))
    }

    func testSettingsOverviewKeepsAllNavigationRowsInSettingsSection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseGuestMode", "YES"]
        app.launch()

        openSettings(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["settings-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["配置文件"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["关于"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["profile-create-action"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-browsing-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-reading-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-storage-and-progress-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-data-and-backup-link"].exists)
    }

    func testDataBackupAndSyncExposesSettingsRows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseGuestMode", "YES"]
        app.launch()

        openSettings(in: app)
        let dataSettings = app.descendants(matching: .any)["settings-data-and-backup-link"]
        XCTAssertTrue(dataSettings.waitForExistence(timeout: 5))
        dataSettings.tap()

        XCTAssertTrue(app.navigationBars["数据备份&同步"].waitForExistence(timeout: 5))
        for identifier in [
            "refresh-downloaded-gallery-metadata-action",
            "import-gallery-metadata-action",
            "import-download-archive-action",
            "export-gallery-metadata-action",
            "export-download-archive-action",
            "device-sync-link",
            "rebuild-device-sync-index-action"
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].waitForExistence(timeout: 5),
                "Missing settings action: \(identifier)"
            )
        }

        app.descendants(matching: .any)["refresh-downloaded-gallery-metadata-action"].tap()
        XCTAssertTrue(app.buttons["仅更新缺失信息"].waitForExistence(timeout: 5))
    }

    func testCreatingProfileShowsNameEditorControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseGuestMode", "YES"]
        app.launch()

        openSettings(in: app)
        let createProfile = app.descendants(matching: .any)["profile-create-action"]
        XCTAssertTrue(createProfile.waitForExistence(timeout: 5))
        createProfile.tap()

        XCTAssertTrue(app.textFields["profile-name-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["profile-name-save-action"].waitForExistence(timeout: 5))
    }

    func testGalleryDeepLinkPushesDetailOnIPhone() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseGuestMode", "YES"]
        app.launch()

        XCTAssertTrue(app.otherElements["ehviewer-root"].waitForExistence(timeout: 5))
        app.open(URL(string: "ehviewer://?url=https://e-hentai.org/g/12345/token/")!)

        XCTAssertTrue(app.navigationBars["详情"].waitForExistence(timeout: 5))
    }

    private func openSettings(in app: XCUIApplication) {
        if app.buttons["settings-tab"].waitForExistence(timeout: 5) {
            app.buttons["settings-tab"].tap()
        } else if app.buttons["settings-sidebar"].waitForExistence(timeout: 5) {
            app.buttons["settings-sidebar"].tap()
        } else if app.tabBars.firstMatch.exists {
            app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1).tap()
        }
    }
}
