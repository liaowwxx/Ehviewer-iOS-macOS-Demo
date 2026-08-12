import Foundation
import Observation
import SwiftData
import EHDomain
import EHNetworking
import EHPersistence
import EHDownloads

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let forceGuestMode: Bool
    let api: any EHAPI
    let persistence: PersistenceStore
    let downloads: DownloadCoordinator
    let sessionVault: SessionVault
    let imagePipeline: ImagePipeline
    let backgroundSession: BackgroundDownloadSession
    let downloadFiles: DownloadFileStore

    var site: SiteMode
    var galleries: [GallerySummary] = []
    var historyGalleries: [GallerySummary] = []
    var favoriteGalleries: [GallerySummary] = []
    var filterRules: [FilterRuleSnapshot] = []
    var tagTranslations: [String: String] = [:]
    var quickSearches: [String] = []
    var imageQuota: ImageQuota?
    var localArchive: LocalArchiveDocument?
    var selectedRoute: AppRoute? = .browse
    var isLoading = false
    var searchText = ""
    var isGuestMode = true
    var isPasswordLoginInProgress = false
    var appLockEnabled: Bool
    var isLocked: Bool
    var errorMessage: String?
    private(set) var nextPageURL: URL?
    var hasMorePage: Bool { nextPageURL != nil }
    private var activeQuery = GalleryListQuery()
    private var activeListRequestID = UUID()

    init(
        container: ModelContainer,
        api: (any EHAPI)? = nil,
        sessionVault: SessionVault = SessionVault(),
        defaults: UserDefaults = .standard,
        downloadFiles: DownloadFileStore? = nil
    ) {
        self.defaults = defaults
        site = SiteMode(rawValue: defaults.string(forKey: "site") ?? "") ?? .eHentai
        let arguments = ProcessInfo.processInfo.arguments
        let forceGuestModeForUITest = arguments.contains("-UITestUseGuestMode")
        forceGuestMode = forceGuestModeForUITest
        if forceGuestModeForUITest {
            isGuestMode = true
        }
        appLockEnabled = defaults.object(forKey: "appLockEnabled") as? Bool ?? false
        isLocked = defaults.object(forKey: "appLockEnabled") as? Bool ?? false
        self.sessionVault = sessionVault
        let client: any EHAPI = api ?? EHClient(sessionVault: sessionVault)
        self.api = client
        let store = PersistenceStore(modelContainer: container)
        persistence = store
        imagePipeline = ImagePipeline()
        let fileStore = downloadFiles ?? DownloadFileStore()
        self.downloadFiles = fileStore
        let backgroundSession = BackgroundDownloadSession(
            taskObserver: { description, identifier in
                guard let (key, pageIndex) = parseDownloadTaskDescription(description) else { return }
                try? await store.setBackgroundTaskIdentifier(identifier, for: key, pageIndex: pageIndex)
            },
            orphanCompletion: { description, data, statusCode in
                guard (200..<300).contains(statusCode),
                      let (key, pageIndex) = parseDownloadTaskDescription(description) else { return }
                do {
                    _ = try await fileStore.write(data, for: key, pageIndex: pageIndex)
                    try await store.markDownloadPageCompleted(for: key, pageIndex: pageIndex, bytes: Int64(data.count))
                } catch {
                    return
                }
            }
        )
        self.backgroundSession = backgroundSession
        downloads = DownloadCoordinator(
            pageLoader: { descriptor in
                var request = URLRequest(url: descriptor.pageURL)
                request.httpMethod = "GET"
                request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
                if let cookieHeader = try? await sessionVault.loadCookieHeader() {
                    request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                }
                return try await backgroundSession.data(
                    for: request,
                    taskDescription: "\(descriptor.galleryKey.gid)|\(descriptor.galleryKey.token)|\(descriptor.index)"
                )
            },
            fileStore: fileStore,
            persistence: { job in
                try? await store.upsertDownload(
                    key: job.key,
                    title: job.title,
                    pages: job.pages,
                    completedPageIndexes: job.completedPageIndexes,
                    stateRaw: job.state.rawValue,
                    errorMessage: job.errorMessage,
                    label: job.label
                )
            },
            removal: { key in try? await store.deleteDownload(for: key) }
        )
        Task { @MainActor [weak self] in
            if self?.forceGuestMode == false {
                await self?.refreshSessionStatus()
            }
            await self?.loadFilterRules()
            await self?.loadTagTranslations()
            await self?.restoreDownloads()
        }
    }

    func load(query: GalleryListQuery? = nil) async {
        let requestID = UUID()
        activeListRequestID = requestID
        isLoading = true
        nextPageURL = nil
        var loadedNextPageURL: URL?
        var didLoadPage = false
        defer {
            if activeListRequestID == requestID {
                isLoading = false
                if didLoadPage {
                    nextPageURL = loadedNextPageURL
                }
            }
        }
        let query = query ?? GalleryListQuery(site: site, searchText: searchText.nilIfEmpty)
        activeQuery = query
        do {
            let result = if query.kind == .favorites {
                try await api.favorites(query: query)
            } else {
                try await api.list(query: query)
            }
            try Task.checkCancellation()
            guard activeListRequestID == requestID else { return }
            galleries = result.items.filter(matchesFilter)
            loadedNextPageURL = result.cursor?.nextPageURL
            didLoadPage = true
            try await persistence.upsert(result.items)
            if let searchText = query.searchText { try? await persistence.recordQuickSearch(searchText) }
            quickSearches = (try? await persistence.quickSearches()) ?? quickSearches
        } catch is CancellationError {
            // View lifecycle cancellation is expected.
        } catch {
            if activeListRequestID == requestID {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadBrowseQuery(_ query: GalleryListQuery) async {
        activeListRequestID = UUID()
        isLoading = false
        nextPageURL = nil
        if query.searchText?.isEmpty == false {
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
        }
        guard Task.isCancelled == false else { return }
        await load(query: query)
    }

    func searchTag(_ tag: String) {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTag.isEmpty == false else { return }
        searchText = normalizedTag
        selectedRoute = .browse
    }

    func loadMore() async {
        guard let pageURL = nextPageURL, isLoading == false else { return }
        let requestID = activeListRequestID
        var query = activeQuery
        query.page += 1
        isLoading = true
        var loadedNextPageURL: URL?
        var didLoadPage = false
        defer {
            if activeListRequestID == requestID {
                isLoading = false
                if didLoadPage {
                    nextPageURL = loadedNextPageURL
                }
            }
        }
        do {
            let result = try await api.list(query: query, pageURL: pageURL)
            try Task.checkCancellation()
            guard activeListRequestID == requestID else { return }
            appendUniqueGalleries(result.items)
            loadedNextPageURL = result.cursor?.nextPageURL
            didLoadPage = true
            activeQuery = query
            try await persistence.upsert(result.items)
        } catch is CancellationError {
            return
        } catch {
            if activeListRequestID == requestID {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMoreIfNeeded(after galleryKey: GalleryKey) async {
        guard galleries.last?.key == galleryKey else { return }
        await loadMore()
    }

    func searchByImage(data: Data, fileName: String, options: ImageSearchOptions) async {
        let requestID = UUID()
        activeListRequestID = requestID
        isLoading = true
        nextPageURL = nil
        var loadedNextPageURL: URL?
        var didLoadPage = false
        defer {
            if activeListRequestID == requestID {
                isLoading = false
                if didLoadPage {
                    nextPageURL = loadedNextPageURL
                }
            }
        }
        do {
            let result = try await api.imageSearch(imageData: data, fileName: fileName, site: site, options: options)
            try Task.checkCancellation()
            guard activeListRequestID == requestID else { return }
            galleries = result.items.filter(matchesFilter)
            activeQuery = GalleryListQuery(site: site, kind: .search)
            loadedNextPageURL = result.cursor?.nextPageURL
            didLoadPage = true
            try await persistence.upsert(result.items)
        } catch is CancellationError {
            return
        } catch {
            if activeListRequestID == requestID {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadImageQuota() async {
        do {
            imageQuota = try await api.imageQuota(site: site)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetImageQuota() async {
        do {
            imageQuota = try await api.resetImageQuota(site: site)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retryLastListRequest() async {
        await load(query: activeQuery)
    }

    func detail(for key: GalleryKey) async -> GalleryDetail? {
        do {
            let detail = try await api.detail(for: key, site: site)
            try await persistence.upsert([detail.summary])
            return detail
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func pageImage(for descriptor: GalleryPageDescriptor) async throws -> GalleryPageImage {
        try await api.pageImage(for: descriptor, site: site)
    }

    func imageData(for image: GalleryPageImage, resolution: ImageResolution = .preview) async throws -> Data {
        let api = self.api
        return try await imagePipeline.data(for: imageURL(for: image, resolution: resolution)) {
            try await api.imageData(for: image, resolution: resolution)
        }
    }

    func downloadedPageData(
        for descriptor: GalleryPageDescriptor,
        resolution: ImageResolution = .preview
    ) async throws -> Data {
        do {
            return try await downloadFiles.data(
                for: descriptor.galleryKey,
                pageIndex: descriptor.index
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let directImage = GalleryPageImage(
                galleryKey: descriptor.galleryKey,
                index: descriptor.index,
                imageURL: descriptor.pageURL
            )
            return try await imageData(for: directImage, resolution: resolution)
        }
    }

    func savePage(_ descriptor: GalleryPageDescriptor, resolution: ImageResolution = .preview) async {
        do {
            if await downloadFiles.contains(descriptor.galleryKey, pageIndex: descriptor.index) { return }
            let image = try await pageImage(for: descriptor)
            let data = try await imageData(for: image, resolution: resolution)
            _ = try await downloadFiles.write(data, for: descriptor.galleryKey, pageIndex: descriptor.index)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prefetch(_ descriptors: [GalleryPageDescriptor], resolution: ImageResolution = .preview) async {
        let api = self.api
        let pipeline = self.imagePipeline
        let currentSite = site
        await withTaskGroup(of: Void.self) { group in
            for descriptor in descriptors {
                group.addTask {
                    guard Task.isCancelled == false else { return }
                    do {
                        let image = try await api.pageImage(for: descriptor, site: currentSite)
                        let url = resolution == .original ? (image.originImageURL ?? image.imageURL) : image.imageURL
                        _ = try await pipeline.data(for: url) {
                            try await api.imageData(for: image, resolution: resolution)
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }
                }
            }
        }
    }

    func toggleFavorite(for key: GalleryKey) async {
        await toggleFavorite(for: key, remoteDetail: nil)
    }

    func toggleFavorite(for key: GalleryKey, remoteDetail: GalleryDetail?) async {
        do {
            if let summary = galleries.first(where: { $0.key == key }) {
                try await persistence.upsert([summary])
            }
            let current = try await persistence.isFavorite(for: key) ?? false
            if remoteDetail != nil, isGuestMode == false {
                try await api.setFavorite(
                    for: key,
                    site: site,
                    category: current ? nil : 0,
                    note: nil
                )
            }
            try await persistence.setFavorite(for: key, isFavorite: !current)
            await loadLibrary(mode: .favorites)
        }
        catch { errorMessage = error.localizedDescription }
    }

    func rate(_ detail: GalleryDetail, value: Double) async {
        guard let apiUID = detail.apiUID, let apiKey = detail.apiKey else {
            errorMessage = EHError.authenticationRequired.localizedDescription
            return
        }
        do {
            _ = try await api.rateGallery(for: detail.summary.key, site: site, rating: value, apiUID: apiUID, apiKey: apiKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitComment(for detail: GalleryDetail, body: String) async -> [GalleryComment]? {
        do {
            return try await api.submitComment(for: detail.summary.key, site: site, body: body, editing: nil)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func torrents(for key: GalleryKey) async -> [TorrentDescriptor] {
        do {
            return try await api.torrents(for: key, site: site)
        } catch is CancellationError {
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func archiveOptions(for key: GalleryKey) async -> [ArchiveOption] {
        do {
            return try await api.archiveOptions(for: key, site: site)
        } catch is CancellationError {
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func archiveDownloadURL(for key: GalleryKey, resolution: String) async -> URL? {
        do {
            return try await api.archiveDownloadURL(for: key, site: site, resolution: resolution)
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func openLocalArchive(from url: URL) async -> LocalArchiveDocument? {
        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try LocalArchiveReader.open(url)
            }.value
            localArchive = document
            return document
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func data(for entry: LocalArchiveEntry, in document: LocalArchiveDocument) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try LocalArchiveReader.readData(for: entry, in: document)
        }.value
    }

    func closeLocalArchive() {
        localArchive = nil
    }

    func updateProgress(for key: GalleryKey, page: Int) async {
        do { try await persistence.updateReadingProgress(for: key, page: page) }
        catch { errorMessage = error.localizedDescription }
    }

    func readingPage(for key: GalleryKey) async -> Int? {
        try? await persistence.readingPage(for: key)
    }

    func favoriteState(for key: GalleryKey) async -> Bool {
        (try? await persistence.isFavorite(for: key)) ?? false
    }

    func loadLibrary(mode: LibraryView.Mode) async {
        do {
            switch mode {
            case .history:
                historyGalleries = try await persistence.recent()
            case .favorites:
                favoriteGalleries = try await persistence.favorites()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadFilterRules() async {
        filterRules = (try? await persistence.filterRules()) ?? []
    }

    func loadTagTranslations() async {
        tagTranslations = (try? await persistence.tagTranslations(locale: Locale.current.identifier)) ?? [:]
    }

    func localizedTag(_ tag: String) -> String {
        tagTranslations[tag] ?? tag
    }

    func loadQuickSearches() async {
        quickSearches = (try? await persistence.quickSearches()) ?? []
    }

    func setFilterRule(pattern: String, isEnabled: Bool) async {
        do {
            try await persistence.setFilterRule(pattern: pattern, isEnabled: isEnabled)
            await loadFilterRules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setDownloadLabel(_ label: String?, for key: GalleryKey) async {
        let normalized = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, normalized.isEmpty == false {
            try? await persistence.saveDownloadLabel(normalized)
        }
        await downloads.setLabel(normalized, for: key)
    }

    func enqueue(_ detail: GalleryDetail) async {
        do {
            let client = self.api
            let currentSite = site
            let resolvedPages = try await withThrowingTaskGroup(of: GalleryPageDescriptor.self, returning: [GalleryPageDescriptor].self) { group in
                for descriptor in detail.pages {
                    group.addTask {
                        let image = try await client.pageImage(for: descriptor, site: currentSite)
                        return GalleryPageDescriptor(
                            galleryKey: descriptor.galleryKey,
                            index: descriptor.index,
                            pageURL: image.imageURL,
                            previewURL: descriptor.previewURL
                        )
                    }
                }
                var pages: [GalleryPageDescriptor] = []
                for try await page in group { pages.append(page) }
                return pages.sorted { $0.index < $1.index }
            }
            await downloads.enqueue(key: detail.summary.key, title: detail.summary.title, pages: resolvedPages)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreDownloads() async {
        guard let persisted = try? await persistence.downloadJobs() else { return }
        var jobs: [DownloadJob] = []
        for item in persisted {
            var job = DownloadJob(key: item.key, title: item.title, pages: item.pages)
            let expectedPageIndexes = Set(item.pages.map(\.index))
            let readablePageIndexes = await downloadFiles.readablePageIndexes(
                for: item.key,
                pageIndexes: Array(expectedPageIndexes)
            )
            job.completedPageIndexes = readablePageIndexes
            job.state = DownloadState(rawValue: item.stateRaw) ?? .queued
            job.label = item.label
            job.errorMessage = item.errorMessage
            if expectedPageIndexes.isEmpty == false,
               readablePageIndexes == expectedPageIndexes,
               job.state != .cancelled {
                job.state = .completed
                job.errorMessage = nil
            } else if job.state == .completed {
                job.state = .paused
                job.errorMessage = "部分下载文件缺失或无效，请继续下载"
            } else if item.inFlightPageIndexes.isEmpty == false {
                job.state = .paused
                job.errorMessage = "后台下载任务恢复中"
            }
            jobs.append(job)
        }
        await downloads.restore(jobs)
    }

    func saveCookie(_ cookieHeader: String) async -> Bool {
        do {
            try await sessionVault.saveCookieHeader(cookieHeader)
            isGuestMode = false
            persistSettings()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func login(username: String, password: String) async -> Bool {
        guard isPasswordLoginInProgress == false else { return false }
        isPasswordLoginInProgress = true
        defer { isPasswordLoginInProgress = false }
        do {
            _ = try await api.login(username: username, password: password)
            isGuestMode = false
            persistSettings()
            errorMessage = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearSession() async {
        do {
            try await sessionVault.clear()
            isGuestMode = true
            persistSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSessionStatus() async {
        isGuestMode = (try? await sessionVault.loadCookieHeader()) == nil
    }

    func setAppLockEnabled(_ enabled: Bool) async {
        if enabled {
            guard await AppLockService.authenticate() else {
                errorMessage = "无法启用应用锁：设备未完成认证"
                return
            }
            appLockEnabled = true
            isLocked = false
        } else {
            appLockEnabled = false
            isLocked = false
        }
        persistSettings()
    }

    func lockForBackground() {
        if appLockEnabled { isLocked = true }
    }

    func unlockIfNeeded() async {
        guard appLockEnabled, isLocked else { return }
        if await AppLockService.authenticate() {
            isLocked = false
        }
    }

    func handleIncomingURL(_ url: URL) {
        if url.scheme == "ehviewer",
           let sharedURLString = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
           let sharedURL = URL(string: sharedURLString) {
            handleIncomingURL(sharedURL)
            return
        }
        let components = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
        guard let gIndex = components.firstIndex(of: "g"),
              components.count > gIndex + 2,
              let gid = Int64(components[gIndex + 1]),
              components[gIndex + 2].isEmpty == false else { return }
        selectedRoute = .gallery(GalleryKey(gid: gid, token: components[gIndex + 2]))
    }

    func persistSettings() {
        defaults.set(site.rawValue, forKey: "site")
        defaults.set(appLockEnabled, forKey: "appLockEnabled")
    }

    private func imageURL(for image: GalleryPageImage, resolution: ImageResolution) -> URL {
        resolution == .original ? (image.originImageURL ?? image.imageURL) : image.imageURL
    }

    private func matchesFilter(_ gallery: GallerySummary) -> Bool {
        let haystack = ([gallery.title, gallery.secondaryTitle ?? ""] + gallery.tags).joined(separator: " ").lowercased()
        return filterRules.contains { $0.isEnabled && haystack.localizedCaseInsensitiveContains($0.pattern) } == false
    }

    private func appendUniqueGalleries(_ newGalleries: [GallerySummary]) {
        var existingKeys = Set(galleries.map(\.key))
        galleries.append(contentsOf: newGalleries.filter {
            matchesFilter($0) && existingKeys.insert($0.key).inserted
        })
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private func parseDownloadTaskDescription(_ description: String) -> (GalleryKey, Int)? {
    let pieces = description.split(separator: "|", omittingEmptySubsequences: false)
    guard pieces.count == 3,
          let gid = Int64(pieces[0]),
          let pageIndex = Int(pieces[2]),
          pieces[1].isEmpty == false else { return nil }
    return (GalleryKey(gid: gid, token: String(pieces[1])), pageIndex)
}
