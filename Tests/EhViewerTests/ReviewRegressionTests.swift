import Foundation
import SwiftData
import Testing
import EHDomain
import EHNetworking
import EHPersistence
import EHDownloads
import EHDeviceSync
@testable import EhViewerPreview

@MainActor
struct ReviewRegressionTests {
    private func makeModel(api: any EHAPI = ReviewBrowseAPI(), galleryCache: GalleryCacheStore? = nil) async throws -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-review-\(UUID().uuidString)")
        let defaults = try #require(UserDefaults(suiteName: "EhViewerReview-\(UUID().uuidString)"))
        let model = AppModel(
            container: try ModelContainerFactory.make(inMemory: true), api: api,
            sessionVault: SessionVault(service: "EhViewerReview-\(UUID().uuidString)"), defaults: defaults,
            downloadFiles: DownloadFileStore(root: root.appendingPathComponent("Downloads")),
            translationRoot: root.appendingPathComponent("Translations"),
            galleryCache: galleryCache ?? GalleryCacheStore(root: root.appendingPathComponent("GalleryCache")),
            tagSuggestionProvider: TagSuggestionProvider(
                sourceURLs: [], cacheURL: root.appendingPathComponent("Tags"),
                bundledDatabaseURL: root.appendingPathComponent("NoBundledTagDatabase")
            ),
            imagePipeline: ImagePipeline(diskRoot: root.appendingPathComponent("Images")),
            galleryCoverLoader: GalleryCoverLoader(diskRoot: root.appendingPathComponent("Thumbnails")),
            deviceSyncIndex: DeviceSyncIndexStore(root: root.appendingPathComponent("Index")),
            deviceSyncTransactionRoot: root.appendingPathComponent("Transactions")
        )
        await model.waitUntilReady()
        return model
    }

    @Test("A search superseded during tag enrichment cannot publish stale results", .timeLimit(.minutes(1)), arguments: [false, true])
    func latestEnrichedSearchWins(legacyModel: Bool) async throws {
        let gate = ReviewGate<Void>()
        let api = ReviewBrowseAPI(delayedKey: ReviewBrowseAPI.first.key, gate: gate)
        let model = try await makeModel(api: api)
        let page = BrowsePageModel(model: model, kind: .search)
        let first = Task {
            if legacyModel { await model.load(query: GalleryListQuery(searchText: "first")) }
            else { await page.load(query: GalleryListQuery(searchText: "first")) }
        }
        await gate.waitUntilStarted()
        if legacyModel { await model.load(query: GalleryListQuery(searchText: "second")) }
        else { await page.load(query: GalleryListQuery(searchText: "second")) }
        await gate.release(())
        await first.value
        #expect((legacyModel ? model.galleries : page.galleries).map(\.key) == [ReviewBrowseAPI.second.key])
        #expect(!(legacyModel ? model.isLoading : page.isLoading))
    }

    @Test("An old pagination enrichment cannot append to a new search", .timeLimit(.minutes(1)))
    func stalePaginationIsDiscarded() async throws {
        let gate = ReviewGate<Void>()
        let api = ReviewBrowseAPI(delayedKey: ReviewBrowseAPI.next.key, gate: gate)
        let model = try await makeModel(api: api)
        let page = BrowsePageModel(model: model, kind: .search)
        await page.load(query: GalleryListQuery(searchText: "first"))
        let pagination = Task { await page.loadMore() }
        await gate.waitUntilStarted()
        await page.load(query: GalleryListQuery(searchText: "second"))
        await gate.release(())
        await pagination.value
        #expect(page.galleries.map(\.key) == [ReviewBrowseAPI.second.key])
    }

    @Test("New query clears old results while same-query refresh preserves them", .timeLimit(.minutes(1)))
    func queryAndRefreshContentPolicy() async throws {
        let model = try await makeModel()
        let page = BrowsePageModel(model: model, kind: .search)
        let query = GalleryListQuery(searchText: "first")
        await page.load(query: query)
        let old = page.galleries
        // The API suspension makes the intermediate loading state observable.
        let gate = ReviewGate<Void>()
        let api = ReviewBrowseAPI(delayedKey: ReviewBrowseAPI.first.key, gate: gate)
        let otherModel = try await makeModel(api: api)
        let otherPage = BrowsePageModel(model: otherModel, kind: .search)
        await otherPage.load(query: GalleryListQuery(searchText: "second"))
        otherPage.scrollPosition = ReviewBrowseAPI.second.key
        let load = Task { await otherPage.load(query: query) }
        await gate.waitUntilStarted()
        #expect(otherPage.galleries.isEmpty)
        #expect(otherPage.scrollPosition == nil)
        #expect(otherPage.isLoading)
        await gate.release(())
        await load.value
        #expect(otherPage.galleries == old)

        let refresh = Task { await otherPage.load(query: query) }
        await gate.waitUntilStarted()
        #expect(otherPage.galleries == old)
        await gate.release(())
        await refresh.value
    }

    @Test("Pagination retries retain the exact cursor and clear the previous error")
    func failedPaginationCanRetry() async throws {
        let api = ReviewBrowseAPI()
        let model = try await makeModel(api: api)
        let page = BrowsePageModel(model: model, kind: .search)
        await page.load(query: GalleryListQuery(searchText: "first"))
        let cursor = page.nextPageURL
        await api.failNextRequest()
        await page.loadMore()
        #expect(page.paginationErrorMessage != nil)
        #expect(page.nextPageURL == cursor)
        #expect(page.galleries.map(\.key) == [ReviewBrowseAPI.first.key])
        await page.loadMore()
        #expect(page.paginationErrorMessage == nil)
        #expect(page.galleries.map(\.key) == [ReviewBrowseAPI.first.key, ReviewBrowseAPI.next.key])
        #expect(await api.pageURLs == [cursor, cursor].compactMap { $0 })
    }

    @Test("Refresh failure keeps the existing content and pagination cursor")
    func failedRefreshRetainsContent() async throws {
        let api = ReviewBrowseAPI()
        let model = try await makeModel(api: api)
        let page = BrowsePageModel(model: model, kind: .search)
        let query = GalleryListQuery(searchText: "first")
        await page.load(query: query)
        let cursor = page.nextPageURL
        await api.failNextRequest()
        await page.load(query: query)
        #expect(page.errorMessage != nil)
        #expect(page.nextPageURL == cursor)
        #expect(page.galleries.map(\.key) == [ReviewBrowseAPI.first.key])
        await page.load(query: query)
        #expect(page.errorMessage == nil)
    }

    @Test("Explicit refresh reloads a cached browse page while returning from detail does not")
    func explicitRefreshReloadsCachedPage() async throws {
        let api = ReviewBrowseAPI()
        let model = try await makeModel(api: api)
        let page = BrowsePageModel(model: model, kind: .search)
        let query = GalleryListQuery(searchText: "first")
        await page.loadIfNeeded(query: query)
        await page.loadIfNeeded(query: query)
        #expect(await api.listRequestCount == 1)
        model.requestBrowseRefresh()
        await page.loadIfNeeded(query: query)
        #expect(await api.listRequestCount == 2)
    }

    @Test("URLSession-style cancellation does not become a visible browse error", .timeLimit(.minutes(1)), arguments: [false, true])
    func cancelledTransportDoesNotPublishError(legacyModel: Bool) async throws {
        let gate = ReviewGate<Void>()
        let api = ReviewBrowseAPI(listFailureGate: gate)
        let model = try await makeModel(api: api)
        let page = BrowsePageModel(model: model, kind: .search)
        let load = Task {
            if legacyModel { await model.load(query: GalleryListQuery(searchText: "first")) }
            else { await page.load(query: GalleryListQuery(searchText: "first")) }
        }
        await gate.waitUntilStarted()
        load.cancel()
        await gate.release(())
        await load.value
        #expect((legacyModel ? model.errorMessage : page.errorMessage) == nil)
        #expect(!(legacyModel ? model.isLoading : page.isLoading))
    }

    @Test("A configuration change during enrichment discards the old page", .timeLimit(.minutes(1)))
    func configurationChangeDiscardsEnrichment() async throws {
        let gate = ReviewGate<Void>()
        let api = ReviewBrowseAPI(delayedKey: ReviewBrowseAPI.first.key, gate: gate)
        let model = try await makeModel(api: api)
        let page = BrowsePageModel(model: model, kind: .search)
        let load = Task { await page.load(query: GalleryListQuery(searchText: "first")) }
        await gate.waitUntilStarted()
        model.filterRules = [FilterRuleSnapshot(pattern: "First", isEnabled: true)]
        await gate.release(())
        await load.value
        #expect(page.galleries.isEmpty)
        #expect(!page.isLoading)
        #expect(page.nextPageURL == nil)
        await page.load(query: GalleryListQuery(searchText: "second"))
        #expect(page.galleries.map(\.key) == [ReviewBrowseAPI.second.key])
    }

    @Test("A site change during tag enrichment cannot publish the previous site's list", .timeLimit(.minutes(1)), arguments: [false, true])
    func siteChangeDiscardsEnrichment(legacyModel: Bool) async throws {
        let gate = ReviewGate<Void>()
        let api = ReviewBrowseAPI(delayedKey: ReviewBrowseAPI.first.key, gate: gate)
        let model = try await makeModel(api: api)
        model.site = .eHentai
        let page = BrowsePageModel(model: model, kind: .search)
        let load = Task {
            if legacyModel { await model.load(query: GalleryListQuery(searchText: "first")) }
            else { await page.load(query: GalleryListQuery(searchText: "first")) }
        }
        await gate.waitUntilStarted()
        model.site = .exHentai
        await gate.release(())
        await load.value
        #expect((legacyModel ? model.galleries : page.galleries).isEmpty)
    }

    @Test("Blocked content has a distinct state and automatic loading remains bounded")
    func blockedPagesHaveDistinctState() async throws {
        let model = try await makeModel()
        model.filterRules = [FilterRuleSnapshot(pattern: "First", isEnabled: true)]
        let page = BrowsePageModel(model: model, kind: .search)
        await page.load(query: GalleryListQuery(searchText: "first"))
        #expect(page.isContentFiltered)
        #expect(page.galleries.isEmpty)
        #expect(page.nextPageURL != nil)
        #expect(page.shouldAutomaticallyLoadMore)
        await page.loadMore()
        #expect(!page.isContentFiltered)
        #expect(page.galleries.map(\.key) == [ReviewBrowseAPI.next.key])
    }

    @Test("A cache cleanup failure is reported and does not report success")
    func cacheClearReportsFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-cache-failure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocker = root.appendingPathComponent("not-a-directory")
        let sentinel = Data("must remain intact".utf8)
        try sentinel.write(to: blocker)
        let model = try await makeModel(galleryCache: GalleryCacheStore(root: blocker.appendingPathComponent("Cache")))
        await model.clearGalleryCache()
        #expect(model.errorMessage != nil)
        #expect(model.storageMaintenanceMessage == nil)
        #expect(!model.isClearingGalleryCache)
        #expect(try Data(contentsOf: blocker) == sentinel)
    }

    @Test("Async media decoding reports invalid data and respects caller cancellation")
    func asynchronousDecodeFailures() async throws {
        await #expect(throws: EHError.self) {
            _ = try await ReaderMediaView.Content.decode(Data("invalid".utf8))
        }
        let decode = Task { try await ReaderMediaView.Content.decode(Self.png) }
        decode.cancel()
        do { _ = try await decode.value; Issue.record("Cancelled decode should not publish content") }
        catch is CancellationError {}
    }

    @Test("Library clear actions preserve progress and do not change one another")
    func independentLibraryClearActions() async throws {
        let store = PersistenceStore(modelContainer: try ModelContainerFactory.make(inMemory: true))
        let summaries = (0..<60).map { GallerySummary(key: GalleryKey(gid: Int64(8_000 + $0), token: "retained"), title: "Book \($0)") }
        try await store.upsert(summaries)
        for summary in summaries {
            try await store.updateReadingProgress(for: summary.key, page: 7)
            try await store.setFavorite(for: summary.key, isFavorite: true)
        }
        try await store.clearHistory()
        #expect(try await store.recent().isEmpty)
        #expect(try await store.favorites(limit: 100).count == 60)
        try await store.clearFavorites()
        #expect(try await store.favorites().isEmpty)
        for summary in summaries { #expect(try await store.readingPage(for: summary.key) == 7) }
    }

    @Test("Cache clear counts all media caches and preserves library data and local files")
    func cacheClearPreservesLibraryAndOtherProfiles() async throws {
        let model = try await makeModel()
        let other = try await makeModel()
        let summary = ReviewBrowseAPI.first
        for target in [model, other] {
            try await target.persistence.upsert([summary])
            try await target.persistence.updateReadingProgress(for: summary.key, page: 9)
            try await target.persistence.setFavorite(for: summary.key, isFavorite: true)
            _ = try await target.imagePipeline.data(for: URL(string: "https://example.invalid/cover")!) { Self.png }
            _ = try await target.galleryCoverLoader.image(for: "review-cover", maxPixelSize: 20) { Self.png }
        }
        let localFile = await model.downloadFiles.finalURL(for: summary.key, pageIndex: 0)
        try FileManager.default.createDirectory(at: localFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.png.write(to: localFile)
        await model.refreshGalleryCacheUsage()
        #expect(model.galleryCacheByteCount > Int64(Self.png.count))
        await model.clearGalleryCache()
        #expect(model.galleryCacheByteCount == 0)
        #expect(model.storageMaintenanceMessage != nil)
        #expect(try await model.persistence.recent().first?.title == summary.title)
        #expect(try await model.persistence.favorites().first?.title == summary.title)
        #expect(try await model.persistence.readingPage(for: summary.key) == 9)
        #expect(try Data(contentsOf: localFile) == Self.png)
        #expect(await other.imagePipeline.diskUsage() > 0)
        #expect(try await other.persistence.isFavorite(for: summary.key) == true)
    }

    @Test("Image cache hashing supports long URLs and existing Base64 cache entries")
    func imageDiskCacheCompatibility() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-cache-format-\(UUID().uuidString)")
        let url = URL(string: "https://example.invalid/" + String(repeating: "long-signed-value", count: 50))!
        let first = ImagePipeline(byteLimit: 1, diskRoot: root)
        _ = try await first.data(for: url) { Self.png }
        let path = try #require(await first.diskPath(for: url))
        #expect(URL(fileURLWithPath: path).lastPathComponent.utf8.count <= 255)
        let second = ImagePipeline(diskRoot: root)
        #expect(try await second.data(for: url) { throw EHError.notFound } == Self.png)

        let legacyURL = URL(string: "https://example.invalid/legacy")!
        let legacyName = Data(legacyURL.absoluteString.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
        try Self.png.write(to: root.appendingPathComponent(legacyName + ".bin"))
        #expect(try await second.data(for: legacyURL) { throw EHError.notFound } == Self.png)
        #expect(await second.diskPath(for: legacyURL) != nil)
    }

    @Test("An image fetch that ignores cancellation cannot refill cleared caches or remove a replacement fetch", .timeLimit(.minutes(1)))
    func imageCacheClearDiscardsLateFetch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-cache-race-\(UUID().uuidString)")
        let pipeline = ImagePipeline(diskRoot: root)
        let url = URL(string: "https://example.invalid/shared")!
        let oldGate = ReviewGate<Data>()
        let newGate = ReviewGate<Data>()
        let old = Task { try await pipeline.data(for: url) { await oldGate.wait() } }
        await oldGate.waitUntilStarted()
        try await pipeline.clear()
        let replacement = Task { try await pipeline.data(for: url) { await newGate.wait() } }
        await newGate.waitUntilStarted()
        await oldGate.release(Data("old".utf8))
        do { _ = try await old.value; Issue.record("Cleared fetch should be cancelled") }
        catch is CancellationError {}
        #expect(await pipeline.diskUsage() == 0)
        await newGate.release(Data("new".utf8))
        #expect(try await replacement.value == Data("new".utf8))
        #expect(try await pipeline.data(for: url) { throw EHError.notFound } == Data("new".utf8))
    }

    @Test("Clearing thumbnails prevents an old remote cover from writing back", .timeLimit(.minutes(1)))
    func coverClearDiscardsLateFetch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-cover-race-\(UUID().uuidString)")
        let loader = GalleryCoverLoader(diskRoot: root)
        let gate = ReviewGate<Data>()
        let load = Task { try await loader.image(for: "cover", maxPixelSize: 20) { await gate.wait() } }
        await gate.waitUntilStarted()
        try await loader.clear()
        await gate.release(Self.png)
        do { _ = try await load.value; Issue.record("Cleared cover should be cancelled") }
        catch is CancellationError {}
        #expect(await loader.diskUsage() == 0)
        #expect(try await loader.image(for: "cover", maxPixelSize: 20) { Self.png } != nil)
    }

    @Test("Media format detection uses bytes and repeated saves never overwrite existing files")
    func mediaFormatAndExclusiveSave() throws {
        #expect(DownloadMediaValidator.fileExtension(of: Self.png) == "png")
        #expect(DownloadMediaValidator.fileExtension(of: Data([0x1a, 0x45, 0xdf, 0xa3])) == "webm")
        #expect(DownloadMediaValidator.fileExtension(of: Data([0, 0, 1, 0xba])) == "mpg")
        #expect(DownloadMediaValidator.fileExtension(of: Data([0, 0, 0, 12, 0x66, 0x74, 0x79, 0x70, 0, 0, 0, 0])) == "mp4")
        #expect(DownloadMediaValidator.fileExtension(of: Data("<html>error</html>".utf8)) == nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-media-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = try AppModel.saveMediaData(Self.png, named: "page.png", in: root)
        let secondData = Data("existing file must survive".utf8)
        let second = try AppModel.saveMediaData(secondData, named: "page.png", in: root)
        #expect(original != second)
        #expect(try Data(contentsOf: original) == Self.png)
        #expect(try Data(contentsOf: second) == secondData)
    }

    @Test("Image indexes distinguish optional page, URL, site and exact gallery key")
    func imageIndexUsesExactIdentity() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let url = URL(string: "https://example.invalid/image")!
        let key = ReviewBrowseAPI.first.key
        for index in [nil, 0, 1] as [Int?] {
            try await store.recordImageIndex(key: key, site: .eHentai, kind: "preview", pageIndex: index, originalURL: url, localPath: "old", byteCount: 1)
        }
        try await store.recordImageIndex(key: key, site: .eHentai, kind: "preview", pageIndex: 0, originalURL: url, localPath: "updated", byteCount: 2)
        try await store.recordImageIndex(key: key, site: .exHentai, kind: "preview", pageIndex: 0, originalURL: url, localPath: "other-site", byteCount: 1)
        try await store.recordImageIndex(key: GalleryKey(gid: key.gid, token: "other"), site: .eHentai, kind: "preview", pageIndex: 0, originalURL: url, localPath: "other-key", byteCount: 1)
        try await store.recordImageIndex(key: key, site: .eHentai, kind: "original", pageIndex: 0, originalURL: url, localPath: "other-kind", byteCount: 1)
        try await store.recordImageIndex(key: key, site: .eHentai, kind: "preview", pageIndex: 0, originalURL: URL(string: "https://example.invalid/other")!, localPath: "other-url", byteCount: 1)
        let records = try ModelContext(container).fetch(FetchDescriptor<GalleryImageIndexRecord>())
        #expect(records.count == 7)
        #expect(records.filter { $0.localPath == "updated" }.count == 1)
    }

    nonisolated private static var png: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    }
}

private actor ReviewGate<Value: Sendable> {
    private var waiter: CheckedContinuation<Value, Never>?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async -> Value {
        await withCheckedContinuation { continuation in
            waiter = continuation
            let started = startedWaiters
            startedWaiters = []
            for observer in started { observer.resume() }
        }
    }

    func waitUntilStarted() async {
        if waiter != nil { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func release(_ value: Value) {
        waiter?.resume(returning: value)
        waiter = nil
    }
}

private actor ReviewBrowseAPI: EHAPI {
    static let first = GallerySummary(key: GalleryKey(gid: 81, token: "first"), title: "First")
    static let second = GallerySummary(key: GalleryKey(gid: 82, token: "second"), title: "Second")
    static let next = GallerySummary(key: GalleryKey(gid: 83, token: "next"), title: "Next")
    let delayedKey: GalleryKey?
    let gate: ReviewGate<Void>?
    let listFailureGate: ReviewGate<Void>?
    private var shouldFail = false
    private(set) var listRequestCount = 0
    private(set) var pageURLs: [URL] = []

    init(delayedKey: GalleryKey? = nil, gate: ReviewGate<Void>? = nil, listFailureGate: ReviewGate<Void>? = nil) {
        self.delayedKey = delayedKey
        self.gate = gate
        self.listFailureGate = listFailureGate
    }

    func failNextRequest() { shouldFail = true }

    func list(query: GalleryListQuery) async throws -> GalleryListPage {
        listRequestCount += 1
        if let listFailureGate {
            await listFailureGate.wait()
            throw URLError(.cancelled)
        }
        if shouldFail { shouldFail = false; throw EHError.networkFailed("offline") }
        return GalleryListPage(items: [query.searchText == "second" ? Self.second : Self.first], cursor: GalleryCursor(page: 0, nextPageURL: URL(string: "https://example.invalid/?next=83")!))
    }

    func list(query: GalleryListQuery, pageURL: URL?) async throws -> GalleryListPage {
        if let pageURL { pageURLs.append(pageURL) }
        if shouldFail { shouldFail = false; throw EHError.networkFailed("offline") }
        return GalleryListPage(items: [Self.next])
    }

    func gallerySummaries(for keys: [GalleryKey], site: SiteMode) async throws -> [GallerySummary] {
        if let delayedKey, keys.contains(delayedKey), let gate { await gate.wait() }
        return []
    }

    func detail(for key: GalleryKey, site: SiteMode) async throws -> GalleryDetail { throw EHError.notFound }
}
