import Foundation
import Testing
import EHDomain
import EHNetworking
import EHPersistence
import EHDownloads
@testable import EhViewerPreview

@MainActor
struct AppModelTests {
    @Test("Preview reveal state adds 20 items and collapses to the initial window")
    func previewRevealState() {
        var state = GalleryPreviewRevealState()
        #expect(state.visibleCount == 27)

        state.revealNext(totalCount: 100)
        #expect(state.visibleCount == 47)
        state.revealNext(totalCount: 60)
        #expect(state.visibleCount == 60)
        state.revealNext(totalCount: 60)
        #expect(state.visibleCount == 60)

        state.collapse()
        #expect(state.visibleCount == 27)
    }

    @Test("App starts in guest mode without a saved session")
    func defaultsToGuestMode() async throws {
        let suiteName = "EhViewerGuestModeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sessionVault = SessionVault(service: suiteName)
        try await sessionVault.clear()

        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: sessionVault,
            defaults: defaults
        )

        #expect(model.isGuestMode)
        await model.refreshSessionStatus()
        #expect(model.isGuestMode)
    }

    @Test("Unrelated cookies cannot leave guest mode")
    func unrelatedCookieDoesNotAuthenticate() async throws {
        let suiteName = "EhViewerCookieLoginTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sessionVault = SessionVault(service: suiteName)
        try await sessionVault.clear()
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: sessionVault,
            defaults: defaults
        )

        #expect(await model.saveCookie("foo=bar") == false)
        #expect(model.isGuestMode)
        #expect(try await sessionVault.hasAuthenticatedSession() == false)
    }

    @Test("A complete session cookie leaves guest mode")
    func completeCookieAuthenticates() async throws {
        let suiteName = "EhViewerValidCookieLoginTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sessionVault = SessionVault(service: suiteName)
        try await sessionVault.clear()
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: sessionVault,
            defaults: defaults
        )

        #expect(await model.saveCookie("ipb_member_id=42; ipb_pass_hash=secret; unrelated=value"))
        #expect(model.isGuestMode == false)
        #expect(model.site == .eHentai)
        #expect(model.selectedRoute == .browse)
        #expect(try await sessionVault.loadAuthenticatedCookieHeader() == "ipb_member_id=42; ipb_pass_hash=secret")
        await model.clearSession()
        #expect(model.site == .eHentai)
    }

    @Test("An authenticated session restores the selected site")
    func authenticatedSessionRestoresSelectedSite() async throws {
        let suiteName = "EhViewerDefaultSiteTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(SiteMode.exHentai.rawValue, forKey: "site")
        let vault = SessionVault(service: suiteName)
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret")

        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: vault,
            defaults: defaults
        )
        await model.refreshSessionStatus()

        #expect(model.isGuestMode == false)
        #expect(model.site == .exHentai)
        #expect(defaults.string(forKey: "site") == SiteMode.exHentai.rawValue)
        try await vault.clear()
    }

    @Test("Typing a query does not commit it before search submission")
    func searchSubmissionIsExplicit() throws {
        let suiteName = "EhViewerExplicitSearchTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )

        model.searchText = "  artist:test\n"
        #expect(model.submittedSearchText.isEmpty)
        model.submitSearch()
        #expect(model.searchText == "artist:test")
        #expect(model.submittedSearchText == "artist:test")
    }

    @Test("Selecting a tag reloads the browse query and replaces the old list")
    func tagSearchReloadsBrowseQuery() async throws {
        let api = ControlledListAPI()
        let suiteName = "EhViewerTagSearchTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: api,
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )

        let oldSummary = GallerySummary(key: GalleryKey(gid: 1, token: "old"), title: "Old result")
        let oldLoad = Task { await model.load(query: GalleryListQuery(searchText: "old")) }
        await api.waitUntilRequested("old")
        #expect(await api.respond(to: "old", with: GalleryListPage(items: [oldSummary])))
        await oldLoad.value

        model.searchTag("artist:test")
        let tagQueryText = model.pendingSearchQuery
        let tagQuery = GalleryListQuery(
            site: model.site,
            kind: .home,
            searchText: tagQueryText
        )
        let newSummary = GallerySummary(key: GalleryKey(gid: 2, token: "tag"), title: "Tag result")
        let tagLoad = Task { await model.load(query: tagQuery) }
        await api.waitUntilRequested(tagQueryText ?? "")
        #expect(await api.respond(to: tagQueryText ?? "", with: GalleryListPage(items: [newSummary])))
        await tagLoad.value

        #expect(model.galleries == [newSummary])
        #expect(model.pendingSearchQuery == SearchQueryComposer.searchSyntax(for: "artist:test"))
    }

    @Test("Browse page models keep secondary lists independent from the home list")
    func browsePageModelsAreIndependent() async throws {
        let suiteName = "EhViewerIndependentBrowseTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: KindListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )
        let home = BrowsePageModel(model: model, kind: .home)
        let popular = BrowsePageModel(model: model, kind: .popular)

        await home.load(query: home.listQuery)
        await popular.load(query: popular.listQuery)

        #expect(home.galleries.map(\.title) == ["Home result"])
        #expect(popular.galleries.map(\.title) == ["Popular result"])
    }

    @Test("Browse search restores cached tag suggestions")
    func browseSearchShowsTagSuggestions() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-browse-tags-\(UUID().uuidString)")
        let cacheURL = root.appendingPathComponent("tag-translations-zh-rCN")
        defer { try? FileManager.default.removeItem(at: root) }

        let translation = Data("蓝色档案".utf8).base64EncodedString()
        let payload = Data("g:blue archive\r\(translation)\nf:sample\rbnVsbA==\n".utf8)
        var data = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        data.append(payload)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)

        let provider = TagSuggestionProvider(
            sourceURLs: [URL(string: "https://example.invalid/tags")!],
            cacheURL: cacheURL
        )
        let suiteName = "EhViewerBrowseTagSuggestionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults,
            tagSuggestionProvider: provider
        )
        let pageModel = BrowsePageModel(model: model, kind: .home)
        pageModel.searchText = "blue archive"

        await pageModel.refreshSearchSuggestions(for: pageModel.searchText)

        #expect(pageModel.tagSearchSuggestions == [
            SearchTagSuggestion(english: "group:blue archive", localizedText: "蓝色档案", rawKey: "g:blue archive")
        ])
    }

    @Test("The reference tag database import translates detail tags to Chinese")
    func tagDatabaseImportTranslatesDetailTags() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-tag-import-\(UUID().uuidString)")
        let cacheURL = root.appendingPathComponent("tag-translations-zh-rCN")
        defer { try? FileManager.default.removeItem(at: root) }

        func databaseLine(_ key: String, _ text: String) -> String {
            "\(key)\r\(Data(text.utf8).base64EncodedString())\n"
        }
        let payload = Data(
            (
                databaseLine("a:blue archive", "蓝色档案")
                    + databaseLine("n:artist", "画师")
                    + databaseLine("n:male", "男性")
                    + databaseLine("n:other", "其他")
                    + databaseLine("m:furry", "毛茸茸")
                    + databaseLine("o:full color", "全彩")
                    + databaseLine("o:artbook", "画集")
            ).utf8
        )
        var data = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        data.append(payload)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)

        let provider = TagSuggestionProvider(
            sourceURLs: [URL(string: "https://example.invalid/tags")!],
            cacheURL: cacheURL
        )
        let suiteName = "EhViewerTagImportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: OfflineReaderAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults,
            tagSuggestionProvider: provider
        )

        await model.importTagTranslationsIfNeeded()

        #expect(model.displayTag("artist:blue archive") == "蓝色档案")
        #expect(model.displayTag("male:furry") == "毛茸茸")
        #expect(model.displayTag("other:full color") == "全彩")
        #expect(model.displayTag("other:artbook") == "画集")
        #expect(model.displayTag("misc:unknown") == "unknown")
        #expect(model.localizedTag("n:artist") == "画师")
        #expect(model.localizedTag("n:male") == "男性")

        model.readingSettings.showTagTranslations = false
        #expect(model.displayTag("male:furry") == "furry")
        #expect(model.displayTag("other:full color") == "full color")
    }

    @Test("Download sort and status filters persist across launches")
    func downloadPreferencesPersist() async throws {
        let suiteName = "EhViewerDownloadPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: OfflineReaderAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )
        #expect(first.downloadSortOrder == .titleAscending)
        #expect(first.downloadStatusFilter == .all)
        #expect(first.downloadLayoutMode == .list)
        first.downloadSortOrder = .progress
        first.downloadStatusFilter = .completed
        first.downloadLayoutMode = .grid
        first.persistDownloadPreferences()

        let second = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: OfflineReaderAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )
        #expect(second.downloadSortOrder == .progress)
        #expect(second.downloadStatusFilter == .completed)
        #expect(second.downloadLayoutMode == .grid)
    }

    @Test("Rapid tag suggestion refresh follows the input and keeps the latest query")
    func rapidTagSuggestionRefreshFollowsInputAndKeepsLatestQuery() async throws {
        let tagLoader = ControlledTagSuggestionLoader()
        let suiteName = "EhViewerRapidTagSuggestionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )
        let pageModel = BrowsePageModel(
            model: model,
            kind: .home,
            tagSuggestionLoader: { keyword in
                try await tagLoader.suggestions(for: keyword)
            }
        )

        pageModel.searchText = "blue archive"
        let seedTask = Task { @MainActor in
            await pageModel.refreshSearchSuggestions(for: "blue archive")
        }
        await tagLoader.waitUntilRequested("blue archive")
        #expect(await tagLoader.respond(
            to: "blue archive",
            with: [SearchTagSuggestion(english: "group:blue archive", localizedText: "蓝色档案")]
        ))
        await seedTask.value
        #expect(pageModel.tagSearchSuggestions == [
            SearchTagSuggestion(english: "group:blue archive", localizedText: "蓝色档案")
        ])

        pageModel.searchText = "group"
        let staleTask = Task { @MainActor in
            await pageModel.refreshSearchSuggestions(for: "group")
        }
        await tagLoader.waitUntilRequested("group")
        #expect(pageModel.suggestionQuery == "group")
        #expect(pageModel.isUpdatingSearchSuggestions)
        #expect(pageModel.tagSearchSuggestions == [
            SearchTagSuggestion(english: "group:blue archive", localizedText: "蓝色档案")
        ])

        pageModel.searchText = "female"
        let latestTask = Task { @MainActor in
            await pageModel.refreshSearchSuggestions(for: "female")
        }
        await tagLoader.waitUntilRequested("female")
        #expect(pageModel.suggestionQuery == "female")
        #expect(pageModel.isUpdatingSearchSuggestions)
        #expect(pageModel.tagSearchSuggestions.isEmpty)

        #expect(await tagLoader.respond(
            to: "female",
            with: [SearchTagSuggestion(english: "female:sample")]
        ))
        await latestTask.value

        #expect(pageModel.tagSearchSuggestions == [
            SearchTagSuggestion(english: "female:sample")
        ])
        #expect(pageModel.isUpdatingSearchSuggestions == false)

        #expect(await tagLoader.respond(
            to: "group",
            with: [SearchTagSuggestion(english: "group:blue archive", localizedText: "蓝色档案")]
        ))
        await staleTask.value

        #expect(pageModel.suggestionQuery == "female")
        #expect(pageModel.tagSearchSuggestions == [
            SearchTagSuggestion(english: "female:sample")
        ])
    }

    @Test("Selecting a tag only updates the pending search text")
    func selectingTagDoesNotSubmitSearch() async throws {
        let suiteName = "EhViewerPendingTagSearchTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )
        let pageModel = BrowsePageModel(model: model, kind: .search)
        pageModel.searchText = "l:\"chinese$\" furry"
        pageModel.submittedSearchText = "l:\"chinese$\" furry"

        pageModel.completeTagSuggestion("female:furry")

        #expect(pageModel.searchText == "l:\"chinese$\" f:\"furry$\"")
        #expect(pageModel.submittedSearchText == "l:\"chinese$\" furry")
    }

    @Test("An incoming gallery link selects the gallery route")
    func incomingGalleryLinkSelectsGalleryRoute() throws {
        let suiteName = "EhViewerDeepLinkTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )

        let url = try #require(URL(string: "ehviewer://?url=https://e-hentai.org/g/12345/token/"))
        model.handleIncomingURL(url)

        #expect(model.selectedRoute == .gallery(GalleryKey(gid: 12345, token: "token")))
    }

    @Test("A slower old search cannot overwrite the latest result")
    func latestListRequestWins() async throws {
        let api = ControlledListAPI()
        let suiteName = "EhViewerAppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: api,
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )

        let firstTask = Task {
            await model.load(query: GalleryListQuery(searchText: "first"))
        }
        await api.waitUntilRequested("first")

        let secondTask = Task {
            await model.load(query: GalleryListQuery(searchText: "second"))
        }
        await api.waitUntilRequested("second")

        let secondSummary = GallerySummary(
            key: GalleryKey(gid: 2, token: "second"),
            title: "Second result"
        )
        #expect(await api.respond(to: "second", with: GalleryListPage(items: [secondSummary])))
        await secondTask.value

        let firstSummary = GallerySummary(
            key: GalleryKey(gid: 1, token: "first"),
            title: "Stale first result"
        )
        #expect(await api.respond(to: "first", with: GalleryListPage(items: [firstSummary])))
        await firstTask.value

        #expect(model.galleries == [secondSummary])
        #expect(model.isLoading == false)
    }

    @Test("Reaching the last search result loads and appends the exact next cursor")
    func lastSearchResultLoadsNextPage() async throws {
        let first = GallerySummary(key: GalleryKey(gid: 2, token: "first"), title: "First")
        let last = GallerySummary(key: GalleryKey(gid: 1, token: "last"), title: "Last")
        let next = GallerySummary(key: GalleryKey(gid: 3, token: "next"), title: "Next")
        let cursorURL = try #require(URL(string: "https://e-hentai.org/?f_search=test&next=1"))
        let api = SearchPaginationAPI(
            firstPage: GalleryListPage(
                items: [first, last],
                cursor: GalleryCursor(page: 0, nextPageURL: cursorURL)
            ),
            secondPage: GalleryListPage(items: [next])
        )
        let suiteName = "EhViewerSearchPaginationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: api,
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )

        await model.load(query: GalleryListQuery(kind: .search, searchText: "test"))
        await model.loadMoreIfNeeded(after: first.key)
        #expect(await api.requestedPageURLs().isEmpty)

        await model.loadMoreIfNeeded(after: last.key)
        #expect(model.galleries == [first, last, next])
        #expect(await api.requestedPageURLs() == [cursorURL])
        #expect(model.hasMorePage == false)
    }

    @Test("Returning from gallery detail keeps the loaded list and pagination position")
    func returningFromDetailDoesNotReloadBrowseList() async throws {
        let first = GallerySummary(key: GalleryKey(gid: 2, token: "first"), title: "First")
        let second = GallerySummary(key: GalleryKey(gid: 1, token: "second"), title: "Second")
        let next = GallerySummary(key: GalleryKey(gid: 3, token: "next"), title: "Next")
        let cursorURL = try #require(URL(string: "https://e-hentai.org/?next=1"))
        let api = SearchPaginationAPI(
            firstPage: GalleryListPage(
                items: [first, second],
                cursor: GalleryCursor(page: 0, nextPageURL: cursorURL)
            ),
            secondPage: GalleryListPage(items: [next])
        )
        let suiteName = "EhViewerBrowseReturnTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: api,
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )
        let query = GalleryListQuery()

        await model.loadBrowseQuery(query)
        await model.loadMoreIfNeeded(after: second.key)
        await model.loadBrowseQuery(query)

        #expect(await api.firstPageRequestCount() == 1)
        #expect(model.galleries == [first, second, next])
    }

    @Test("Downloaded reader loads a completed page without a network request")
    func downloadedReaderPrefersLocalPage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-reader-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = DownloadFileStore(root: root, minimumFreeBytes: 1)
        let key = GalleryKey(gid: 9, token: "offline")
        let descriptor = GalleryPageDescriptor(
            galleryKey: key,
            index: 0,
            pageURL: URL(string: "https://example.invalid/remote.png")!
        )
        let localData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        _ = try await files.write(localData, for: key, pageIndex: 0)

        let suiteName = "EhViewerDownloadedReaderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: OfflineReaderAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults,
            downloadFiles: files
        )

        let loaded = try await model.downloadedPageData(for: descriptor)

        #expect(loaded == localData)
    }

    @Test("Search result models are reused and do not reload after returning from detail")
    func searchResultModelIsCached() async throws {
        let result = GallerySummary(key: GalleryKey(gid: 20, token: "cached"), title: "Cached")
        let api = SearchPaginationAPI(firstPage: GalleryListPage(items: [result]), secondPage: GalleryListPage(items: []))
        let suiteName = "EhViewerSearchCacheTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: api,
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )

        let first = model.searchPageModel(for: "  artist:test  ")
        await first.loadIfNeeded(query: first.listQuery)
        first.scrollPosition = result.key
        let restored = model.searchPageModel(for: "artist:test")
        await restored.loadIfNeeded(query: restored.listQuery)

        #expect(first === restored)
        #expect(restored.galleries == [result])
        #expect(restored.scrollPosition == result.key)
        #expect(await api.firstPageRequestCount() == 1)
    }

    @Test("A fully blocked page continues from the exact next cursor")
    func blockedFirstPageCanContinueLoading() async throws {
        let blocked = GallerySummary(key: GalleryKey(gid: 21, token: "blocked"), title: "spoiler gallery")
        let visible = GallerySummary(key: GalleryKey(gid: 22, token: "visible"), title: "visible gallery")
        let cursor = try #require(URL(string: "https://e-hentai.org/?next=blocked-page"))
        let api = SearchPaginationAPI(
            firstPage: GalleryListPage(items: [blocked], cursor: GalleryCursor(page: 0, nextPageURL: cursor)),
            secondPage: GalleryListPage(items: [visible])
        )
        let suiteName = "EhViewerBlockedPageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: api,
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )
        await model.setFilterRule(pattern: "spoiler", isEnabled: true)
        let pageModel = BrowsePageModel(model: model, kind: .home)

        await pageModel.load(query: pageModel.listQuery)
        #expect(pageModel.galleries.isEmpty)
        await pageModel.loadMore()

        #expect(pageModel.galleries == [visible])
        #expect(await api.requestedPageURLs() == [cursor])
    }

    @Test("Tag and tag-namespace filter rules remove matching list items")
    func tagFilterRulesBlockListItems() async throws {
        let furry = GallerySummary(
            key: GalleryKey(gid: 31, token: "furry"),
            title: "Furry comic",
            tags: ["female:furry", "male:furry", "misc:full color"]
        )
        let aiGenerated = GallerySummary(
            key: GalleryKey(gid: 32, token: "ai"),
            title: "AI sample",
            tags: ["misc:ai generated"]
        )
        let clean = GallerySummary(
            key: GalleryKey(gid: 33, token: "clean"),
            title: "Clean gallery",
            tags: ["language:english"]
        )
        let api = SearchPaginationAPI(
            firstPage: GalleryListPage(items: [furry, aiGenerated, clean]),
            secondPage: GalleryListPage(items: [])
        )
        let suiteName = "EhViewerTagFilterTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: api,
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )
        let pageModel = BrowsePageModel(model: model, kind: .home)

        await model.setFilterRule(pattern: "female", isEnabled: true, mode: .tagNamespace)
        await pageModel.load(query: pageModel.listQuery)
        #expect(pageModel.galleries.map(\.key) == [aiGenerated.key, clean.key])

        await model.setFilterRule(pattern: "ai generated", isEnabled: true, mode: .tag)
        await pageModel.load(query: pageModel.listQuery)
        #expect(pageModel.galleries.map(\.key) == [clean.key])
    }

    @Test("Tag filters fetch full tags through the gdata API before blocking")
    func tagFiltersEnrichListItemsFromAPI() async throws {
        let key = GalleryKey(gid: 41, token: "enrich")
        // The list page only carries a few summary tags; the full tag list
        // only comes from the gdata API, like the reference's fillGalleryListByApi.
        let sparse = GallerySummary(key: key, title: "Sparse summary", tags: ["language:english"])
        let api = TagFilterListAPI(
            items: [sparse],
            fullTagsByKey: [key: ["female:furry", "misc:ai generated"]]
        )
        let suiteName = "EhViewerTagEnrichTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: api,
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )
        await model.setFilterRule(pattern: "female", isEnabled: true, mode: .tagNamespace)
        let pageModel = BrowsePageModel(model: model, kind: .home)

        await pageModel.load(query: pageModel.listQuery)

        #expect(pageModel.galleries.isEmpty)
        #expect(await api.summaryRequestCount == 1)
    }

    @Test("Enqueue keeps page URLs so each download attempt can resolve a fresh image node")
    func enqueueKeepsResolvablePageURL() async throws {
        let suiteName = "EhViewerResolvableDownloadTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: OfflineReaderAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )
        let key = GalleryKey(gid: 23, token: "fresh")
        let pageURL = try #require(URL(string: "https://e-hentai.org/s/page-token/23-1"))
        let detail = GalleryDetail(
            summary: GallerySummary(key: key, title: "Fresh node"),
            pages: [GalleryPageDescriptor(galleryKey: key, index: 0, pageURL: pageURL)]
        )

        await model.enqueue(detail)
        let job = await model.downloadJob(for: key)

        #expect(job?.pages.first?.pageURL == pageURL)
        #expect(job?.pages.first?.requiresPageResolution == true)
    }

    @Test("Incoming AirDrop archives are staged, gallery sync is separated, and JSON backups are ignored")
    func incomingArchiveURLsAreStagedByExtension() async throws {
        let suiteName = "EhViewerIncomingURLTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )
        await waitUntilDownloadsLoaded(model)

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("incoming-\(UUID().uuidString).EHARCHIVE")
        try Data("not a zip".utf8).write(to: archiveURL)
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        model.handleIncomingURL(archiveURL)
        await waitForPendingIncomingArchive(model)
        #expect(model.pendingIncomingArchive?.stagedURL.pathExtension.lowercased() == "eharchive")
        #expect(FileManager.default.fileExists(atPath: archiveURL.path) == false)
        model.discardIncomingArchive()
        #expect(model.pendingIncomingArchive == nil)

        let gallerySyncURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("incoming-\(UUID().uuidString).ehgallery")
        try GallerySyncArchive.export(
            GallerySyncSnapshot(galleries: [
                GallerySummary(key: GalleryKey(gid: 99, token: "sync"), title: "Sync")
            ]),
            to: gallerySyncURL
        )
        defer { try? FileManager.default.removeItem(at: gallerySyncURL) }
        model.handleIncomingURL(gallerySyncURL)
        await waitForPendingIncomingGallerySync(model)
        #expect(model.pendingIncomingGallerySync?.stagedURL.pathExtension.lowercased() == "ehgallery")
        #expect(model.pendingIncomingArchive == nil)
        #expect(FileManager.default.fileExists(atPath: gallerySyncURL.path) == false)
        await model.confirmIncomingGallerySync()
        #expect(model.pendingIncomingGallerySync == nil)
        let syncedJob = try #require(await model.downloadJob(for: GalleryKey(gid: 99, token: "sync")))
        #expect(syncedJob.state == .paused)
        #expect(syncedJob.pages.isEmpty)

        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("incoming-\(UUID().uuidString).zip")
        try Data("not a zip".utf8).write(to: zipURL)
        defer { try? FileManager.default.removeItem(at: zipURL) }
        model.handleIncomingURL(zipURL)
        await waitForPendingIncomingArchive(model)
        #expect(model.pendingIncomingArchive?.stagedURL.pathExtension.lowercased() == "zip")
        model.discardIncomingArchive()
        #expect(model.pendingIncomingArchive == nil)

        let legacyBackupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("incoming-\(UUID().uuidString).ehbackup")
        try Data("{}".utf8).write(to: legacyBackupURL)
        defer { try? FileManager.default.removeItem(at: legacyBackupURL) }
        model.handleIncomingURL(legacyBackupURL)
        #expect(model.pendingIncomingArchive == nil)
    }

    @Test("Custom download archives and legacy ZIP files are accepted")
    func downloadArchiveImportTypesIncludeLegacyZip() {
        #expect(BackupFileFormat.downloadImportTypes == [.ehViewerDownloadArchive, .zip])
        #expect(BackupFileFormat.gallerySyncImportTypes == [.ehViewerGallerySync])
    }

    @Test("Discarding a temporary import copy deletes only files inside the app temporary directory")
    func discardTemporaryImportCopyOnlyRemovesTemporaryFiles() async throws {
        let suiteName = "EhViewerImportCopyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )

        let temporaryFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-import-copy-\(UUID().uuidString).eharchive")
        try Data("copy".utf8).write(to: temporaryFile)
        defer { try? FileManager.default.removeItem(at: temporaryFile) }

        let cachesDirectory = try #require(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        )
        let outsideFile = cachesDirectory
            .appendingPathComponent("ehviewer-import-copy-\(UUID().uuidString).eharchive")
        try Data("original".utf8).write(to: outsideFile)
        defer { try? FileManager.default.removeItem(at: outsideFile) }

        model.discardTemporaryImportCopy(temporaryFile)
        model.discardTemporaryImportCopy(outsideFile)

        #expect(FileManager.default.fileExists(atPath: temporaryFile.path) == false)
        #expect(FileManager.default.fileExists(atPath: outsideFile.path) == true)
    }

    @Test("Startup sweep removes stale EhViewer temporary leftovers but keeps fresh and unrelated files")
    func sweepStaleTemporaryFilesRemovesOldLeftovers() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let old = Date(timeIntervalSinceNow: -7200)

        let staleArchive = temporaryDirectory
            .appendingPathComponent("EhViewer-Downloads-All-20200101-0000.eharchive")
        try Data("stale".utf8).write(to: staleArchive)
        defer { try? FileManager.default.removeItem(at: staleArchive) }
        try FileManager.default.setAttributes([.creationDate: old], ofItemAtPath: staleArchive.path)

        let staleIncoming = temporaryDirectory
            .appendingPathComponent("EhViewer-Incoming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staleIncoming, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staleIncoming) }
        try FileManager.default.setAttributes([.creationDate: old], ofItemAtPath: staleIncoming.path)

        let freshArchive = temporaryDirectory
            .appendingPathComponent("EhViewer-Galleries-\(UUID().uuidString).ehgallery")
        try Data("fresh".utf8).write(to: freshArchive)
        defer { try? FileManager.default.removeItem(at: freshArchive) }

        let unrelated = temporaryDirectory
            .appendingPathComponent("incoming-\(UUID().uuidString).zip")
        try Data("unrelated".utf8).write(to: unrelated)
        defer { try? FileManager.default.removeItem(at: unrelated) }

        AppModel.sweepStaleTemporaryFiles()

        #expect(FileManager.default.fileExists(atPath: staleArchive.path) == false)
        #expect(FileManager.default.fileExists(atPath: staleIncoming.path) == false)
        #expect(FileManager.default.fileExists(atPath: freshArchive.path) == true)
        #expect(FileManager.default.fileExists(atPath: unrelated.path) == true)
    }

    @Test("Gallery sync export contains only galleries in the download list")
    func gallerySyncExportUsesDownloadList() async throws {
        let suiteName = "EhViewerGallerySyncExportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults
        )
        await waitUntilDownloadsLoaded(model)

        let cachedOnly = GallerySummary(key: GalleryKey(gid: 100, token: "cached"), title: "Cached only")
        let downloaded = GallerySummary(key: GalleryKey(gid: 101, token: "download"), title: "Downloaded")
        try await model.persistence.upsert([cachedOnly, downloaded])
        var job = DownloadJob(key: downloaded.key, title: downloaded.title, pages: [])
        job.state = .paused
        await model.downloads.restore([job])

        let archiveURL = try #require(await model.exportGallerySync())
        defer { model.discardPendingSharedFile(archiveURL) }
        let snapshot = try GallerySyncArchive.read(from: archiveURL)
        #expect(snapshot.galleries.map(\.key) == [downloaded.key])
    }

    @Test("Selected download export only contains the requested gallery keys")
    func selectedDownloadArchiveExportContainsOnlyRequestedKeys() async throws {
        let suiteName = "EhViewerSelectedDownloadExportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fileRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-selected-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: fileRoot) }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults,
            downloadFiles: DownloadFileStore(root: fileRoot, minimumFreeBytes: 1)
        )
        await waitUntilDownloadsLoaded(model)

        let imageData = try #require(Self.onePixelPNG)
        let firstKey = GalleryKey(gid: 71, token: "selected-a")
        let secondKey = GalleryKey(gid: 72, token: "selected-b")
        let firstPage = GalleryPageDescriptor(
            galleryKey: firstKey,
            index: 0,
            pageURL: try #require(URL(string: "https://example.invalid/selected-a-1.jpg"))
        )
        let secondPage = GalleryPageDescriptor(
            galleryKey: secondKey,
            index: 0,
            pageURL: try #require(URL(string: "https://example.invalid/selected-b-1.jpg"))
        )
        try await model.persistence.upsertDownload(
            key: firstKey,
            title: "Selected A",
            pages: [firstPage],
            completedPageIndexes: [],
            stateRaw: DownloadState.paused.rawValue,
            errorMessage: nil
        )
        try await model.persistence.upsertDownload(
            key: secondKey,
            title: "Selected B",
            pages: [secondPage],
            completedPageIndexes: [],
            stateRaw: DownloadState.paused.rawValue,
            errorMessage: nil
        )
        _ = try await model.downloadFiles.write(imageData, for: firstKey, pageIndex: 0)
        _ = try await model.downloadFiles.write(imageData, for: secondKey, pageIndex: 0)

        let archiveURL = try #require(await model.exportDownloadArchive(keys: [firstKey]))
        defer { model.discardPendingSharedFile(archiveURL) }

        let inspection = try await LegacyDownloadArchive.inspect(archiveURL)
        #expect(inspection.candidates.map(\.key) == [firstKey])
        #expect(inspection.candidates.count == 1)
    }

    @Test("Re-importing a download archive skips duplicate items and pages")
    func downloadArchiveReimportSkipsDuplicatePages() async throws {
        let suiteName = "EhViewerDownloadReimportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let destinationRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-reimport-destination-\(UUID().uuidString)")
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-reimport-source-\(UUID().uuidString)")
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-reimport-\(UUID().uuidString).eharchive")
        defer {
            try? FileManager.default.removeItem(at: destinationRoot)
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: archiveURL)
        }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults,
            downloadFiles: DownloadFileStore(root: destinationRoot, minimumFreeBytes: 1)
        )
        await waitUntilDownloadsLoaded(model)

        let imageData = try #require(Self.onePixelPNG)
        let key = GalleryKey(gid: 73, token: "reimport")
        let sourceStore = DownloadFileStore(root: sourceRoot, minimumFreeBytes: 1)
        for pageIndex in 0..<3 {
            _ = try await sourceStore.write(imageData, for: key, pageIndex: pageIndex)
        }
        let item = DownloadArchiveExportItem(
            key: key,
            title: "Reimport gallery",
            totalPageCount: 3,
            pageTokens: [:]
        )
        _ = try await DownloadArchiveExporter.export(items: [item], files: sourceStore, to: archiveURL)

        let firstOutcome = await model.restoreDownloads(from: archiveURL)
        #expect(firstOutcome.candidateCount == 1)
        #expect(firstOutcome.importedItemCount == 1)
        #expect(firstOutcome.mergedItemCount == 0)
        #expect(firstOutcome.skippedDuplicateItemCount == 0)
        #expect(firstOutcome.importedPageCount == 3)
        #expect(firstOutcome.skippedDuplicatePageCount == 0)
        #expect(await model.downloads.snapshot().count == 1)

        let secondOutcome = await model.restoreDownloads(from: archiveURL)
        #expect(secondOutcome.candidateCount == 1)
        #expect(secondOutcome.importedItemCount == 0)
        #expect(secondOutcome.mergedItemCount == 0)
        #expect(secondOutcome.skippedDuplicateItemCount == 1)
        #expect(secondOutcome.importedPageCount == 0)
        #expect(secondOutcome.skippedDuplicatePageCount == 3)
        #expect(secondOutcome.failedPageCount == 0)
        #expect(await model.downloads.snapshot().count == 1)
    }

    @Test("Partial archive import only writes pages missing from the local store")
    func partialArchiveImportWritesOnlyMissingPages() async throws {
        let suiteName = "EhViewerPartialArchiveImportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let destinationRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-partial-import-destination-\(UUID().uuidString)")
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-partial-import-source-\(UUID().uuidString)")
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-partial-import-\(UUID().uuidString).eharchive")
        defer {
            try? FileManager.default.removeItem(at: destinationRoot)
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: archiveURL)
        }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults,
            downloadFiles: DownloadFileStore(root: destinationRoot, minimumFreeBytes: 1)
        )
        await waitUntilDownloadsLoaded(model)

        let imageData = try #require(Self.onePixelPNG)
        let key = GalleryKey(gid: 74, token: "partial")
        let pageURL = try #require(URL(string: "https://example.invalid/partial-1.jpg"))
        var localJob = DownloadJob(
            key: key,
            title: "Partial local",
            pages: [GalleryPageDescriptor(galleryKey: key, index: 0, pageURL: pageURL)]
        )
        localJob.state = .paused
        await model.downloads.restore([localJob])
        _ = try await model.downloadFiles.write(imageData, for: key, pageIndex: 0)

        let sourceStore = DownloadFileStore(root: sourceRoot, minimumFreeBytes: 1)
        for pageIndex in 0..<3 {
            _ = try await sourceStore.write(imageData, for: key, pageIndex: pageIndex)
        }
        _ = try await DownloadArchiveExporter.export(
            items: [DownloadArchiveExportItem(key: key, title: "Partial archive", totalPageCount: 3, pageTokens: [:])],
            files: sourceStore,
            to: archiveURL
        )

        let outcome = await model.restoreDownloads(from: archiveURL)
        #expect(outcome.mergedItemCount == 1)
        #expect(outcome.importedPageCount == 2)
        #expect(outcome.skippedDuplicatePageCount == 1)
        #expect(await model.downloads.snapshot().count == 1)
        #expect(await model.downloadFiles.readablePageIndexes(for: key, pageIndexes: [0, 1, 2]) == [0, 1, 2])
    }

    @Test("Corrupt local pages are repaired by archive import")
    func corruptLocalPageIsRepairedByArchiveImport() async throws {
        let suiteName = "EhViewerCorruptPageRepairTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let destinationRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-corrupt-import-destination-\(UUID().uuidString)")
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-corrupt-import-source-\(UUID().uuidString)")
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-corrupt-import-\(UUID().uuidString).eharchive")
        defer {
            try? FileManager.default.removeItem(at: destinationRoot)
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: archiveURL)
        }
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true),
            api: ControlledListAPI(),
            sessionVault: SessionVault(service: suiteName),
            defaults: defaults,
            downloadFiles: DownloadFileStore(root: destinationRoot, minimumFreeBytes: 1)
        )
        await waitUntilDownloadsLoaded(model)

        let imageData = try #require(Self.onePixelPNG)
        let key = GalleryKey(gid: 75, token: "corrupt")
        let pageURL = try #require(URL(string: "https://example.invalid/corrupt-1.jpg"))
        var localJob = DownloadJob(
            key: key,
            title: "Corrupt local",
            pages: [GalleryPageDescriptor(galleryKey: key, index: 0, pageURL: pageURL)]
        )
        localJob.state = .paused
        await model.downloads.restore([localJob])
        _ = try await model.downloadFiles.write(imageData, for: key, pageIndex: 0)
        let finalURL = await model.downloadFiles.finalURL(for: key, pageIndex: 0)
        try Data("broken image payload".utf8).write(to: finalURL)

        let sourceStore = DownloadFileStore(root: sourceRoot, minimumFreeBytes: 1)
        _ = try await sourceStore.write(imageData, for: key, pageIndex: 0)
        _ = try await DownloadArchiveExporter.export(
            items: [DownloadArchiveExportItem(key: key, title: "Repair archive", totalPageCount: 1, pageTokens: [:])],
            files: sourceStore,
            to: archiveURL
        )

        let outcome = await model.restoreDownloads(from: archiveURL)
        #expect(outcome.mergedItemCount == 1)
        #expect(outcome.importedPageCount == 1)
        #expect(outcome.skippedDuplicatePageCount == 0)
        #expect(try await model.downloadFiles.data(for: key, pageIndex: 0) == imageData)
    }

    private func waitForPendingIncomingArchive(_ model: AppModel) async {
        for _ in 0..<500 where model.pendingIncomingArchive == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitForPendingIncomingGallerySync(_ model: AppModel) async {
        for _ in 0..<500 where model.pendingIncomingGallerySync == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitUntilDownloadsLoaded(_ model: AppModel) async {
        for _ in 0..<200 where model.isLoadingDownloads {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static var onePixelPNG: Data? {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
    }
}

private actor OfflineReaderAPI: EHAPI {
    func list(query: GalleryListQuery) async throws -> GalleryListPage {
        throw EHError.networkFailed("offline")
    }

    func detail(for key: GalleryKey, site: SiteMode) async throws -> GalleryDetail {
        throw EHError.networkFailed("offline")
    }

    func imageData(for image: GalleryPageImage, resolution: ImageResolution) async throws -> Data {
        Issue.record("a completed downloaded page must not use the network")
        throw EHError.networkFailed("offline")
    }
}

private actor TagFilterListAPI: EHAPI {
    private let items: [GallerySummary]
    private let fullTagsByKey: [GalleryKey: [String]]
    private(set) var summaryRequestCount = 0

    init(items: [GallerySummary], fullTagsByKey: [GalleryKey: [String]]) {
        self.items = items
        self.fullTagsByKey = fullTagsByKey
    }

    func list(query: GalleryListQuery) async throws -> GalleryListPage {
        GalleryListPage(items: items)
    }

    func detail(for key: GalleryKey, site: SiteMode) async throws -> GalleryDetail {
        throw EHError.networkFailed("offline")
    }

    func gallerySummaries(for keys: [GalleryKey], site: SiteMode) async throws -> [GallerySummary] {
        summaryRequestCount += 1
        return keys.compactMap { key in
            guard let tags = fullTagsByKey[key] else { return nil }
            var summary = GallerySummary(key: key, title: "fetched")
            summary.tags = tags
            return summary
        }
    }
}

private actor ControlledListAPI: EHAPI {
    private var requests = Set<String>()
    private var requestWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var responseContinuations: [String: CheckedContinuation<GalleryListPage, any Error>] = [:]

    func list(query: GalleryListQuery) async throws -> GalleryListPage {
        let searchText = query.searchText ?? ""
        requests.insert(searchText)
        requestWaiters.removeValue(forKey: searchText)?.forEach { $0.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            responseContinuations[searchText] = continuation
        }
    }

    func detail(for key: GalleryKey, site: SiteMode) async throws -> GalleryDetail {
        throw EHError.notFound
    }

    func waitUntilRequested(_ searchText: String) async {
        if requests.contains(searchText) { return }
        await withCheckedContinuation { continuation in
            requestWaiters[searchText, default: []].append(continuation)
        }
    }

    func respond(to searchText: String, with page: GalleryListPage) -> Bool {
        guard let continuation = responseContinuations.removeValue(forKey: searchText) else { return false }
        continuation.resume(returning: page)
        return true
    }
}

private actor ControlledTagSuggestionLoader {
    private var requests = Set<String>()
    private var requestWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var responseContinuations: [String: CheckedContinuation<[SearchTagSuggestion], any Error>] = [:]

    func suggestions(for keyword: String) async throws -> [SearchTagSuggestion] {
        requests.insert(keyword)
        requestWaiters.removeValue(forKey: keyword)?.forEach { $0.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            responseContinuations[keyword] = continuation
        }
    }

    func waitUntilRequested(_ keyword: String) async {
        if requests.contains(keyword) { return }
        await withCheckedContinuation { continuation in
            requestWaiters[keyword, default: []].append(continuation)
        }
    }

    func respond(to keyword: String, with suggestions: [SearchTagSuggestion]) -> Bool {
        guard let continuation = responseContinuations.removeValue(forKey: keyword) else { return false }
        continuation.resume(returning: suggestions)
        return true
    }
}

private actor KindListAPI: EHAPI {
    func list(query: GalleryListQuery) async throws -> GalleryListPage {
        let title = switch query.kind {
        case .popular: "Popular result"
        default: "Home result"
        }
        return GalleryListPage(
            items: [GallerySummary(
                key: GalleryKey(gid: query.kind == .popular ? 2 : 1, token: query.kind.rawValue),
                title: title
            )]
        )
    }

    func detail(for key: GalleryKey, site: SiteMode) async throws -> GalleryDetail {
        throw EHError.notFound
    }
}

private actor SearchPaginationAPI: EHAPI {
    let firstPage: GalleryListPage
    let secondPage: GalleryListPage
    private var pageURLs: [URL] = []
    private var firstPageRequests = 0

    init(firstPage: GalleryListPage, secondPage: GalleryListPage) {
        self.firstPage = firstPage
        self.secondPage = secondPage
    }

    func list(query: GalleryListQuery) async throws -> GalleryListPage {
        firstPageRequests += 1
        return firstPage
    }

    func list(query: GalleryListQuery, pageURL: URL?) async throws -> GalleryListPage {
        if let pageURL { pageURLs.append(pageURL) }
        return secondPage
    }

    func detail(for key: GalleryKey, site: SiteMode) async throws -> GalleryDetail {
        throw EHError.notFound
    }

    func requestedPageURLs() -> [URL] {
        pageURLs
    }

    func firstPageRequestCount() -> Int {
        firstPageRequests
    }
}
