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

private actor SearchPaginationAPI: EHAPI {
    let firstPage: GalleryListPage
    let secondPage: GalleryListPage
    private var pageURLs: [URL] = []

    init(firstPage: GalleryListPage, secondPage: GalleryListPage) {
        self.firstPage = firstPage
        self.secondPage = secondPage
    }

    func list(query: GalleryListQuery) async throws -> GalleryListPage {
        firstPage
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
}
