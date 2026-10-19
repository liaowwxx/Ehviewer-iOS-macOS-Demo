import XCTest
import UIKit

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

    func testLocalGalleryDetailGroupsReadingAndTranslationActions() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Checks compact iPhone layout")
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestUseGuestMode", "YES", "-UITestLocalSearchFixtures", "YES",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"
        ]
        app.launch()
        let later = app.alerts.buttons["稍后"]
        if later.waitForExistence(timeout: 3) { later.tap() }
        XCTAssertTrue(app.buttons["打开《Green Garden》"].waitForExistence(timeout: 10))
        app.buttons["打开《Green Garden》"].tap()

        let read = app.buttons["start-reading-action"]
        XCTAssertTrue(read.waitForExistence(timeout: 10))
        XCTAssertTrue(read.isHittable)
        XCTAssertGreaterThanOrEqual(read.frame.height, 44)
        let favorite = app.buttons["favorite-action"]
        let share = app.buttons["share-action"]
        let similar = app.buttons["similar-gallery-action"]
        XCTAssertTrue(favorite.isHittable)
        XCTAssertTrue(share.isHittable)
        XCTAssertTrue(similar.isHittable)
        XCTAssertEqual(favorite.frame.midY, share.frame.midY, accuracy: 2)
        XCTAssertEqual(share.frame.midY, similar.frame.midY, accuracy: 2)
        XCTAssertGreaterThan(read.frame.width, favorite.frame.width)
        XCTAssertFalse(app.buttons["移除译件"].exists)
        XCTAssertFalse(app.buttons["导入译件目录"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "compact-gallery-detail"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertFalse(app.buttons["translation-management-menu"].exists)
        XCTAssertFalse(app.buttons["translation-import-action"].exists)

        let more = app.buttons["detail-more-actions"]
        XCTAssertTrue(more.isHittable)
        more.tap()
        XCTAssertTrue(app.buttons["detail-refresh-action"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["detail-open-site-action"].exists)
        XCTAssertFalse(app.buttons["导入译件目录"].exists)
    }

    func testLocalGalleryTapOpensDetailInEveryLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestUseGuestMode", "YES", "-UITestLocalSearchFixtures", "YES",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"
        ]
        app.launch()
        let later = app.alerts.buttons["稍后"]
        if later.waitForExistence(timeout: 3) { later.tap() }

        for layout in ["列表", "卡片", "瀑布流"] {
            let toggle = app.buttons["downloads-layout-toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            XCTAssertEqual(toggle.value as? String, layout)
            let gallery = app.buttons["打开《Green Garden》"]
            XCTAssertTrue(gallery.waitForExistence(timeout: 10))
            gallery.tap()
            XCTAssertTrue(app.navigationBars["详情"].waitForExistence(timeout: 5))
            let read = app.buttons["start-reading-action"]
            XCTAssertTrue(read.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["reader-settings-menu"].exists)
            read.tap()
            let readerMenu = app.buttons["reader-settings-menu"]
            XCTAssertTrue(readerMenu.waitForExistence(timeout: 10))
            XCTAssertTrue(readerMenu.isHittable, "\(layout): reader must be in front immediately after tapping Read")
            XCTAssertFalse(read.isHittable, "\(layout): detail must not cover the reader")
            app.navigationBars["Green Garden"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(read.waitForExistence(timeout: 5))
            XCTAssertTrue(read.isHittable, "\(layout): Back from reader must return to detail")
            app.navigationBars["详情"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            if layout != "瀑布流" { toggle.tap() }
        }
    }

    func testAdvancedSearchExplainsFiltersAndKeepsPageLabelsVisible() throws {
        let app = launchAdvancedSearch()

        let torrents = app.switches["advanced-search-torrents"]
        scrollToAdvancedSearchElement(torrents, in: app)
        XCTAssertTrue(torrents.label.contains("仅显示有种子文件的画廊"))
        XCTAssertTrue(torrents.label.contains("只显示提供 Torrent 种子文件的画廊。"))
        let expunged = app.switches["advanced-search-expunged"]
        XCTAssertTrue(expunged.exists)
        XCTAssertTrue(expunged.label.contains("仅搜索被移除的画廊"))
        XCTAssertTrue(expunged.label.contains("Expunged"))

        let minimum = app.textFields["advanced-search-minimum-pages"]
        scrollToAdvancedSearchElement(minimum, in: app)
        XCTAssertEqual(minimum.label, "最少页数")
        XCTAssertEqual(minimum.value as? String, "0")
        XCTAssertTrue(app.staticTexts["最少页数"].isHittable)
        let maximum = app.textFields["advanced-search-maximum-pages"]
        scrollToAdvancedSearchElement(maximum, in: app)
        XCTAssertEqual(maximum.label, "最多页数")
        XCTAssertEqual(maximum.value as? String, "0")
        XCTAssertTrue(app.staticTexts["最多页数"].isHittable)

        let help = app.staticTexts["advanced-search-default-filters-help"]
        scrollToAdvancedSearchElement(help, in: app)
        XCTAssertEqual(help.label, "开启后，本次搜索将忽略网站账户中对应的默认过滤设置。App 内的本地过滤规则仍然生效。")
        for title in ["忽略语言过滤", "忽略上传者过滤", "忽略标签过滤"] {
            XCTAssertTrue(app.switches[title].exists)
        }
    }

    func testAdvancedSearchPreservesPageRangeAndRejectsReversedBounds() throws {
        let app = launchAdvancedSearch()
        let minimum = app.textFields["advanced-search-minimum-pages"]
        let maximum = app.textFields["advanced-search-maximum-pages"]

        replaceAdvancedSearchValue(in: minimum, with: "20", app: app)
        XCTAssertTrue(app.staticTexts["最少页数"].isHittable)
        replaceAdvancedSearchValue(in: maximum, with: "80", app: app)
        XCTAssertTrue(app.staticTexts["最多页数"].isHittable)
        let apply = app.buttons["apply-advanced-search"]
        XCTAssertTrue(apply.isEnabled)
        apply.tap()

        let openSearch = app.buttons["advanced-search-action"]
        XCTAssertTrue(openSearch.waitForExistence(timeout: 5))
        openSearch.tap()
        XCTAssertTrue(app.scrollViews["advanced-search-scroll"].waitForExistence(timeout: 5))
        scrollToAdvancedSearchElement(minimum, in: app)
        XCTAssertEqual(minimum.value as? String, "20")
        XCTAssertTrue(app.staticTexts["最少页数"].isHittable)
        scrollToAdvancedSearchElement(maximum, in: app)
        XCTAssertEqual(maximum.value as? String, "80")
        XCTAssertTrue(app.staticTexts["最多页数"].isHittable)

        replaceAdvancedSearchValue(in: maximum, with: "10", app: app)
        let error = app.staticTexts["最多页数不能小于最少页数"]
        scrollToAdvancedSearchElement(error, in: app)
        XCTAssertFalse(apply.isEnabled)
        replaceAdvancedSearchValue(in: maximum, with: "0", app: app)
        XCTAssertTrue(apply.isEnabled)
        XCTAssertFalse(error.exists)
    }

    func testIPadLocalSearchKeepsSidebarToggleBeforeAndAfterSubmission() throws {
        let app = try launchIPadLocalSearch()
        let toggle = systemSidebarToggle(in: app)
        let sidebar = app.buttons["settings-sidebar"]

        for hideBeforeSearch in [true, false] {
            if sidebar.isHittable == false {
                toggle.tap()
            }
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            if hideBeforeSearch {
                toggle.tap()
                XCTAssertTrue(sidebar.waitForNonExistence(timeout: 5))
            }

            submitLocalSearch("blue archive", in: app)
            assertLocalSearchToolbar(in: app, query: "blue archive")
            XCTAssertTrue(app.buttons["打开《Blue Archive A》"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["打开《Green Garden》"].exists)

            if hideBeforeSearch == false {
                toggle.tap()
                XCTAssertTrue(sidebar.waitForNonExistence(timeout: 5))
            }
            XCTAssertTrue(toggle.isHittable)
            toggle.tap()
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            assertLocalSearchToolbar(in: app, query: "blue archive")
            XCTAssertTrue(app.buttons["打开《Blue Archive A》"].exists)
        }
    }

    func testIPadLocalSearchPreservesQueryAcrossLayoutSortAndFilters() throws {
        let app = try launchIPadLocalSearch()
        submitLocalSearch("blue archive", in: app)
        assertLocalSearchToolbar(in: app, query: "blue archive")

        let layout = app.buttons["downloads-layout-toggle"]
        let originalLayout = layout.value as? String
        layout.tap()
        XCTAssertNotEqual(layout.value as? String, originalLayout)
        assertLocalSearchToolbar(in: app, query: "blue archive")

        app.buttons["download-sort-menu"].tap()
        let descending = app.buttons["标题 Z-A"]
        XCTAssertTrue(descending.waitForExistence(timeout: 5))
        descending.tap()
        assertLocalSearchToolbar(in: app, query: "blue archive")
        let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打开《Blue Archive"))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.element(boundBy: 0).label, "打开《Blue Archive Z》")

        app.buttons["download-advanced-filter"].tap()
        let apply = app.buttons["apply-download-category-filter"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        assertLocalSearchToolbar(in: app, query: "blue archive")
        app.buttons["download-advanced-filter"].tap()
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        apply.tap()
        assertLocalSearchToolbar(in: app, query: "blue archive")

        submitLocalSearch("no-local-gallery-matches", in: app)
        XCTAssertTrue(app.staticTexts["没有匹配的下载"].waitForExistence(timeout: 5))
        assertLocalSearchToolbar(in: app, query: "no-local-gallery-matches")
        replaceLocalSearchInput(with: "", in: app)
        XCTAssertTrue(app.buttons["打开《Green Garden》"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打开《")).count, 3)
        XCTAssertFalse(app.staticTexts["没有匹配的下载"].exists)
    }

    func testIPadLocalSearchTagCompletionOnlyFiltersAfterSubmission() throws {
        let app = try launchIPadLocalSearch()

        let search = app.searchFields.firstMatch
        replaceLocalSearchInput(with: "精灵", in: app)
        let suggestion = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label BEGINSWITH %@", "female:elf", "female:elf，"
        )).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        suggestion.tap()
        let completedQuery = try XCTUnwrap(search.value as? String)
        XCTAssertTrue(completedQuery.contains("elf"))
        XCTAssertNotEqual(completedQuery, "female:elf")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["打开《Green Garden》"].exists)
        XCTAssertTrue(app.buttons["打开《Blue Archive A》"].exists)

        search.typeText("\n")
        assertLocalSearchToolbar(in: app, query: completedQuery)
        XCTAssertTrue(app.buttons["打开《Blue Archive A》"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["打开《Green Garden》"].exists)
    }

    private func launchIPadLocalSearch() throws -> XCUIApplication {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires iPad split navigation")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestUseGuestMode", "YES", "-UITestLocalSearchFixtures", "YES",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"
        ]
        app.launch()
        XCTAssertTrue(app.otherElements["ehviewer-root"].waitForExistence(timeout: 10))
        let later = app.alerts.buttons["稍后"]
        if later.waitForExistence(timeout: 2) {
            later.tap()
        }
        XCTAssertTrue(systemSidebarToggle(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["打开《Green Garden》"].waitForExistence(timeout: 10))
        return app
    }

    private func replaceLocalSearchInput(with query: String, in app: XCUIApplication) {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        let current = search.value as? String ?? ""
        if current.isEmpty == false, current != search.placeholderValue {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        if query.isEmpty == false {
            search.typeText(query)
        }
    }

    private func submitLocalSearch(_ query: String, in app: XCUIApplication) {
        replaceLocalSearchInput(with: query, in: app)
        app.searchFields.firstMatch.typeText("\n")
    }

    private func assertLocalSearchToolbar(in app: XCUIApplication, query: String) {
        XCTAssertTrue(app.navigationBars["本地"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["搜索结果"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        if query.isEmpty {
            XCTAssertTrue((search.value as? String ?? "").isEmpty || search.value as? String == search.placeholderValue)
        } else {
            XCTAssertEqual(search.value as? String, query)
        }
        let sidebarToggle = systemSidebarToggle(in: app)
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(sidebarToggle.isHittable)
        for identifier in ["downloads-layout-toggle", "download-sort-menu", "download-advanced-filter"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
            XCTAssertTrue(button.isHittable, identifier)
            XCTAssertTrue(button.isEnabled, identifier)
        }
    }

    private func systemSidebarToggle(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS[c] %@", "边栏", "sidebar"
        )).firstMatch
    }

    private func launchAdvancedSearch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestUseGuestMode", "YES",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons.element(boundBy: 0).tap()
        let action = app.buttons["advanced-search-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
        XCTAssertTrue(app.scrollViews["advanced-search-scroll"].waitForExistence(timeout: 5))
        return app
    }

    private func scrollToAdvancedSearchElement(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews["advanced-search-scroll"]
        for _ in 0..<6 {
            if element.isHittable { break }
            scrollView.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func replaceAdvancedSearchValue(in field: XCUIElement, with value: String, app: XCUIApplication) {
        scrollToAdvancedSearchElement(field, in: app)
        field.tap()
        let currentValue = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count) + value + "\n")
        XCTAssertEqual(field.value as? String, value)
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
