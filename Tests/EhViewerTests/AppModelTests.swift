import Foundation
import Testing
import EHDomain
import EHNetworking
import EHPersistence
import EHDownloads
@testable import EhViewerPreview

@MainActor
struct AppModelTests {
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
            sourceURL: URL(string: "https://example.invalid/tags")!,
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
            SearchTagSuggestion(english: "group:blue archive", localizedText: "蓝色档案")
        ])
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
