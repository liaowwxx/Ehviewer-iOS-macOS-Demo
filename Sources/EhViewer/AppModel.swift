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
    let tagSuggestionProvider: TagSuggestionProvider

    var site: SiteMode
    var readingSettings: ReadingSettings
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
    var isLoading = false
    var searchText = ""
    var submittedSearchText = ""
    var isGuestMode = true
    var isPasswordLoginInProgress = false
    var errorMessage: String?
    var isRestoringDownloads = false
    var downloadRestoreStatus = ""
    private(set) var nextPageURL: URL?
    var hasMorePage: Bool { nextPageURL != nil }
    private var activeQuery = GalleryListQuery()
    private var activeListRequestID = UUID()

    init(
        container: ModelContainer,
        api: (any EHAPI)? = nil,
        sessionVault: SessionVault = SessionVault(),
        defaults: UserDefaults = .standard,
        downloadFiles: DownloadFileStore? = nil,
        tagSuggestionProvider: TagSuggestionProvider = TagSuggestionProvider()
    ) {
        self.defaults = defaults
        site = .eHentai
        readingSettings = ReadingSettings.load(from: defaults)
        defaults.set(SiteMode.eHentai.rawValue, forKey: "site")
        let arguments = ProcessInfo.processInfo.arguments
        let forceGuestModeForUITest = arguments.contains("-UITestUseGuestMode")
        forceGuestMode = forceGuestModeForUITest
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
        downloads = DownloadCoordinator(
            pageLoader: { descriptor in
                var request = URLRequest(url: descriptor.pageURL)
                request.httpMethod = "GET"
                request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
                if let cookieHeader = try? await sessionVault.loadAuthenticatedCookieHeader() {
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
        Task { [tagSuggestionProvider] in
            await tagSuggestionProvider.preload()
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
        searchText = searchSyntax
        submittedSearchText = searchSyntax
        selectedRoute = .browse
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

    func savePage(_ descriptor: GalleryPageDescriptor, resolution: ImageResolution = .preview) async throws {
        let data: Data
        if await downloadFiles.contains(descriptor.galleryKey, pageIndex: descriptor.index) {
            data = try await downloadFiles.data(for: descriptor.galleryKey, pageIndex: descriptor.index)
        } else {
            let image = try await pageImage(for: descriptor)
            data = try await imageData(for: image, resolution: resolution)
        }
        #if os(iOS)
        try await PhotoLibrarySaver.save(data)
        #else
        _ = try await downloadFiles.write(data, for: descriptor.galleryKey, pageIndex: descriptor.index)
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
        do {
            let resolvedPages = try await resolvedDownloadPages(detail.pages)
            await downloads.enqueue(key: detail.summary.key, title: detail.summary.preferredTitle, pages: resolvedPages)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreDownloads(from archiveURL: URL) async -> String {
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

            let existingGIDs = Set(await downloads.snapshot().map { $0.key.gid })
            var seenGIDs = existingGIDs
            var candidateByKey: [GalleryKey: LegacyDownloadCandidate] = [:]
            var detailByKey: [GalleryKey: GalleryDetail] = [:]
            var preparedKeys: [GalleryKey] = []
            var skippedCount = 0
            var failedGalleryCount = 0

            for (offset, candidate) in inspection.candidates.enumerated() {
                try Task.checkCancellation()
                downloadRestoreStatus = "正在获取画廊信息 \(offset + 1)/\(inspection.candidates.count)…"
                guard seenGIDs.insert(candidate.key.gid).inserted else {
                    skippedCount += 1
                    continue
                }
                do {
                    let detail = try await api.detail(for: candidate.key, site: restoreSite)
                    try? await persistence.upsert([detail.summary])
                    candidateByKey[candidate.key] = candidate
                    detailByKey[candidate.key] = detail
                    preparedKeys.append(candidate.key)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failedGalleryCount += 1
                }
            }

            guard preparedKeys.isEmpty == false else {
                return "未能恢复下载项。已跳过 \(skippedCount) 项，\(failedGalleryCount) 项无法获取画廊信息。"
            }

            let selections = preparedKeys.flatMap { key -> [LegacyDownloadPageSelection] in
                guard let candidate = candidateByKey[key] else { return [] }
                return candidate.images.compactMap { image in
                    guard (0..<candidate.declaredPageCount).contains(image.pageIndex) else { return nil }
                    return LegacyDownloadPageSelection(
                        archivePath: image.archivePath,
                        key: key,
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

            var importedIndexes: [GalleryKey: Set<Int>] = [:]
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

            var restoredCount = 0
            for (offset, key) in preparedKeys.enumerated() {
                try Task.checkCancellation()
                guard let detail = detailByKey[key], let candidate = candidateByKey[key] else { continue }
                if await downloads.snapshot().contains(where: { $0.key.gid == key.gid }) {
                    skippedCount += 1
                    continue
                }

                let imported = importedIndexes[key] ?? []
                let legacyPages = legacyPageDescriptors(candidate: candidate, detail: detail, site: restoreSite)
                let expected = Set(0..<candidate.declaredPageCount)
                let isComplete = expected.isEmpty == false && imported == expected
                var pages = legacyPages.pages
                var state: DownloadState = isComplete ? .completed : .paused
                var itemError: String?

                if isComplete == false {
                    downloadRestoreStatus = "正在准备缺失页面 \(offset + 1)/\(preparedKeys.count)…"
                    let missingIndexes = expected.subtracting(imported)
                    if missingIndexes.isSubset(of: legacyPages.resumableIndexes) == false {
                        state = .failed
                        itemError = "已恢复 \(imported.count)/\(expected.count) 页，但部分缺页没有可用的页面 token"
                    } else {
                        do {
                            let missingPages = pages.filter { missingIndexes.contains($0.index) }
                            let resolvedMissingPages = try await resolvedDownloadPages(missingPages, site: restoreSite)
                            let resolvedByIndex = Dictionary(uniqueKeysWithValues: resolvedMissingPages.map { ($0.index, $0) })
                            pages = pages.map { resolvedByIndex[$0.index] ?? $0 }
                            itemError = "已恢复 \(imported.count)/\(expected.count) 页，可继续下载缺失页面"
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            state = .failed
                            itemError = "已恢复 \(imported.count)/\(expected.count) 页，但续传地址准备失败：\(error.localizedDescription)"
                        }
                    }
                }

                var job = DownloadJob(key: key, title: detail.summary.preferredTitle, pages: pages)
                job.completedPageIndexes = imported
                job.state = state
                job.errorMessage = itemError
                await downloads.restore([job])
                restoredCount += 1
            }

            var parts = ["已恢复 \(restoredCount) 项"]
            if skippedCount > 0 { parts.append("跳过 \(skippedCount) 项") }
            if failedGalleryCount > 0 { parts.append("画廊信息失败 \(failedGalleryCount) 项") }
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
        detail: GalleryDetail,
        site: SiteMode
    ) -> (pages: [GalleryPageDescriptor], resumableIndexes: Set<Int>) {
        let detailByIndex = Dictionary(uniqueKeysWithValues: detail.pages.map { ($0.index, $0) })
        var resumableIndexes = Set<Int>()
        let pages = (0..<candidate.declaredPageCount).map { index in
            if let descriptor = detailByIndex[index] {
                resumableIndexes.insert(index)
                return descriptor
            }
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

    private func restoreDownloads() async {
        guard let persisted = try? await persistence.downloadJobs() else { return }
        var jobs: [DownloadJob] = []
        let restoreSite = site
        for item in persisted {
            let summary = try? await persistence.gallerySummary(for: item.key)
            let title = summary?.preferredTitle ?? item.title
            var pages = item.pages
            if let expectedPageCount = summary?.pageCount,
               expectedPageCount > pages.count,
               item.stateRaw != DownloadState.cancelled.rawValue,
               let detail = try? await api.detail(for: item.key, site: restoreSite) {
                let existingIndexes = Set(pages.map(\.index))
                let missingDescriptors = detail.pages.filter { existingIndexes.contains($0.index) == false }
                if missingDescriptors.isEmpty == false,
                   let resolvedPages = try? await resolvedDownloadPages(missingDescriptors, site: restoreSite) {
                    pages = (pages + resolvedPages).sorted { $0.index < $1.index }
                }
            }
            var job = DownloadJob(key: item.key, title: title, pages: pages)
            let expectedPageIndexes = Set(pages.map(\.index))
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
        site = .eHentai
        persistSettings()
    }

    private func completeAuthentication() {
        isGuestMode = false
        site = .eHentai
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
        let components = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
        guard let gIndex = components.firstIndex(of: "g"),
              components.count > gIndex + 2,
              let gid = Int64(components[gIndex + 1]),
              components[gIndex + 2].isEmpty == false else { return }
        selectedRoute = .gallery(GalleryKey(gid: gid, token: components[gIndex + 2]))
    }

    func persistSettings() {
        defaults.set(site.rawValue, forKey: "site")
    }

    func persistReadingSettings() {
        readingSettings.save(to: defaults)
    }

    func exportMigrationData() async -> Data? {
        do {
            var snapshot = try await persistence.exportSnapshot()
            snapshot.siteRaw = site.rawValue
            snapshot.readingSettingsData = try JSONEncoder().encode(readingSettings)
            return try JSONEncoder().encode(snapshot)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func importMigrationData(_ data: Data) async -> Bool {
        do {
            let snapshot = try JSONDecoder().decode(MigrationSnapshot.self, from: data)
            try await persistence.importSnapshot(snapshot)
            if let rawSite = snapshot.siteRaw, let importedSite = SiteMode(rawValue: rawSite), isGuestMode == false || importedSite == .eHentai {
                site = importedSite
                persistSettings()
            }
            if let settingsData = snapshot.readingSettingsData,
               let importedSettings = try? JSONDecoder().decode(ReadingSettings.self, from: settingsData) {
                readingSettings = importedSettings
                persistReadingSettings()
            }
            await loadFilterRules()
            await loadTagTranslations()
            await loadQuickSearches()
            await restoreDownloads()
            historyGalleries = (try? await persistence.recent()) ?? historyGalleries
            favoriteGalleries = (try? await persistence.favorites()) ?? favoriteGalleries
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
