import Foundation
import Observation
import SwiftData
import EHDomain
import EHNetworking
import EHPersistence
import EHDownloads

struct MigrationProgress: Sendable, Hashable {
    let status: String
    let completed: Int
    let total: Int
    let fraction: Double?

    init(status: String, completed: Int = 0, total: Int = 0, fraction: Double? = nil) {
        self.status = status
        self.completed = completed
        self.total = total
        self.fraction = fraction ?? (total > 0 ? min(1, max(0, Double(completed) / Double(total))) : nil)
    }
}

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
    let tagSuggestionProvider: TagSuggestionProvider

    var site: SiteMode
    var readingSettings: ReadingSettings
    var downloadSortOrder: DownloadSortOrder
    var downloadStatusFilter: DownloadStatusFilter
    var galleries: [GallerySummary] = []
    var historyGalleries: [GallerySummary] = []
    var favoriteGalleries: [GallerySummary] = []
    var filterRules: [FilterRuleSnapshot] = []
    var tagTranslations: [String: String] = [:]
    var quickSearches: [String] = []
    var searchHistorySuggestions: [String] = []
    var tagSearchSuggestions: [SearchTagSuggestion] = []
    var localArchive: LocalArchiveDocument?
    var selectedRoute: AppRoute? = .browse
    var browseRefreshToken = 0
    var isLoading = false
    var searchText = ""
    var submittedSearchText = ""
    var pendingSearchQuery: String?
    var isGuestMode = true
    var isPasswordLoginInProgress = false
    var errorMessage: String?
    var isRestoringDownloads = false
    var downloadRestoreStatus = ""
    private(set) var isMigrating = false
    private(set) var migrationProgress: MigrationProgress?
    private(set) var isLoadingDownloads = true
    private(set) var nextPageURL: URL?
    var hasMorePage: Bool { nextPageURL != nil }
    private var activeQuery = GalleryListQuery()
    private var activeListRequestID = UUID()
    @ObservationIgnored private var searchPageModels: [String: BrowsePageModel] = [:]

    init(
        container: ModelContainer,
        api: (any EHAPI)? = nil,
        sessionVault: SessionVault = SessionVault(),
        defaults: UserDefaults = .standard,
        downloadFiles: DownloadFileStore? = nil,
        tagSuggestionProvider: TagSuggestionProvider = TagSuggestionProvider()
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        let forceGuestModeForUITest = arguments.contains("-UITestUseGuestMode")
        self.defaults = defaults
        forceGuestMode = forceGuestModeForUITest
        let savedSite = SiteMode(rawValue: defaults.string(forKey: "site") ?? "") ?? .eHentai
        let selectedSite = forceGuestModeForUITest ? SiteMode.eHentai : savedSite
        site = selectedSite
        readingSettings = ReadingSettings.load(from: defaults)
        downloadSortOrder = DownloadSortOrder(
            rawValue: defaults.string(forKey: "downloadSortOrder") ?? ""
        ) ?? .titleAscending
        downloadStatusFilter = DownloadStatusFilter(
            rawValue: defaults.string(forKey: "downloadStatusFilter") ?? ""
        ) ?? .all
        if forceGuestModeForUITest {
            isGuestMode = true
        }
        defaults.removeObject(forKey: "appLockEnabled")
        self.sessionVault = sessionVault
        self.tagSuggestionProvider = tagSuggestionProvider
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
        let downloadClient = client
        let downloadSite = selectedSite
        downloads = DownloadCoordinator(
            pageLoader: { descriptor in
                var pageDescriptor = descriptor
                var lastValidationError: EHError?

                for attempt in 0..<5 {
                    try Task.checkCancellation()
                    let pageImage: GalleryPageImage
                    if pageDescriptor.requiresPageResolution {
                        pageImage = try await downloadClient.pageImage(for: pageDescriptor, site: downloadSite)
                    } else {
                        pageImage = GalleryPageImage(
                            galleryKey: pageDescriptor.galleryKey,
                            index: pageDescriptor.index,
                            imageURL: pageDescriptor.pageURL
                        )
                    }

                    var request = URLRequest(url: pageImage.imageURL)
                    request.httpMethod = "GET"
                    request.setValue("image/avif,image/webp,image/apng,video/mp4,video/*,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                    request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
                    request.setValue(pageDescriptor.pageURL.absoluteString, forHTTPHeaderField: "Referer")
                    if let cookieHeader = try? await sessionVault.loadAuthenticatedCookieHeader() {
                        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                    }

                    let data = try await backgroundSession.data(
                        for: request,
                        taskDescription: "\(descriptor.galleryKey.gid)|\(descriptor.galleryKey.token)|\(descriptor.index)"
                    )
                    do {
                        try DownloadMediaValidator.validate(data)
                        return data
                    } catch let error as EHError {
                        lastValidationError = error
                        guard attempt < 4 else { throw error }
                        if descriptor.requiresPageResolution,
                           let skipHathKey = pageImage.skipHathKey {
                            pageDescriptor = Self.pageDescriptor(descriptor, skippingHathNodeWith: skipHathKey)
                        } else {
                            pageDescriptor = descriptor
                        }
                    }
                }
                throw lastValidationError ?? EHError.parsingFailed("下载结果不是有效图片或视频")
            },
            fileStore: fileStore,
            persistence: { job in
                try? await store.upsertDownload(
                    key: job.key,
                    title: job.title,
                    japaneseTitle: job.japaneseTitle,
                    pages: job.pages,
                    completedPageIndexes: job.completedPageIndexes,
                    stateRaw: job.state.rawValue,
                    errorMessage: job.errorMessage,
                    label: job.label
                )
            },
            removal: { key in
                try await store.deleteDownload(for: key)
            }
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.forceGuestMode == false {
                await self.refreshSessionStatus()
            }
            await self.loadFilterRules()
            await self.loadTagTranslations()
        }
        Task { @MainActor [weak self] in
            await self?.restoreDownloads()
        }
        Task { [tagSuggestionProvider, weak self] in
            await tagSuggestionProvider.preload()
            await self?.importTagTranslationsIfNeeded()
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
            let items = await enrichedForTagFiltering(result.items)
            galleries = items.filter(matchesFilter)
            loadedNextPageURL = result.cursor?.nextPageURL
            didLoadPage = true
            try await persistence.upsert(items)
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

    var hasActiveTagFilterRules: Bool {
        filterRules.contains { rule in
            rule.isEnabled && (rule.mode == .tag || rule.mode == .tagNamespace)
        }
    }

    /// Mirrors the reference `EhEngine.fillGalleryList`: list pages only carry
    /// a few summary tags, so when tag or tag-namespace filters are enabled
    /// the full tag list is fetched through the gdata API before matching.
    func enrichedForTagFiltering(_ items: [GallerySummary]) async -> [GallerySummary] {
        guard hasActiveTagFilterRules, items.isEmpty == false else { return items }
        guard let fetched = try? await api.gallerySummaries(for: items.map(\.key), site: site),
              fetched.isEmpty == false else { return items }
        let tagsByKey = Dictionary(uniqueKeysWithValues: fetched.map { ($0.key, $0.tags) })
        return items.map { item in
            guard let tags = tagsByKey[item.key], tags.isEmpty == false else { return item }
            var enriched = item
            enriched.tags = tags
            return enriched
        }
    }

    func loadBrowseQuery(_ query: GalleryListQuery) async {
        guard galleries.isEmpty || isActiveList(query) == false else { return }
        await load(query: query)
    }

    private func isActiveList(_ query: GalleryListQuery) -> Bool {
        var requestedQuery = query
        requestedQuery.page = 0
        var currentQuery = activeQuery
        currentQuery.page = 0
        return requestedQuery == currentQuery
    }

    func searchTag(_ tag: String) {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTag.isEmpty == false else { return }
        let searchSyntax = SearchQueryComposer.searchSyntax(for: normalizedTag)
        pendingSearchQuery = searchSyntax
        selectedRoute = .browse
    }

    func searchPageModel(for query: String) -> BrowsePageModel {
        let normalized = SearchQueryComposer.normalized(query)
        if let cached = searchPageModels[normalized] { return cached }
        let pageModel = BrowsePageModel(model: self, kind: .search, initialSearchText: normalized)
        searchPageModels[normalized] = pageModel
        return pageModel
    }

    func updateSearchSuggestions(for query: String) async {
        let normalizedQuery = SearchQueryComposer.normalized(query)
        searchHistorySuggestions = []
        tagSearchSuggestions = []
        do {
            if normalizedQuery.isEmpty == false {
                try await Task.sleep(for: .milliseconds(120))
            }
            async let history = persistence.quickSearchSuggestions(prefix: normalizedQuery)
            let fragment = SearchQueryComposer.suggestionFragment(in: normalizedQuery)
            async let tags = tagSuggestionProvider.suggestions(for: fragment)
            let (loadedHistory, loadedTags) = try await (history, tags)
            try Task.checkCancellation()
            guard SearchQueryComposer.normalized(searchText) == normalizedQuery else { return }
            searchHistorySuggestions = loadedHistory
            tagSearchSuggestions = loadedTags
        } catch is CancellationError {
            return
        } catch {
            searchHistorySuggestions = (try? await persistence.quickSearchSuggestions(prefix: normalizedQuery)) ?? []
            tagSearchSuggestions = []
        }
    }

    func completeTagSuggestion(_ tag: String) {
        searchText = SearchQueryComposer.completing(tag: tag, in: searchText)
    }

    func selectSearchHistory(_ query: String) {
        let normalized = SearchQueryComposer.normalized(query)
        searchText = normalized
    }

    func deleteSearchHistory(_ query: String) async {
        do {
            try await persistence.deleteQuickSearch(query)
            await loadQuickSearches()
            await updateSearchSuggestions(for: searchText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitSearch() {
        let normalized = SearchQueryComposer.normalized(searchText)
        searchText = normalized
        submittedSearchText = normalized
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

    func retryLastListRequest() async {
        await load(query: activeQuery)
    }

    func requestBrowseRefresh() {
        browseRefreshToken &+= 1
    }

    func detail(for key: GalleryKey) async throws -> GalleryDetail {
        let detail = try await api.detail(for: key, site: site)
        try await persistence.upsert([detail.summary])
        return detail
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
            if descriptor.requiresPageResolution {
                let image = try await pageImage(for: descriptor)
                return try await imageData(for: image, resolution: resolution)
            }
            return try await imageData(for: directImage, resolution: resolution)
        }
    }

    func downloadedPageDataIfAvailable(for descriptor: GalleryPageDescriptor) async -> Data? {
        guard await downloadFiles.contains(descriptor.galleryKey, pageIndex: descriptor.index) else {
            return nil
        }
        return try? await downloadFiles.data(for: descriptor.galleryKey, pageIndex: descriptor.index)
    }

    func savePage(_ descriptor: GalleryPageDescriptor, resolution: ImageResolution = .preview) async throws {
        let data: Data
        if await downloadFiles.contains(descriptor.galleryKey, pageIndex: descriptor.index) {
            data = try await downloadFiles.data(for: descriptor.galleryKey, pageIndex: descriptor.index)
        } else {
            let image = try await pageImage(for: descriptor)
            data = try await imageData(for: image, resolution: resolution)
        }
        #if os(iOS)
        guard let mediaKind = DownloadMediaValidator.kind(of: data) else {
            throw EHError.parsingFailed("媒体数据无效")
        }
        try await PhotoLibrarySaver.save(data, kind: mediaKind)
        #else
        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw EHError.storageFailed("找不到可写入的下载目录")
        }
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let fileExtension = DownloadMediaValidator.kind(of: data) == .video
            ? "mp4"
            : (descriptor.pageURL.pathExtension.isEmpty ? "img" : descriptor.pageURL.pathExtension)
        let fileName = "ehviewer-\(descriptor.galleryKey.gid)-\(descriptor.index + 1).\(fileExtension)"
        try data.write(to: downloadsDirectory.appendingPathComponent(fileName), options: .atomic)
        #endif
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
            if let remoteDetail {
                try await persistence.upsert([remoteDetail.summary])
            } else if let summary = galleries.first(where: { $0.key == key }) {
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
        var loaded = (try? await persistence.tagTranslations(locale: Self.tagTranslationLocale)) ?? [:]
        if Locale.current.identifier != Self.tagTranslationLocale,
           let local = try? await persistence.tagTranslations(locale: Locale.current.identifier) {
            loaded.merge(local) { _, new in new }
        }
        tagTranslations = loaded
    }

    static let tagTranslationLocale = "zh-rCN"

    /// Imports the reference tag database once so detail pages can show the
    /// same Chinese tag translations as the original client.
    func importTagTranslationsIfNeeded() async {
        guard defaults.string(forKey: "tagTranslationImportLocale") != Self.tagTranslationLocale else { return }
        guard let entries = try? await tagSuggestionProvider.allEntries() else { return }
        let pairs = entries.compactMap { entry -> (tag: String, localizedText: String)? in
            guard let text = entry.localizedText, text.isEmpty == false else { return nil }
            return (entry.rawKey ?? entry.english, text)
        }
        guard pairs.isEmpty == false else { return }
        try? await persistence.saveTagTranslations(pairs, locale: Self.tagTranslationLocale)
        defaults.set(Self.tagTranslationLocale, forKey: "tagTranslationImportLocale")
        await loadTagTranslations()
    }

    func localizedTag(_ tag: String) -> String {
        tagTranslations[tag] ?? tag
    }

    /// Detail-page tag display, mirroring the reference client: only the tag
    /// value is shown (never the `misc:`/`artist:` prefix), translated when
    /// the reference database has an entry for it and translations are on.
    func displayTag(_ tag: String) -> String {
        let value: String
        if let separator = tag.firstIndex(of: ":") {
            value = String(tag[tag.index(after: separator)...])
        } else {
            value = tag
        }
        guard readingSettings.showTagTranslations else { return value }
        if let translated = tagTranslations[tag] { return translated }
        let databaseKey = SearchQueryComposer.databaseTagKey(for: tag)
        if databaseKey != tag, let translated = tagTranslations[databaseKey] { return translated }
        if value != tag, let translated = tagTranslations[value] { return translated }
        return value
    }

    func loadQuickSearches() async {
        quickSearches = (try? await persistence.quickSearches()) ?? []
    }

    func setFilterRule(pattern: String, isEnabled: Bool, mode: GalleryFilterMode = .title) async {
        do {
            try await persistence.setFilterRule(pattern: pattern, isEnabled: isEnabled, mode: mode)
            await loadFilterRules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Tag candidates for the filter-rule keyword field, backed by the same
    /// database as the browse search suggestions.
    func filterTagSuggestions(for keyword: String, limit: Int = 10) async -> [SearchTagSuggestion] {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return [] }
        return (try? await tagSuggestionProvider.suggestions(for: normalized, limit: limit)) ?? []
    }

    func deleteFilterRule(pattern: String, mode: GalleryFilterMode = .title) async {
        do {
            try await persistence.deleteFilterRule(pattern: pattern, mode: mode)
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

    func resetAllDownloadReadingProgress() async {
        do {
            let keys = await downloads.snapshot().map(\.key)
            try await persistence.resetReadingProgress(for: keys)
            historyGalleries = try await persistence.recent()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enqueue(_ detail: GalleryDetail) async {
        await downloads.enqueue(
            key: detail.summary.key,
            title: detail.summary.displayTitle(showJapaneseTitle: readingSettings.showJapaneseTitle),
            japaneseTitle: detail.summary.japaneseTitle,
            pages: detail.pages
        )
    }

    func downloadJob(for key: GalleryKey) async -> DownloadJob? {
        await downloads.job(for: key)
    }

    func restoreDownloads(
        from archiveURL: URL,
        progress: ((Int, Int) -> Void)? = nil
    ) async -> String {
        guard isRestoringDownloads == false else { return "已有恢复任务正在进行。" }
        isRestoringDownloads = true
        downloadRestoreStatus = "正在检查备份压缩包…"
        let restoreSite = site
        defer {
            isRestoringDownloads = false
            downloadRestoreStatus = ""
        }

        do {
            let inspection = try await LegacyDownloadArchive.inspect(archiveURL)
            guard inspection.candidates.isEmpty == false else {
                return inspection.invalidItemCount > 0
                    ? "没有找到可恢复的下载项；发现 \(inspection.invalidItemCount) 个无效目录。"
                    : "没有在压缩包的 download 目录中找到可恢复的下载项。"
            }

            let existingJobs = Dictionary(uniqueKeysWithValues: await downloads.snapshot().map { ($0.key, $0) })
            var existingLocalIndexes: [GalleryKey: Set<Int>] = [:]
            for candidate in inspection.candidates {
                let pageIndexes = Array(0..<candidate.declaredPageCount)
                existingLocalIndexes[candidate.key] = await downloadFiles.readablePageIndexes(
                    for: candidate.key,
                    pageIndexes: pageIndexes
                )
            }
            let candidates = inspection.candidates
            progress?(0, candidates.count)

            downloadRestoreStatus = "正在获取画廊信息…"
            let summaries = (try? await api.gallerySummaries(
                for: candidates.map(\.key),
                site: restoreSite
            )) ?? []
            if summaries.isEmpty == false {
                try? await persistence.upsert(summaries)
            }
            let summaryByKey = Dictionary(uniqueKeysWithValues: summaries.map { ($0.key, $0) })

            let selections = candidates.flatMap { candidate -> [LegacyDownloadPageSelection] in
                return candidate.images.compactMap { image in
                    guard (0..<candidate.declaredPageCount).contains(image.pageIndex) else { return nil }
                    guard existingLocalIndexes[candidate.key, default: []].contains(image.pageIndex) == false else { return nil }
                    return LegacyDownloadPageSelection(
                        archivePath: image.archivePath,
                        key: candidate.key,
                        pageIndex: image.pageIndex
                    )
                }
            }

            downloadRestoreStatus = "正在解压下载图片…"
            let extraction = try await LegacyDownloadArchive.extractPages(
                from: archiveURL,
                selections: selections
            )
            defer { try? FileManager.default.removeItem(at: extraction.temporaryDirectory) }

            var importedIndexes = existingLocalIndexes
            var failedPageCount = extraction.failedPageCount
            for (offset, page) in extraction.pages.enumerated() {
                try Task.checkCancellation()
                downloadRestoreStatus = "正在导入图片 \(offset + 1)/\(extraction.pages.count)…"
                do {
                    _ = try await downloadFiles.importFile(
                        at: page.fileURL,
                        for: page.key,
                        pageIndex: page.pageIndex
                    )
                    importedIndexes[page.key, default: []].insert(page.pageIndex)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failedPageCount += 1
                }
            }

            var restoredJobs: [DownloadJob] = []
            restoredJobs.reserveCapacity(candidates.count)
            for (offset, candidate) in candidates.enumerated() {
                try Task.checkCancellation()

                let imported = importedIndexes[candidate.key] ?? []
                let legacyPages = legacyPageDescriptors(candidate: candidate, site: restoreSite)
                var pageByIndex = Dictionary(uniqueKeysWithValues: legacyPages.pages.map { ($0.index, $0) })
                if let existing = existingJobs[candidate.key] {
                    for page in existing.pages {
                        if let mergedPage = pageByIndex[page.index], mergedPage.requiresPageResolution {
                            continue
                        }
                        pageByIndex[page.index] = page
                    }
                }
                let pages = pageByIndex.values.sorted { $0.index < $1.index }
                let expected = Set(0..<max(candidate.declaredPageCount, (pages.map(\.index).max() ?? -1) + 1))
                let isComplete = expected.isEmpty == false && imported == expected
                var state: DownloadState = isComplete ? .completed : .paused
                var itemError: String?

                if isComplete == false {
                    downloadRestoreStatus = "正在准备缺失页面 \(offset + 1)/\(candidates.count)…"
                    let missingIndexes = expected.subtracting(imported)
                    if missingIndexes.isSubset(of: legacyPages.resumableIndexes) == false {
                        state = .failed
                        itemError = "已恢复 \(imported.count)/\(expected.count) 页，但部分缺页没有可用的页面 token"
                    } else {
                        itemError = "已恢复 \(imported.count)/\(expected.count) 页，可继续下载缺失页面"
                    }
                }

                var job = DownloadJob(
                    key: candidate.key,
                    title: existingJobs[candidate.key]?.title
                        ?? summaryByKey[candidate.key]?.displayTitle(showJapaneseTitle: readingSettings.showJapaneseTitle)
                        ?? fallbackDownloadTitle(for: candidate),
                    japaneseTitle: existingJobs[candidate.key]?.japaneseTitle
                        ?? summaryByKey[candidate.key]?.japaneseTitle,
                    pages: pages,
                    label: existingJobs[candidate.key]?.label,
                    addedAt: existingJobs[candidate.key]?.addedAt ?? Date()
                )
                job.completedPageIndexes = imported
                job.state = state
                job.errorMessage = itemError
                restoredJobs.append(job)
                progress?(offset + 1, candidates.count)
            }
            await downloads.mergeRestored(restoredJobs)

            var parts = ["已合并恢复 \(restoredJobs.count) 项"]
            if inspection.invalidItemCount > 0 { parts.append("无效目录 \(inspection.invalidItemCount) 个") }
            if failedPageCount > 0 { parts.append("图片失败 \(failedPageCount) 页") }
            return parts.joined(separator: "，") + "。"
        } catch is CancellationError {
            return "已取消恢复下载项。"
        } catch {
            return "恢复下载项失败：\(error.localizedDescription)"
        }
    }

    private func resolvedDownloadPages(
        _ descriptors: [GalleryPageDescriptor],
        maximumConcurrent: Int = 4,
        site requestedSite: SiteMode? = nil
    ) async throws -> [GalleryPageDescriptor] {
        let client = api
        let currentSite = requestedSite ?? site
        return try await withThrowingTaskGroup(
            of: GalleryPageDescriptor.self,
            returning: [GalleryPageDescriptor].self
        ) { group in
            var iterator = descriptors.makeIterator()
            for _ in 0..<min(maximumConcurrent, descriptors.count) {
                guard let descriptor = iterator.next() else { break }
                group.addTask { try await Self.resolveDownloadPage(descriptor, client: client, site: currentSite) }
            }

            var pages: [GalleryPageDescriptor] = []
            for try await page in group {
                pages.append(page)
                if let descriptor = iterator.next() {
                    group.addTask { try await Self.resolveDownloadPage(descriptor, client: client, site: currentSite) }
                }
            }
            return pages.sorted { $0.index < $1.index }
        }
    }

    private func legacyPageDescriptors(
        candidate: LegacyDownloadCandidate,
        site: SiteMode
    ) -> (pages: [GalleryPageDescriptor], resumableIndexes: Set<Int>) {
        var resumableIndexes = Set<Int>()
        let pages = (0..<candidate.declaredPageCount).map { index in
            if let pageToken = candidate.pageTokens[index],
               let pageURL = URL(string: "https://\(site.host)/s/\(pageToken)/\(candidate.key.gid)-\(index + 1)") {
                resumableIndexes.insert(index)
                return GalleryPageDescriptor(
                    galleryKey: candidate.key,
                    index: index,
                    pageURL: pageURL
                )
            }
            let placeholderURL = URL(
                string: "https://\(site.host)/g/\(candidate.key.gid)/\(candidate.key.token)/#restored-\(index + 1)"
            )!
            return GalleryPageDescriptor(
                galleryKey: candidate.key,
                index: index,
                pageURL: placeholderURL
            )
        }
        return (pages, resumableIndexes)
    }

    private func fallbackDownloadTitle(for candidate: LegacyDownloadCandidate) -> String {
        let directoryName = candidate.directoryPath.split(separator: "/").last.map(String.init) ?? ""
        let prefix = "\(candidate.key.gid)-"
        let title = directoryName.hasPrefix(prefix) ? String(directoryName.dropFirst(prefix.count)) : directoryName
        return title.isEmpty ? "Gallery \(candidate.key.gid)" : title
    }

    nonisolated private static func resolveDownloadPage(
        _ descriptor: GalleryPageDescriptor,
        client: any EHAPI,
        site: SiteMode
    ) async throws -> GalleryPageDescriptor {
        let image = try await client.pageImage(for: descriptor, site: site)
        return GalleryPageDescriptor(
            galleryKey: descriptor.galleryKey,
            index: descriptor.index,
            pageURL: image.imageURL,
            previewURL: descriptor.previewURL
        )
    }

    nonisolated private static func pageDescriptor(
        _ descriptor: GalleryPageDescriptor,
        skippingHathNodeWith key: String
    ) -> GalleryPageDescriptor {
        guard var components = URLComponents(url: descriptor.pageURL, resolvingAgainstBaseURL: false) else {
            return descriptor
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "nl" }
        queryItems.append(URLQueryItem(name: "nl", value: key))
        components.queryItems = queryItems
        guard let pageURL = components.url else { return descriptor }
        return GalleryPageDescriptor(
            galleryKey: descriptor.galleryKey,
            index: descriptor.index,
            pageURL: pageURL,
            previewURL: descriptor.previewURL
        )
    }

    private func restoreDownloads(progress: ((Int, Int) -> Void)? = nil) async {
        isLoadingDownloads = true
        guard let persisted = try? await persistence.downloadJobs() else {
            isLoadingDownloads = false
            return
        }

        let baselines = persisted.map(makePersistedDownloadJob)
        await downloads.loadPersisted(baselines)
        isLoadingDownloads = false
        progress?(0, persisted.count)

        let restoreSite = site
        for (offset, (item, baseline)) in zip(persisted, baselines).enumerated() {
            if Task.isCancelled { return }
            var pages = item.pages
            if item.totalPageCount > pages.count,
               item.stateRaw != DownloadState.cancelled.rawValue,
               let detail = try? await api.detail(for: item.key, site: restoreSite) {
                let existingIndexes = Set(pages.map(\.index))
                let missingDescriptors = detail.pages.filter { existingIndexes.contains($0.index) == false }
                if missingDescriptors.isEmpty == false,
                   let resolvedPages = try? await resolvedDownloadPages(missingDescriptors, site: restoreSite) {
                    pages = (pages + resolvedPages).sorted { $0.index < $1.index }
                }
            }
            var job = DownloadJob(
                key: item.key,
                title: item.title,
                japaneseTitle: item.japaneseTitle,
                pages: pages,
                addedAt: item.createdAt
            )
            let expectedPageIndexes = Set(pages.map(\.index))
            let persistedPageIndexes = item.completedPageIndexes.intersection(expectedPageIndexes)
            let readablePageIndexes = await downloadFiles.readablePageIndexes(
                for: item.key,
                pageIndexes: Array(persistedPageIndexes)
            )
            job.completedPageIndexes = readablePageIndexes
            job.state = normalizedRestoredState(item.stateRaw)
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
            _ = await downloads.reconcilePersisted(job, replacing: baseline)
            progress?(offset + 1, persisted.count)
        }
        await downloads.startRestoredJobs()
    }

    private func makePersistedDownloadJob(_ item: PersistedDownload) -> DownloadJob {
        var job = DownloadJob(
            key: item.key,
            title: item.title,
            japaneseTitle: item.japaneseTitle,
            pages: item.pages,
            addedAt: item.createdAt
        )
        job.completedPageIndexes = item.completedPageIndexes
        job.state = normalizedRestoredState(item.stateRaw)
        job.label = item.label
        job.errorMessage = item.errorMessage
        if item.inFlightPageIndexes.isEmpty == false {
            job.state = .paused
            job.errorMessage = "后台下载任务恢复中"
        }
        return job
    }

    private func normalizedRestoredState(_ rawValue: String) -> DownloadState {
        let state = DownloadState(rawValue: rawValue) ?? .queued
        return state == .running ? .queued : state
    }

    func saveCookie(_ cookieHeader: String) async -> Bool {
        do {
            try await sessionVault.saveCookieHeader(cookieHeader)
            guard try await sessionVault.hasAuthenticatedSession() else {
                throw EHError.invalidCookie
            }
            completeAuthentication()
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
            guard try await sessionVault.hasAuthenticatedSession() else {
                throw EHError.invalidCookie
            }
            completeAuthentication()
            return true
        } catch is CancellationError {
            isGuestMode = true
            return false
        } catch {
            isGuestMode = true
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearSession() async {
        do {
            try await sessionVault.clear()
            isGuestMode = true
            site = .eHentai
            persistSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSessionStatus() async {
        isGuestMode = (try? await sessionVault.hasAuthenticatedSession()) != true
        if isGuestMode { site = .eHentai }
        persistSettings()
    }

    private func completeAuthentication() {
        isGuestMode = false
        selectedRoute = .browse
        errorMessage = nil
        persistSettings()
    }

    func handleIncomingURL(_ url: URL) {
        if url.scheme == "ehviewer",
           let sharedURLString = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
           let sharedURL = URL(string: sharedURLString) {
            handleIncomingURL(sharedURL)
            return
        }
        if let key = Self.galleryKey(from: url) {
            selectedRoute = .gallery(key)
        }
    }

    static func galleryKey(from url: URL) -> GalleryKey? {
        let components = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
        guard let gIndex = components.firstIndex(where: { $0.caseInsensitiveCompare("g") == .orderedSame }),
              components.count > gIndex + 2,
              let gid = Int64(components[gIndex + 1]),
              components[gIndex + 2].isEmpty == false else { return nil }
        return GalleryKey(gid: gid, token: components[gIndex + 2])
    }

    func persistSettings() {
        defaults.set(site.rawValue, forKey: "site")
    }

    func persistReadingSettings() {
        readingSettings.save(to: defaults)
    }

    func persistDownloadPreferences() {
        defaults.set(downloadSortOrder.rawValue, forKey: "downloadSortOrder")
        defaults.set(downloadStatusFilter.rawValue, forKey: "downloadStatusFilter")
    }

    func exportMigrationData() async -> Data? {
        guard beginMigration(status: "正在准备 JSON 数据…") else { return nil }
        defer { finishMigration() }

        do {
            setMigrationProgress(status: "正在读取本地数据…", fraction: 0.1)
            var snapshot = try await persistence.exportSnapshot()
            snapshot.siteRaw = site.rawValue
            setMigrationProgress(status: "正在编码阅读设置…", fraction: 0.35)
            let settings = readingSettings
            snapshot.readingSettingsData = try await Task.detached(priority: .userInitiated) {
                try JSONEncoder().encode(settings)
            }.value
            setMigrationProgress(status: "正在生成 JSON 文件…", fraction: 0.7)
            let data = try await Task.detached(priority: .userInitiated) {
                try JSONEncoder().encode(snapshot)
            }.value
            setMigrationProgress(status: "JSON 数据已准备完成", fraction: 1)
            return data
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func exportDownloadArchive() async -> URL? {
        guard beginMigration(status: "正在准备下载压缩包…") else { return nil }
        defer { finishMigration() }

        do {
            setMigrationProgress(status: "正在读取下载任务…", fraction: 0.05)
            let persisted = try await persistence.downloadJobs()
            let items = persisted.map { item in
                let pageTokens = Dictionary(uniqueKeysWithValues: item.pages.compactMap { page -> (Int, String)? in
                    guard let token = pageToken(from: page.pageURL) else { return nil }
                    return (page.index, token)
                })
                let highestPage = item.pages.map { $0.index + 1 }.max() ?? 0
                return DownloadArchiveExportItem(
                    key: item.key,
                    title: item.title,
                    totalPageCount: max(item.totalPageCount, highestPage),
                    pageTokens: pageTokens
                )
            }
            setMigrationProgress(status: "正在创建下载压缩包…", fraction: 0.1)
            let archiveURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("EhViewer-Downloads-\(UUID().uuidString).zip")
            _ = try await DownloadArchiveExporter.export(
                items: items,
                files: downloadFiles,
                to: archiveURL
            ) { [weak self] progress in
                guard let self else { return }
                let archiveFraction = progress.fraction
                await self.setMigrationProgress(
                    status: progress.currentTitle.map { "正在导出《\($0)》…" } ?? "正在导出下载文件…",
                    completed: progress.completedFiles,
                    total: progress.totalFiles,
                    fraction: 0.1 + archiveFraction * 0.85
                )
            }
            setMigrationProgress(status: "下载压缩包已准备完成", fraction: 1)
            return archiveURL
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func importMigrationData(_ data: Data) async -> Bool {
        guard beginMigration(status: "正在准备导入…") else { return false }
        defer { finishMigration() }

        do {
            setMigrationProgress(status: "正在解析迁移数据…", fraction: 0.1)
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(MigrationSnapshot.self, from: data)
            }.value
            setMigrationProgress(status: "正在合并本地数据…", fraction: 0.35)
            try await persistence.importSnapshot(snapshot)
            if let rawSite = snapshot.siteRaw,
               let importedSite = SiteMode(rawValue: rawSite),
               isGuestMode == false || importedSite == .eHentai {
                site = importedSite
                persistSettings()
            }
            if let settingsData = snapshot.readingSettingsData,
               let importedSettings = try? JSONDecoder().decode(ReadingSettings.self, from: settingsData) {
                readingSettings = importedSettings
                persistReadingSettings()
            }
            setMigrationProgress(status: "正在刷新搜索与过滤数据…", fraction: 0.58)
            await loadFilterRules()
            await loadTagTranslations()
            await loadQuickSearches()
            setMigrationProgress(status: "正在刷新下载内容…", fraction: 0.7)
            await restoreDownloads(progress: { [weak self] completed, total in
                guard let self else { return }
                let fraction = total > 0 ? 0.7 + 0.22 * Double(completed) / Double(total) : 0.92
                self.setMigrationProgress(
                    status: total > 0 ? "正在刷新下载内容 \(completed)/\(total)…" : "正在刷新下载内容…",
                    completed: completed,
                    total: total,
                    fraction: fraction
                )
            })
            historyGalleries = (try? await persistence.recent()) ?? historyGalleries
            favoriteGalleries = (try? await persistence.favorites()) ?? favoriteGalleries
            setMigrationProgress(status: "数据已合并完成", fraction: 1)
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func beginMigration(status: String) -> Bool {
        guard isMigrating == false else { return false }
        isMigrating = true
        migrationProgress = MigrationProgress(status: status, fraction: 0)
        return true
    }

    private func finishMigration() {
        isMigrating = false
        migrationProgress = nil
    }

    private func setMigrationProgress(
        status: String,
        completed: Int = 0,
        total: Int = 0,
        fraction: Double? = nil
    ) {
        migrationProgress = MigrationProgress(
            status: status,
            completed: completed,
            total: total,
            fraction: fraction
        )
    }

    private func pageToken(from url: URL) -> String? {
        let components = url.pathComponents
        guard let index = components.firstIndex(where: { $0.caseInsensitiveCompare("s") == .orderedSame }),
              components.indices.contains(index + 1),
              components[index + 1].isEmpty == false else { return nil }
        return components[index + 1]
    }

    private func imageURL(for image: GalleryPageImage, resolution: ImageResolution) -> URL {
        resolution == .original ? (image.originImageURL ?? image.imageURL) : image.imageURL
    }

    private func matchesFilter(_ gallery: GallerySummary) -> Bool {
        return filterRules.contains { rule in
            rule.isEnabled && GalleryFilterMatcher.isBlocked(gallery, mode: rule.mode, keyword: rule.pattern)
        } == false
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
