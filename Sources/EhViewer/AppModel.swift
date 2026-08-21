/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

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

struct PendingIncomingArchive: Identifiable, Sendable, Equatable {
    let id = UUID()
    let stagedURL: URL
    let fileName: String
}

struct PendingIncomingGallerySync: Identifiable, Sendable, Equatable {
    let id = UUID()
    let stagedURL: URL
    let fileName: String
}

private struct GallerySyncImportResult: Sendable {
    let galleryOutcome: GallerySyncImportOutcome
    let queuedDownloadCount: Int
    let incompleteMetadataCount: Int
}

struct DownloadRestoreOutcome: Sendable {
    let candidateCount: Int
    let importedItemCount: Int
    let mergedItemCount: Int
    let skippedDuplicateItemCount: Int
    let importedPageCount: Int
    let skippedDuplicatePageCount: Int
    let failedPageCount: Int
    let invalidItemCount: Int
    let incompleteMetadataCount: Int
    let message: String

    init(
        candidateCount: Int = 0,
        importedItemCount: Int = 0,
        mergedItemCount: Int = 0,
        skippedDuplicateItemCount: Int = 0,
        importedPageCount: Int = 0,
        skippedDuplicatePageCount: Int = 0,
        failedPageCount: Int = 0,
        invalidItemCount: Int = 0,
        incompleteMetadataCount: Int = 0,
        message: String
    ) {
        self.candidateCount = candidateCount
        self.importedItemCount = importedItemCount
        self.mergedItemCount = mergedItemCount
        self.skippedDuplicateItemCount = skippedDuplicateItemCount
        self.importedPageCount = importedPageCount
        self.skippedDuplicatePageCount = skippedDuplicatePageCount
        self.failedPageCount = failedPageCount
        self.invalidItemCount = invalidItemCount
        self.incompleteMetadataCount = incompleteMetadataCount
        self.message = message
    }
}

private struct StagedIncomingFile: Sendable {
    let directory: URL
    let stagedURL: URL
    let fileName: String
}

private enum IncomingStagingOutcome: Sendable {
    case success(StagedIncomingFile)
    case failure(String)
}

private struct SearchPageKey: Hashable {
    let query: String
    let advancedSearch: GalleryAdvancedSearch?
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
    let galleryCache: GalleryCacheStore
    let tagSuggestionProvider: TagSuggestionProvider

    var site: SiteMode
    var readingSettings: ReadingSettings
    var downloadSortOrder: DownloadSortOrder
    var downloadStatusFilter: DownloadStatusFilter
    var downloadLayoutMode: DownloadsLayoutMode
    private(set) var galleryCacheByteCount: Int64 = 0
    var galleries: [GallerySummary] = []
    var historyGalleries: [GallerySummary] = []
    var favoriteGalleries: [GallerySummary] = []
    var filterRules: [FilterRuleSnapshot] = []
    var tagTranslations: [String: String] = [:]
    var quickSearches: [String] = []
    var searchHistorySuggestions: [String] = []
    var tagSearchSuggestions: [SearchTagSuggestion] = []
    var localArchive: LocalArchiveDocument?
    var selectedRoute: AppRoute? = .local
    var browseRefreshToken = 0
    var isLoading = false
    var searchText = ""
    var submittedSearchText = ""
    var pendingSearchQuery: String?
    var isGuestMode = true
    var isPasswordLoginInProgress = false
    var errorMessage: String?
    var pendingIncomingArchive: PendingIncomingArchive?
    var pendingIncomingGallerySync: PendingIncomingGallerySync?
    var importResultMessage: String?
    var pendingSharedFileURL: URL?
    var isRestoringDownloads = false
    var downloadRestoreStatus = ""
    private(set) var isMigrating = false
    private(set) var migrationProgress: MigrationProgress?
    private(set) var isLoadingDownloads = true
    private(set) var nextPageURL: URL?
    var hasMorePage: Bool { nextPageURL != nil }
    private var activeQuery = GalleryListQuery()
    private var activeListRequestID = UUID()
    @ObservationIgnored private var searchPageModels: [SearchPageKey: BrowsePageModel] = [:]
    @ObservationIgnored private var incomingStagingGeneration = 0
    @ObservationIgnored private var tagTranslationLoadTask: Task<Void, Never>?
    @ObservationIgnored private var tagTranslationImportTask: Task<Void, Never>?

    init(
        container: ModelContainer,
        api: (any EHAPI)? = nil,
        sessionVault: SessionVault = SessionVault(),
        defaults: UserDefaults = .standard,
        downloadFiles: DownloadFileStore? = nil,
        galleryCache: GalleryCacheStore? = nil,
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
        downloadLayoutMode = DownloadsLayoutMode(
            rawValue: defaults.string(forKey: "downloadLayoutMode") ?? ""
        ) ?? .list
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
        self.galleryCache = galleryCache ?? GalleryCacheStore()
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
                throw lastValidationError ?? EHError.parsingFailed(String(localized: "下载结果不是有效图片或视频"))
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
            },
            batchRemoval: { keys in
                try await store.deleteDownloads(for: keys)
            }
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.persistence.migrateLegacyGalleryRecords()
            await self.migrateLegacyGalleryCache()
            await self.refreshGalleryCacheUsage()
            if self.forceGuestMode == false {
                await self.refreshSessionStatus()
            }
            await self.loadFilterRules()
        }
        Task { @MainActor [weak self] in
            await self?.restoreDownloads()
        }
        Task.detached(priority: .utility) {
            Self.sweepStaleTemporaryFiles()
        }
        let tagTranslationLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadTagTranslations()
        }
        self.tagTranslationLoadTask = tagTranslationLoadTask
        self.tagTranslationImportTask = Task { @MainActor [weak self, tagSuggestionProvider] in
            await tagTranslationLoadTask.value
            guard let self else { return }
            await tagSuggestionProvider.preload()
            await self.importTagTranslationsIfNeeded()
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
            let items = await enrichedForBrowse(result.items)
            galleries = items.filter(matchesFilter)
            loadedNextPageURL = result.cursor?.nextPageURL
            didLoadPage = true
            for item in items {
                try await persistence.upsertStableSnapshot(
                    StableGalleryMetadataSnapshot(summary: item, sourceSite: site)
                )
            }
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

    /// List pages only carry a few summary tags. Fetch the full tag list for
    /// every browse page so cards can display the same tags used for filtering.
    func enrichedForBrowse(_ items: [GallerySummary]) async -> [GallerySummary] {
        guard items.isEmpty == false else { return items }
        guard let fetched = try? await api.gallerySummaries(for: items.map(\.key), site: site),
              fetched.isEmpty == false else { return items }
        let summariesByKey = Dictionary(uniqueKeysWithValues: fetched.map { ($0.key, $0) })
        return items.map { item in
            guard let fetchedSummary = summariesByKey[item.key] else { return item }
            var enriched = item
            enriched.tags = fetchedSummary.tags
            enriched.metadataCompleteness = fetchedSummary.metadataCompleteness
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

    func searchPageModel(for query: String, advancedSearch: GalleryAdvancedSearch? = nil) -> BrowsePageModel {
        let normalized = SearchQueryComposer.normalized(query)
        let key = SearchPageKey(query: normalized, advancedSearch: advancedSearch)
        if let cached = searchPageModels[key] { return cached }
        let pageModel = BrowsePageModel(
            model: self,
            kind: .search,
            initialSearchText: normalized,
            initialAdvancedSearch: advancedSearch
        )
        searchPageModels[key] = pageModel
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
        let stable = StableGalleryMetadataSnapshot(detail: detail, sourceSite: site)
        if await downloads.job(for: key) != nil {
            try await persistence.promoteToDownloadedGallery(
                stable: stable,
                dynamic: DownloadedGalleryDynamicSnapshot(detail: detail)
            )
        } else {
            try await persistence.upsertStableSnapshot(stable)
        }
        return detail
    }

    func detailStream(for key: GalleryKey) -> AsyncThrowingStream<GalleryDetail, Error> {
        api.detailStream(for: key, site: site)
    }

    /// Builds the detail page from data already stored for a downloaded
    /// gallery. The detail cache contributes fields that are not part of a
    /// download job, while SwiftData and the job remain the source of truth
    /// for local metadata and page descriptors.
    func localGalleryDetail(for key: GalleryKey, job: DownloadJob? = nil) async -> GalleryDetail? {
        let resolvedJob: DownloadJob?
        if let job {
            resolvedJob = job
        } else {
            resolvedJob = await downloads.job(for: key)
        }
        guard let job = resolvedJob else { return nil }

        let storedSummary = try? await persistence.gallerySummary(for: key)
        let cachedDetail = await cachedDetail(for: key)
        let dynamic = try? await persistence.downloadedDynamicSnapshot(for: key)
        let cachedSummary = cachedDetail?.summary
        let pages = job.pages.isEmpty ? (cachedDetail?.pages ?? []) : job.pages
        let tags: [String] = if job.tags.isEmpty == false {
            job.tags
        } else if let storedSummary, storedSummary.tags.isEmpty == false {
            storedSummary.tags
        } else if let cachedDetail, cachedDetail.tags.isEmpty == false {
            cachedDetail.tags
        } else {
            cachedSummary?.tags ?? []
        }
        let title = job.title.isEmpty
            ? (storedSummary?.title ?? cachedSummary?.title ?? "Gallery \(key.gid)")
            : job.title
        let summary = GallerySummary(
            key: key,
            title: title,
            japaneseTitle: job.japaneseTitle ?? storedSummary?.japaneseTitle ?? cachedSummary?.japaneseTitle,
            thumbnailURL: storedSummary?.thumbnailURL
                ?? cachedSummary?.thumbnailURL
                ?? pages.first(where: { $0.index == 0 })?.previewURL,
            category: storedSummary?.category ?? cachedSummary?.category,
            pageCount: storedSummary?.pageCount ?? cachedSummary?.pageCount ?? (pages.isEmpty ? nil : pages.count),
            postedAt: storedSummary?.postedAt ?? cachedSummary?.postedAt,
            rating: dynamic?.rating ?? storedSummary?.rating ?? cachedSummary?.rating,
            ratingCount: dynamic?.ratingCount ?? storedSummary?.ratingCount ?? cachedSummary?.ratingCount,
            favoriteCategory: dynamic?.favoriteCategory ?? storedSummary?.favoriteCategory ?? cachedSummary?.favoriteCategory,
            uploader: storedSummary?.uploader ?? cachedSummary?.uploader,
            tags: tags,
            metadataCompleteness: storedSummary?.metadataCompleteness ?? cachedSummary?.metadataCompleteness
        )
        return GalleryDetail(
            summary: summary,
            pages: pages,
            tags: tags,
            comments: dynamic?.comments.map(\.galleryComment) ?? [],
            descriptionText: cachedDetail?.descriptionText,
            externalURL: cachedDetail?.externalURL
                ?? URL(string: "https://\(site.host)/g/\(key.gid)/\(key.token)/"),
            apiUID: nil,
            apiKey: nil,
            favoriteCount: dynamic?.favoriteCount,
            favoriteName: dynamic?.favoriteName,
            ratingCount: dynamic?.ratingCount ?? summary.ratingCount,
            language: cachedDetail?.language,
            fileSize: cachedDetail?.fileSize,
            torrentURL: cachedDetail?.torrentURL,
            torrentCount: cachedDetail?.torrentCount,
            archiveURL: cachedDetail?.archiveURL
        )
    }

    /// Returns local-gallery summaries and fills only missing list metadata
    /// through the batched gdata endpoint. Detail-only fields are left alone.
    func localGallerySummaries(for keys: Set<GalleryKey>) async -> [GallerySummary] {
        guard keys.isEmpty == false else { return [] }
        let stored = (try? await persistence.gallerySyncSummaries(for: keys)) ?? []
        var summariesByKey = Dictionary(
            stored.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Older persisted records may have marked a missing date as
        // `.loadedEmpty` before gdata backfilling existed. The value itself is
        // the compatibility signal here, so those records are retried too.
        let missingPostedAt = keys.filter { summariesByKey[$0]?.postedAt == nil }
            .sorted { $0.id < $1.id }
        guard missingPostedAt.isEmpty == false else {
            return stored
        }

        guard let fetched = try? await api.gallerySummaries(for: missingPostedAt, site: site) else {
            return stored
        }
        var changed: [GallerySummary] = []
        for fetchedSummary in fetched where missingPostedAt.contains(fetchedSummary.key) {
            let completed = fetchedMetadataSummary(fetchedSummary)
            if let existing = summariesByKey[completed.key] {
                let mergedStable = GallerySnapshotMerger.merge(
                    existing: StableGalleryMetadataSnapshot(summary: existing, sourceSite: site),
                    incoming: StableGalleryMetadataSnapshot(summary: completed, sourceSite: site)
                )
                var merged = mergedStable.summary
                merged.rating = completed.rating ?? existing.rating
                merged.ratingCount = completed.ratingCount ?? existing.ratingCount
                merged.favoriteCategory = completed.favoriteCategory ?? existing.favoriteCategory
                summariesByKey[merged.key] = merged
                changed.append(merged)
            } else {
                summariesByKey[completed.key] = completed
                changed.append(completed)
            }
        }
        if changed.isEmpty == false {
            try? await persistence.upsert(changed, site: site)
            await downloads.mergeMetadata(changed)
        }
        return keys.compactMap { summariesByKey[$0] }
    }

    func prepareTagTranslations() async {
        await tagTranslationLoadTask?.value
    }

    func cachedDetail(for key: GalleryKey) async -> GalleryDetail? {
        if let stored = try? await persistence.stableSnapshot(for: key) {
            return stored.detail()
        }
        guard let migrated = await galleryCache.stableSnapshot(for: key, site: site) else { return nil }
        try? await persistence.upsertStableSnapshot(migrated)
        return migrated.detail()
    }

    private func migrateLegacyGalleryCache() async {
        let snapshots = await galleryCache.legacyStableSnapshots()
        for snapshot in snapshots {
            try? await persistence.upsertStableSnapshot(snapshot)
        }
    }

    func cacheDetail(_ detail: GalleryDetail, generation: UInt64? = nil) async {
        let snapshot = StableGalleryMetadataSnapshot(detail: detail, sourceSite: site)
        try? await persistence.upsertStableSnapshot(snapshot)
        await galleryCache.save(snapshot, for: detail.summary.key, site: site, generation: generation)
    }

    func galleryCacheGeneration() async -> UInt64 {
        await galleryCache.currentGeneration()
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

    func galleryImageData(for image: GalleryPageImage, resolution: ImageResolution = .preview) async throws -> Data {
        let api = self.api
        let data = try await galleryCache.imageData(for: image, resolution: resolution) {
            try await api.imageData(for: image, resolution: resolution)
        }
        if let localPath = await galleryCache.imageCachePath(for: image, resolution: resolution) {
            try? await persistence.recordImageIndex(
                key: image.galleryKey,
                site: site,
                kind: "preview",
                pageIndex: image.index,
                originalURL: image.originImageURL ?? image.imageURL,
                localPath: localPath,
                byteCount: Int64(data.count)
            )
        }
        return data
    }

    func refreshGalleryCacheUsage() async {
        galleryCacheByteCount = await galleryCache.usage().byteCount
    }

    func clearGalleryCache() async {
        try? await persistence.clearOrdinaryCache()
        await galleryCache.removeAll()
        try? await persistence.clearLibraryState()
        historyGalleries = []
        favoriteGalleries = []
        await refreshGalleryCacheUsage()
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
            throw EHError.parsingFailed(String(localized: "媒体数据无效"))
        }
        try await PhotoLibrarySaver.save(data, kind: mediaKind)
        #else
        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw EHError.storageFailed(String(localized: "找不到可写入的下载目录"))
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

    func comments(for key: GalleryKey) async throws -> [GalleryComment] {
        if let dynamic = try? await persistence.downloadedDynamicSnapshot(for: key),
           dynamic.completeness.comments.isLoaded {
            return dynamic.comments.map(\.galleryComment)
        }
        return try await api.comments(for: key, site: site)
    }

    func submitComment(for key: GalleryKey, body: String) async -> [GalleryComment]? {
        do {
            return try await api.submitComment(for: key, site: site, body: body, editing: nil)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func submitComment(for detail: GalleryDetail, body: String) async -> [GalleryComment]? {
        await submitComment(for: detail.summary.key, body: body)
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
        let hasImportMarker = defaults.string(forKey: "tagTranslationImportLocale") == Self.tagTranslationLocale
        let hasReferenceTranslations = ((try? await persistence.tagTranslations(locale: Self.tagTranslationLocale)) ?? [:]).isEmpty == false
        guard hasImportMarker == false || hasReferenceTranslations == false else { return }
        guard let entries = try? await tagSuggestionProvider.allEntries() else { return }
        let pairs = entries.compactMap { entry -> (tag: String, localizedText: String)? in
            guard let text = entry.localizedText, text.isEmpty == false else { return nil }
            return (entry.rawKey ?? entry.english, text)
        }
        guard pairs.isEmpty == false else { return }
        do {
            try await persistence.saveTagTranslations(pairs, locale: Self.tagTranslationLocale)
        } catch {
            return
        }
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
        let stable = StableGalleryMetadataSnapshot(detail: detail, sourceSite: site)
        let dynamic = DownloadedGalleryDynamicSnapshot(detail: detail)
        try? await persistence.promoteToDownloadedGallery(stable: stable, dynamic: dynamic)
        await downloads.enqueue(
            key: detail.summary.key,
            title: detail.summary.title,
            japaneseTitle: detail.summary.japaneseTitle,
            tags: detail.summary.tags,
            pages: detail.pages
        )
    }

    /// A synced gallery initially has no page descriptors. Resolve those only
    /// when the user chooses to download it, rather than making import depend
    /// on the network.
    func resumeDownload(_ key: GalleryKey) async {
        guard let job = await downloads.job(for: key) else { return }
        if job.pages.isEmpty {
            guard await hydrateSyncedDownload(job) else { return }
        }
        await downloads.resume(key)
    }

    /// Deletes every downloaded page and restarts the job from the beginning.
    func redownloadDownload(_ key: GalleryKey) async {
        guard let job = await downloads.job(for: key) else { return }
        if job.pages.isEmpty {
            guard await hydrateSyncedDownload(job) else { return }
        }
        if case let .failed(message) = await downloads.redownload(key) {
            errorMessage = message
        }
    }

    func startAllDownloads() async {
        let jobs = await downloads.snapshot()
        for job in jobs where [.paused, .failed, .authenticationRequired, .rateLimited, .bandwidthLimited].contains(job.state) {
            await resumeDownload(job.key)
        }
    }

    func downloadJob(for key: GalleryKey) async -> DownloadJob? {
        await downloads.job(for: key)
    }

    func restoreDownloads(
        from archiveURL: URL,
        progress: ((Int, Int) -> Void)? = nil
    ) async -> DownloadRestoreOutcome {
        guard isMigrating == false else {
            return DownloadRestoreOutcome(message: String(localized: "已有导入或导出任务正在进行。"))
        }
        guard isRestoringDownloads == false else {
            return DownloadRestoreOutcome(message: String(localized: "已有恢复任务正在进行。"))
        }
        isRestoringDownloads = true
        downloadRestoreStatus = String(localized: "正在检查备份压缩包…")
        let restoreSite = site
        defer {
            isRestoringDownloads = false
            downloadRestoreStatus = ""
        }

        do {
            let inspection = try await LegacyDownloadArchive.inspect(archiveURL)
            let candidates = inspection.candidates
            guard candidates.isEmpty == false else {
                let message = inspection.invalidItemCount > 0
                    ? String(localized: "没有找到可恢复的下载项；发现 \(inspection.invalidItemCount) 个无效目录。")
                    : String(localized: "没有在压缩包的 download 目录中找到可恢复的下载项。")
                return DownloadRestoreOutcome(
                    candidateCount: 0,
                    invalidItemCount: inspection.invalidItemCount,
                    message: message
                )
            }

            let existingJobs = Dictionary(uniqueKeysWithValues: await downloads.snapshot().map { ($0.key, $0) })
            let storedSummaries = try await persistence.gallerySyncSummaries(
                for: Set(candidates.map(\.key))
            )
            var existingLocalIndexes: [GalleryKey: Set<Int>] = [:]
            for candidate in candidates {
                let pageIndexes = Array(0..<candidate.declaredPageCount)
                existingLocalIndexes[candidate.key] = await downloadFiles.readablePageIndexes(
                    for: candidate.key,
                    pageIndexes: pageIndexes
                )
            }

            let archiveSummaries = candidates.map { candidate in
                let transferred = candidate.transferRecord?.stable.summary
                return GallerySummary(
                    key: candidate.key,
                    title: transferred?.title
                        ?? candidate.title
                        ?? existingJobs[candidate.key]?.title
                        ?? fallbackDownloadTitle(for: candidate),
                    japaneseTitle: transferred?.japaneseTitle
                        ?? candidate.japaneseTitle
                        ?? existingJobs[candidate.key]?.japaneseTitle,
                    pageCount: candidate.declaredPageCount,
                    tags: transferred?.tags
                        ?? candidate.tags
                        ?? existingJobs[candidate.key]?.tags
                        ?? [],
                    metadataCompleteness: candidate.transferRecord?.stable.completeness
                        ?? candidate.metadataCompleteness
                )
            }

            downloadRestoreStatus = String(localized: "正在获取画廊信息…")
            let resolution = try await resolveTransferMetadata(
                archiveSummaries,
                existing: storedSummaries
            ) { [weak self] completed, total in
                guard let self else { return }
                self.downloadRestoreStatus = total > 0
                    ? String(localized: "正在补全画廊信息 \(completed)/\(total)…")
                    : String(localized: "画廊信息已完备")
            }
            let summaryByKey = resolution.summariesByKey
            for candidate in candidates {
                guard let transfer = candidate.transferRecord else { continue }
                let refreshedStable: StableGalleryMetadataSnapshot
                if let summary = summaryByKey[candidate.key] {
                    refreshedStable = GallerySnapshotMerger.merge(
                        existing: transfer.stable,
                        incoming: StableGalleryMetadataSnapshot(summary: summary, sourceSite: restoreSite)
                    )
                } else {
                    refreshedStable = transfer.stable
                }
                try await persistence.promoteToDownloadedGallery(
                    stable: refreshedStable,
                    dynamic: transfer.dynamic
                )
            }

            var importCandidates: [LegacyDownloadCandidate] = []
            var skippedDuplicateItemCount = 0
            for candidate in candidates {
                let expectedPages = Set(0..<candidate.declaredPageCount)
                if existingJobs[candidate.key] != nil,
                   expectedPages.isSubset(of: existingLocalIndexes[candidate.key] ?? []),
                   summaryByKey[candidate.key]?.metadataCompleteness?.isSummaryComplete == true {
                    skippedDuplicateItemCount += 1
                } else {
                    importCandidates.append(candidate)
                }
            }

            var skippedDuplicatePageCount = 0
            var countedSkippedPageKeys = Set<String>()
            for candidate in candidates {
                let localIndexes = existingLocalIndexes[candidate.key] ?? []
                for image in candidate.images
                where (0..<candidate.declaredPageCount).contains(image.pageIndex)
                    && localIndexes.contains(image.pageIndex) {
                    let pageKey = Self.restorePageKey(key: candidate.key, pageIndex: image.pageIndex)
                    if countedSkippedPageKeys.insert(pageKey).inserted {
                        skippedDuplicatePageCount += 1
                    }
                }
            }

            guard importCandidates.isEmpty == false else {
                await downloads.mergeMetadata(Array(summaryByKey.values))
                progress?(0, 0)
                return DownloadRestoreOutcome(
                    candidateCount: candidates.count,
                    skippedDuplicateItemCount: skippedDuplicateItemCount,
                    skippedDuplicatePageCount: skippedDuplicatePageCount,
                    invalidItemCount: inspection.invalidItemCount,
                    incompleteMetadataCount: resolution.incompleteCount,
                    message: Self.restoreOutcomeMessage(
                        importedItemCount: 0,
                        mergedItemCount: 0,
                        skippedDuplicateItemCount: skippedDuplicateItemCount,
                        skippedDuplicatePageCount: skippedDuplicatePageCount,
                        failedPageCount: 0,
                        invalidItemCount: inspection.invalidItemCount,
                        incompleteMetadataCount: resolution.incompleteCount
                    )
                )
            }
            progress?(0, importCandidates.count)

            var selectedPageKeys = Set<String>()
            let selections = importCandidates.flatMap { candidate -> [LegacyDownloadPageSelection] in
                let localIndexes = existingLocalIndexes[candidate.key] ?? []
                return candidate.images.compactMap { image in
                    guard (0..<candidate.declaredPageCount).contains(image.pageIndex) else { return nil }
                    guard localIndexes.contains(image.pageIndex) == false else { return nil }
                    let pageKey = Self.restorePageKey(key: candidate.key, pageIndex: image.pageIndex)
                    guard selectedPageKeys.insert(pageKey).inserted else { return nil }
                    return LegacyDownloadPageSelection(
                        archivePath: image.archivePath,
                        key: candidate.key,
                        pageIndex: image.pageIndex
                    )
                }
            }

            downloadRestoreStatus = String(localized: "正在解压下载图片…")
            let extraction = try await LegacyDownloadArchive.extractPages(
                from: archiveURL,
                selections: selections
            )
            defer { try? FileManager.default.removeItem(at: extraction.temporaryDirectory) }

            var importedIndexes = existingLocalIndexes
            var importedPageCount = 0
            var failedPageCount = extraction.failedPageCount
            for (offset, page) in extraction.pages.enumerated() {
                try Task.checkCancellation()
                downloadRestoreStatus = String(localized: "正在导入图片 \(offset + 1)/\(extraction.pages.count)…")
                do {
                    _ = try await downloadFiles.importFile(
                        at: page.fileURL,
                        for: page.key,
                        pageIndex: page.pageIndex
                    )
                    importedIndexes[page.key, default: []].insert(page.pageIndex)
                    importedPageCount += 1
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failedPageCount += 1
                }
            }

            var restoredJobs: [DownloadJob] = []
            restoredJobs.reserveCapacity(importCandidates.count)
            for (offset, candidate) in importCandidates.enumerated() {
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
                    downloadRestoreStatus = String(localized: "正在准备缺失页面 \(offset + 1)/\(importCandidates.count)…")
                    let missingIndexes = expected.subtracting(imported)
                    if missingIndexes.isSubset(of: legacyPages.resumableIndexes) == false {
                        state = .failed
                        itemError = String(localized: "已恢复 \(imported.count)/\(expected.count) 页，但部分缺页没有可用的页面 token")
                    } else {
                        itemError = String(localized: "已恢复 \(imported.count)/\(expected.count) 页，可继续下载缺失页面")
                    }
                }

                var job = DownloadJob(
                    key: candidate.key,
                    title: summaryByKey[candidate.key]?.title
                        ?? existingJobs[candidate.key]?.title
                        ?? fallbackDownloadTitle(for: candidate),
                    japaneseTitle: summaryByKey[candidate.key]?.japaneseTitle
                        ?? existingJobs[candidate.key]?.japaneseTitle,
                    tags: summaryByKey[candidate.key]?.tags
                        ?? existingJobs[candidate.key]?.tags
                        ?? [],
                    pages: pages,
                    label: existingJobs[candidate.key]?.label,
                    addedAt: existingJobs[candidate.key]?.addedAt ?? Date()
                )
                job.completedPageIndexes = imported
                job.state = state
                job.errorMessage = itemError
                restoredJobs.append(job)
                progress?(offset + 1, importCandidates.count)
            }
            await downloads.mergeRestored(restoredJobs)
            await downloads.mergeMetadata(Array(summaryByKey.values))

            let mergedItemCount = restoredJobs.filter { existingJobs[$0.key] != nil }.count
            let importedItemCount = restoredJobs.count - mergedItemCount
            return DownloadRestoreOutcome(
                candidateCount: candidates.count,
                importedItemCount: importedItemCount,
                mergedItemCount: mergedItemCount,
                skippedDuplicateItemCount: skippedDuplicateItemCount,
                importedPageCount: importedPageCount,
                skippedDuplicatePageCount: skippedDuplicatePageCount,
                failedPageCount: failedPageCount,
                invalidItemCount: inspection.invalidItemCount,
                incompleteMetadataCount: resolution.incompleteCount,
                message: Self.restoreOutcomeMessage(
                    importedItemCount: importedItemCount,
                    mergedItemCount: mergedItemCount,
                    skippedDuplicateItemCount: skippedDuplicateItemCount,
                    skippedDuplicatePageCount: skippedDuplicatePageCount,
                    failedPageCount: failedPageCount,
                    invalidItemCount: inspection.invalidItemCount,
                    incompleteMetadataCount: resolution.incompleteCount
                )
            )
        } catch is CancellationError {
            return DownloadRestoreOutcome(message: String(localized: "已取消恢复下载项。"))
        } catch {
            return DownloadRestoreOutcome(message: String(localized: "恢复下载项失败：\(error.localizedDescription)"))
        }
    }

    nonisolated private static func restorePageKey(key: GalleryKey, pageIndex: Int) -> String {
        "\(key.gid)|\(key.token)|\(pageIndex)"
    }

    nonisolated private static func restoreOutcomeMessage(
        importedItemCount: Int,
        mergedItemCount: Int,
        skippedDuplicateItemCount: Int,
        skippedDuplicatePageCount: Int,
        failedPageCount: Int,
        invalidItemCount: Int,
        incompleteMetadataCount: Int
    ) -> String {
        var parts = [
            String(localized: "已导入 \(importedItemCount) 项"),
            String(localized: "合并 \(mergedItemCount) 项")
        ]
        if skippedDuplicateItemCount > 0 {
            parts.append(String(localized: "跳过重复项 \(skippedDuplicateItemCount) 项"))
        }
        if skippedDuplicatePageCount > 0 {
            parts.append(String(localized: "跳过已有页面 \(skippedDuplicatePageCount) 页"))
        }
        if failedPageCount > 0 {
            parts.append(String(localized: "图片失败 \(failedPageCount) 页"))
        }
        if invalidItemCount > 0 {
            parts.append(String(localized: "无效目录 \(invalidItemCount) 个"))
        }
        if incompleteMetadataCount > 0 {
            parts.append(String(localized: "待联网补全信息 \(incompleteMetadataCount) 个"))
        }
        return parts.joined(separator: "，") + "。"
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
                tags: item.tags,
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
                job.errorMessage = String(localized: "部分下载文件缺失或无效，请继续下载")
            } else if item.inFlightPageIndexes.isEmpty == false {
                job.state = .paused
                job.errorMessage = String(localized: "后台下载任务恢复中")
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
            tags: item.tags,
            pages: item.pages,
            addedAt: item.createdAt
        )
        job.completedPageIndexes = item.completedPageIndexes
        job.state = normalizedRestoredState(item.stateRaw)
        job.label = item.label
        job.errorMessage = item.errorMessage
        if item.inFlightPageIndexes.isEmpty == false {
            job.state = .paused
            job.errorMessage = String(localized: "后台下载任务恢复中")
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

        if BackupFileFormat.isGallerySyncURL(url) {
            stageIncomingGallerySync(url)
            return
        }

        if BackupFileFormat.isDownloadArchiveURL(url) {
            stageIncomingArchive(url)
            return
        }

        if let key = Self.galleryKey(from: url) {
            selectedRoute = .gallery(key)
        }
    }

    func confirmIncomingArchive() async {
        guard let pending = pendingIncomingArchive else { return }
        await confirmIncomingArchive(pending)
    }

    func discardIncomingArchive() {
        guard let pending = pendingIncomingArchive else { return }
        try? FileManager.default.removeItem(at: pending.stagedURL.deletingLastPathComponent())
        pendingIncomingArchive = nil
    }

    func stageGallerySyncImport(from url: URL) {
        stageIncomingGallerySync(url)
    }

    func confirmIncomingGallerySync() async {
        guard let pending = pendingIncomingGallerySync else { return }
        await confirmIncomingGallerySync(pending)
    }

    func discardIncomingGallerySync() {
        guard let pending = pendingIncomingGallerySync else { return }
        try? FileManager.default.removeItem(at: pending.stagedURL.deletingLastPathComponent())
        pendingIncomingGallerySync = nil
    }

    func discardPendingSharedFile(_ url: URL) {
        if pendingSharedFileURL == url {
            pendingSharedFileURL = nil
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// 导入完成后删除系统留在应用临时目录内的文件副本（iOS 文件选择器与
    /// 「打开方式」会把文件复制到 tmp/Inbox）。macOS 的选择器返回原文件的
    /// 安全作用域 URL，位于临时目录之外，不会被误删。
    func discardTemporaryImportCopy(_ url: URL) {
        guard Self.isInsideTemporaryDirectory(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated private static func isInsideTemporaryDirectory(_ url: URL) -> Bool {
        let temporaryPath = FileManager.default.temporaryDirectory.path
        let normalized = temporaryPath.hasSuffix("/") ? temporaryPath : temporaryPath + "/"
        return url.standardizedFileURL.path.hasPrefix(normalized)
    }

    private func stageIncomingArchive(_ url: URL) {
        incomingStagingGeneration += 1
        let generation = incomingStagingGeneration
        let previousDirectoryToRemove: URL?
        if let previous = pendingIncomingArchive,
           isMigrating == false,
           isRestoringDownloads == false {
            previousDirectoryToRemove = previous.stagedURL.deletingLastPathComponent()
        } else {
            previousDirectoryToRemove = nil
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.copyIncomingFileToTemporaryDirectory(
                    url,
                    previousDirectoryToRemove: previousDirectoryToRemove
                )
            }.value

            guard generation == incomingStagingGeneration else {
                if case .success(let staged) = outcome {
                    Task.detached(priority: .utility) {
                        try? FileManager.default.removeItem(at: staged.directory)
                    }
                }
                return
            }

            switch outcome {
            case .success(let staged):
                self.importResultMessage = nil
                self.errorMessage = nil
                let pending = PendingIncomingArchive(
                    stagedURL: staged.stagedURL,
                    fileName: staged.fileName
                )
                self.pendingIncomingArchive = pending
            case .failure(let message):
                self.errorMessage = message
            }
        }
    }

    private func stageIncomingGallerySync(_ url: URL) {
        incomingStagingGeneration += 1
        let generation = incomingStagingGeneration
        let previousDirectoryToRemove: URL?
        if isMigrating == false, isRestoringDownloads == false {
            previousDirectoryToRemove = pendingIncomingGallerySync?.stagedURL.deletingLastPathComponent()
                ?? pendingIncomingArchive?.stagedURL.deletingLastPathComponent()
        } else {
            previousDirectoryToRemove = nil
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.copyIncomingFileToTemporaryDirectory(
                    url,
                    previousDirectoryToRemove: previousDirectoryToRemove,
                    maximumBytes: GallerySyncArchive.maximumArchiveBytes
                )
            }.value

            guard generation == incomingStagingGeneration else {
                if case .success(let staged) = outcome {
                    Task.detached(priority: .utility) {
                        try? FileManager.default.removeItem(at: staged.directory)
                    }
                }
                return
            }

            switch outcome {
            case .success(let staged):
                self.importResultMessage = nil
                self.errorMessage = nil
                self.pendingIncomingArchive = nil
                self.pendingIncomingGallerySync = PendingIncomingGallerySync(
                    stagedURL: staged.stagedURL,
                    fileName: staged.fileName
                )
            case .failure(let message):
                self.errorMessage = message
            }
        }
    }

    nonisolated private static func copyIncomingFileToTemporaryDirectory(
        _ url: URL,
        previousDirectoryToRemove: URL?,
        maximumBytes: Int64? = nil
    ) -> IncomingStagingOutcome {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            if let maximumBytes,
               let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               Int64(fileSize) > maximumBytes {
                throw GallerySyncArchiveError.archiveTooLarge
            }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("EhViewer-Incoming-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let fileName = url.lastPathComponent.isEmpty ? "EhViewer-Incoming" : url.lastPathComponent
            let stagedURL = directory.appendingPathComponent(fileName)
            do {
                try FileManager.default.copyItem(at: url, to: stagedURL)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }

            // iOS 文件选择器/「打开方式」会在 tmp/Inbox 留下源文件副本，
            // 复制到暂存目录后即可删除，避免导入后残留多份数据。
            if Self.isInsideTemporaryDirectory(url) {
                try? FileManager.default.removeItem(at: url)
            }

            if let previousDirectoryToRemove {
                try? FileManager.default.removeItem(at: previousDirectoryToRemove)
            }
            return .success(
                StagedIncomingFile(
                    directory: directory,
                    stagedURL: stagedURL,
                    fileName: fileName
                )
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func confirmIncomingArchive(_ pending: PendingIncomingArchive) async {
        guard pendingIncomingArchive?.id == pending.id else { return }
        guard isMigrating == false else {
            errorMessage = nil
            importResultMessage = String(localized: "已有导入或导出任务进行中，请稍后重试。")
            return
        }
        guard isRestoringDownloads == false else {
            errorMessage = nil
            importResultMessage = String(localized: "已有恢复任务正在进行，请稍后重试。")
            return
        }

        let directory = pending.stagedURL.deletingLastPathComponent()
        let resultMessage = await restoreDownloads(from: pending.stagedURL).message

        if pendingIncomingArchive?.id == pending.id {
            pendingIncomingArchive = nil
        }
        try? FileManager.default.removeItem(at: directory)
        errorMessage = nil
        importResultMessage = resultMessage
    }

    func confirmIncomingGallerySync(_ pending: PendingIncomingGallerySync) async {
        guard pendingIncomingGallerySync?.id == pending.id else { return }
        let directory = pending.stagedURL.deletingLastPathComponent()
        defer {
            if pendingIncomingGallerySync?.id == pending.id {
                pendingIncomingGallerySync = nil
            }
            try? FileManager.default.removeItem(at: directory)
        }

        guard isMigrating == false, isRestoringDownloads == false else {
            errorMessage = nil
            importResultMessage = String(localized: "已有导入或导出任务进行中，请稍后重试。")
            return
        }

        guard let outcome = await importGallerySync(from: pending.stagedURL) else { return }
        errorMessage = nil
        importResultMessage = Self.gallerySyncOutcomeMessage(outcome)
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
        defaults.set(downloadLayoutMode.rawValue, forKey: "downloadLayoutMode")
    }

    func exportGallerySync(keys: Set<GalleryKey>? = nil) async -> URL? {
        guard beginMigration(status: String(localized: "正在准备画廊同步包…")) else { return nil }
        defer { finishMigration() }

        let archiveName = if let keys {
            "EhViewer-Galleries-\(keys.count)items-\(Self.timestampForExportFilename()).ehgallery"
        } else {
            "EhViewer-Galleries-\(Self.timestampForExportFilename()).ehgallery"
        }
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(archiveName)
        var archiveReady = false
        defer {
            // 导出失败或取消时清理未完成的压缩包，避免残留占用存储。
            if archiveReady == false {
                try? FileManager.default.removeItem(at: archiveURL)
            }
        }

        do {
            setMigrationProgress(status: String(localized: "正在读取下载列表…"), fraction: 0.15)
            let jobs = await downloads.snapshot()
            guard jobs.isEmpty == false else {
                errorMessage = String(localized: "下载列表中没有可导出的画廊。")
                return nil
            }

            let selectedJobs = if let keys {
                jobs.filter { keys.contains($0.key) }
            } else {
                jobs
            }
            guard selectedJobs.isEmpty == false else {
                errorMessage = keys == nil
                    ? String(localized: "下载列表中没有可导出的画廊。")
                    : String(localized: "所选项目没有可导出的画廊。")
                return nil
            }

            let storedSummaries = try await persistence.gallerySyncSummaries(for: Set(selectedJobs.map(\.key)))
            let summariesByKey = try await transferSummaries(
                for: Set(selectedJobs.map(\.key)),
                stored: storedSummaries
            )
            for job in selectedJobs {
                let summary = summariesByKey[job.key] ?? GallerySummary(
                    key: job.key,
                    title: job.title,
                    japaneseTitle: job.japaneseTitle,
                    pageCount: job.pages.isEmpty ? nil : job.pages.count,
                    tags: job.tags
                )
                try await persistence.upsertStableSnapshot(
                    StableGalleryMetadataSnapshot(summary: summary, sourceSite: site),
                    retainForDownload: true
                )
            }
            let records = try await persistence.galleryTransferRecords(
                for: Set(selectedJobs.map(\.key))
            )

            setMigrationProgress(status: String(localized: "正在创建画廊同步包…"), fraction: 0.45)
            let snapshot = GallerySyncSnapshot(records: records)
            try await Task.detached(priority: .userInitiated) {
                try GallerySyncArchive.export(snapshot, to: archiveURL)
            }.value
            setMigrationProgress(status: String(localized: "画廊同步包已准备完成"), fraction: 1)
            archiveReady = true
            replacePendingSharedFile(with: archiveURL)
            return archiveURL
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Refreshes transferable metadata for every item in the download list.
    /// Media files and download progress are not touched; only the gallery
    /// cache and the in-memory download metadata are updated. This intentionally
    /// uses only the site's batched gdata summaries; full detail and preview
    /// pagination remain user-triggered operations.
    func refreshDownloadedGalleryMetadata() async {
        guard isRestoringDownloads == false else {
            errorMessage = String(localized: "正在恢复下载内容，请稍后再更新画廊信息。")
            return
        }
        guard beginMigration(status: String(localized: "正在准备更新已下载画廊信息…")) else { return }
        defer { finishMigration() }

        do {
            let jobs = await downloads.snapshot()
            guard jobs.isEmpty == false else {
                importResultMessage = String(localized: "下载列表中没有需要更新的画廊。")
                return
            }

            let keys = jobs.map(\.key)
            let stored = try await persistence.gallerySyncSummaries(for: Set(keys))
            var summariesByKey = Dictionary(
                stored.map { ($0.key, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for job in jobs where summariesByKey[job.key] == nil {
                summariesByKey[job.key] = GallerySummary(
                    key: job.key,
                    title: job.title,
                    japaneseTitle: job.japaneseTitle,
                    pageCount: job.pages.isEmpty ? nil : job.pages.count,
                    tags: job.tags
                )
            }

            var refreshedKeys = Set<GalleryKey>()
            let batchSize = 25
            for start in stride(from: 0, to: keys.count, by: batchSize) {
                try Task.checkCancellation()
                let end = min(start + batchSize, keys.count)
                let batchKeys = Array(keys[start..<end])
                let batchKeySet = Set(batchKeys)
                setMigrationProgress(
                    status: String(format: String(localized: "正在获取画廊信息 %d/%d…"), end, keys.count),
                    completed: start,
                    total: keys.count,
                    fraction: 0.05 + 0.9 * Double(start) / Double(keys.count)
                )
                let fetched: [GallerySummary]
                do {
                    fetched = try await api.gallerySummaries(for: batchKeys, site: site)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A failed batch is a partial result, not a reason to stop
                    // updating unrelated downloaded galleries.
                    continue
                }
                var merged: [GallerySummary] = []
                merged.reserveCapacity(fetched.count)
                for fetchedSummary in fetched where batchKeySet.contains(fetchedSummary.key) {
                    let completed = fetchedMetadataSummary(fetchedSummary)
                    if let existing = summariesByKey[completed.key] {
                        let mergedStable = GallerySnapshotMerger.merge(
                            existing: StableGalleryMetadataSnapshot(summary: existing, sourceSite: site),
                            incoming: StableGalleryMetadataSnapshot(summary: completed, sourceSite: site)
                        )
                        var mergedSummary = mergedStable.summary
                        // gdata exposes the average rating, but not the other
                        // account-scoped fields. Preserve those fields unless
                        // this response actually supplied a replacement.
                        mergedSummary.rating = completed.rating ?? existing.rating
                        mergedSummary.ratingCount = completed.ratingCount ?? existing.ratingCount
                        mergedSummary.favoriteCategory = completed.favoriteCategory ?? existing.favoriteCategory
                        summariesByKey[mergedSummary.key] = mergedSummary
                        merged.append(mergedSummary)
                    } else {
                        summariesByKey[completed.key] = completed
                        merged.append(completed)
                    }
                    refreshedKeys.insert(completed.key)
                }
                if merged.isEmpty == false {
                    try await persistence.upsert(merged, site: site)
                    await downloads.mergeMetadata(merged)
                    for summary in merged {
                        var completeness = GalleryMetadataCompleteness()
                        // gdata only supplies the average rating. Leave all
                        // other dynamic fields not loaded so an existing
                        // downloaded snapshot (especially comments) survives
                        // this stable-metadata refresh.
                        completeness.rating = summary.rating == nil ? .notLoaded : .loadedWithValue
                        try? await persistence.saveDownloadedDynamicSnapshot(
                            DownloadedGalleryDynamicSnapshot(
                                key: summary.key,
                                rating: summary.rating,
                                capturedAt: Date(),
                                completeness: completeness
                            )
                        )
                    }
                }
                setMigrationProgress(
                    status: String(format: String(localized: "已更新画廊信息 %d/%d…"), end, keys.count),
                    completed: end,
                    total: keys.count,
                    fraction: 0.05 + 0.9 * Double(end) / Double(keys.count)
                )
            }

            setMigrationProgress(
                status: String(localized: "已完成画廊信息更新"),
                completed: keys.count,
                total: keys.count,
                fraction: 1
            )
            let totalRefreshed = min(keys.count, refreshedKeys.count)
            importResultMessage = String(format: String(localized: "已更新 %d/%d 个下载项的画廊信息。"), totalRefreshed, keys.count)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importGallerySync(from archiveURL: URL) async -> GallerySyncImportResult? {
        guard beginMigration(status: String(localized: "正在读取画廊同步包…")) else { return nil }
        defer { finishMigration() }

        do {
            setMigrationProgress(status: String(localized: "正在验证画廊同步包…"), fraction: 0.2)
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try GallerySyncArchive.read(from: archiveURL)
            }.value
            let existing = try await persistence.gallerySyncSummaries(
                for: Set(snapshot.galleries.map(\.key))
            )
            setMigrationProgress(status: String(localized: "正在恢复画廊信息…"), fraction: 0.5)
            let resolution = try await resolveTransferMetadata(
                snapshot.galleries,
                existing: existing
            ) { [weak self] completed, total in
                guard let self else { return }
                let fraction = total > 0 ? Double(completed) / Double(total) : 1
                self.setMigrationProgress(
                    status: String(localized: "正在补全画廊信息 \(completed)/\(total)…"),
                    completed: completed,
                    total: total,
                    fraction: 0.5 + 0.25 * fraction
                )
            }
            let resolvedSummaries = Array(resolution.summariesByKey.values)
            let galleryOutcome = try await persistence.mergeGallerySyncSummaries(resolvedSummaries)
            let resolvedByKey = Dictionary(uniqueKeysWithValues: resolvedSummaries.map { ($0.key, $0) })
            for record in snapshot.records {
                let refreshedStable: StableGalleryMetadataSnapshot
                if let summary = resolvedByKey[record.stable.key] {
                    refreshedStable = GallerySnapshotMerger.merge(
                        existing: record.stable,
                        incoming: StableGalleryMetadataSnapshot(summary: summary, sourceSite: site)
                    )
                } else {
                    refreshedStable = record.stable
                }
                try await persistence.promoteToDownloadedGallery(
                    stable: refreshedStable,
                    dynamic: record.dynamic
                )
            }
            setMigrationProgress(status: String(localized: "正在加入下载列表…"), fraction: 0.8)
            await downloads.mergeMetadata(resolvedSummaries)
            let queuedDownloadCount = await queueMissingSyncedDownloads(resolvedSummaries)
            setMigrationProgress(status: String(localized: "画廊同步完成"), fraction: 1)
            return GallerySyncImportResult(
                galleryOutcome: galleryOutcome,
                queuedDownloadCount: queuedDownloadCount,
                incompleteMetadataCount: resolution.incompleteCount
            )
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func exportDownloadArchive(keys: Set<GalleryKey>? = nil) async -> URL? {
        guard beginMigration(status: String(localized: "正在准备下载包…")) else { return nil }
        defer { finishMigration() }

        let scopeName = keys.map { "\($0.count)items" } ?? "All"
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EhViewer-Downloads-\(scopeName)-\(Self.timestampForExportFilename()).eharchive")
        var archiveReady = false
        defer {
            // 导出失败或取消时清理未完成的压缩包，避免残留占用存储。
            if archiveReady == false {
                try? FileManager.default.removeItem(at: archiveURL)
            }
        }

        do {
            setMigrationProgress(status: String(localized: "正在读取下载任务…"), fraction: 0.05)
            let liveJobs = await downloads.snapshot()
            let persisted = (try? await persistence.downloadJobs()) ?? []
            let persistedJobs = persisted.map(makePersistedDownloadJob)
            var totalPageCounts = Dictionary(
                uniqueKeysWithValues: persisted.map { ($0.key, $0.totalPageCount) }
            )
            var jobsByKey = Dictionary(uniqueKeysWithValues: persistedJobs.map { ($0.key, $0) })
            for job in liveJobs {
                jobsByKey[job.key] = job
                totalPageCounts[job.key] = max(totalPageCounts[job.key] ?? 0, job.pages.count)
            }
            let jobs = jobsByKey.values.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            let selected = if let keys {
                jobs.filter { keys.contains($0.key) }
            } else {
                jobs
            }
            guard selected.isEmpty == false else {
                errorMessage = keys == nil
                    ? String(localized: "没有可导出的下载内容。")
                    : String(localized: "所选项目没有可导出的下载内容。")
                return nil
            }

            let storedSummaries = try await persistence.gallerySyncSummaries(for: Set(selected.map(\.key)))
            let summariesByKey = try await transferSummaries(
                for: Set(selected.map(\.key)),
                stored: storedSummaries
            )
            for item in selected {
                let summary = summariesByKey[item.key] ?? GallerySummary(
                    key: item.key,
                    title: item.title,
                    japaneseTitle: item.japaneseTitle,
                    pageCount: item.pages.isEmpty ? nil : item.pages.count,
                    tags: item.tags
                )
                try await persistence.upsertStableSnapshot(
                    StableGalleryMetadataSnapshot(summary: summary, sourceSite: site),
                    retainForDownload: true
                )
            }
            let transferRecords = (try? await persistence.galleryTransferRecords(
                for: Set(selected.map(\.key))
            )) ?? []
            let transferRecordByKey = Dictionary(uniqueKeysWithValues: transferRecords.map { ($0.stable.key, $0) })

            let items = selected.map { item in
                let pageTokens = Dictionary(uniqueKeysWithValues: item.pages.compactMap { page -> (Int, String)? in
                    guard let token = pageToken(from: page.pageURL) else { return nil }
                    return (page.index, token)
                })
                let highestPage = item.pages.map { $0.index + 1 }.max() ?? 0
                let summary = summariesByKey[item.key]
                return DownloadArchiveExportItem(
                    key: item.key,
                    title: summary?.title ?? item.title,
                    japaneseTitle: summary?.japaneseTitle ?? item.japaneseTitle,
                    tags: summary?.tags ?? item.tags,
                    metadataCompleteness: summary?.metadataCompleteness,
                    transferRecord: transferRecordByKey[item.key],
                    totalPageCount: max(totalPageCounts[item.key] ?? item.pages.count, highestPage),
                    pageTokens: pageTokens
                )
            }

            setMigrationProgress(status: String(localized: "正在创建下载包…"), fraction: 0.1)
            _ = try await DownloadArchiveExporter.export(
                items: items,
                files: downloadFiles,
                to: archiveURL
            ) { [weak self] progress in
                guard let self else { return }
                let archiveFraction = progress.fraction
                await self.setMigrationProgress(
                    status: progress.currentTitle.map { String(localized: "正在导出《\($0)》…") } ?? String(localized: "正在导出下载文件…"),
                    completed: progress.completedFiles,
                    total: progress.totalFiles,
                    fraction: 0.1 + archiveFraction * 0.85
                )
            }
            setMigrationProgress(status: String(localized: "下载包已准备完成"), fraction: 1)
            archiveReady = true
            replacePendingSharedFile(with: archiveURL)
            return archiveURL
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func replacePendingSharedFile(with url: URL) {
        if let previous = pendingSharedFileURL, previous != url {
            try? FileManager.default.removeItem(at: previous)
        }
        pendingSharedFileURL = url
    }

    private static func hasMetadataValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func normalizedMetadataSummary(_ summary: GallerySummary) -> GallerySummary {
        var normalized = summary
        let completeness = summary.metadataCompleteness ?? GalleryMetadataCompleteness()
        var normalizedCompleteness = completeness
        normalizedCompleteness.title = completeness.title.isLoaded
            ? (Self.hasMetadataValue(summary.title) ? .loadedWithValue : .loadedEmpty)
            : .notLoaded
        normalizedCompleteness.japaneseTitle = completeness.japaneseTitle.isLoaded
            ? (Self.hasMetadataValue(summary.japaneseTitle) ? .loadedWithValue : .loadedEmpty)
            : .notLoaded
        normalized.metadataCompleteness = normalizedCompleteness
        return normalized
    }

    /// A successful API response resolves the tag field even when the source
    /// legitimately returns an empty tag list. A title field is complete only
    /// when at least one actual title value was written.
    private func fetchedMetadataSummary(_ summary: GallerySummary) -> GallerySummary {
        var fetched = summary
        fetched.metadataCompleteness = GalleryMetadataCompleteness(
            title: Self.hasMetadataValue(summary.title) ? .loadedWithValue : .loadedEmpty,
            japaneseTitle: Self.hasMetadataValue(summary.japaneseTitle) ? .loadedWithValue : .loadedEmpty,
            authors: StableGalleryMetadataSnapshot.authors(from: summary.tags).isEmpty
                ? .loadedEmpty
                : .loadedWithValue,
            uploader: summary.uploader == nil ? .loadedEmpty : .loadedWithValue,
            tags: summary.tags.isEmpty ? .loadedEmpty : .loadedWithValue,
            category: summary.category == nil ? .loadedEmpty : .loadedWithValue,
            pageCount: summary.pageCount == nil ? .loadedEmpty : .loadedWithValue,
            postedAt: summary.postedAt == nil ? .loadedEmpty : .loadedWithValue,
            thumbnailURL: summary.thumbnailURL == nil ? .loadedEmpty : .loadedWithValue,
            rating: summary.rating == nil ? .loadedEmpty : .loadedWithValue
        )
        return fetched
    }

    /// Merges an incoming package summary without replacing a locally complete
    /// field with an incomplete package field.
    private func mergeMetadataSummary(
        _ incoming: GallerySummary,
        with existing: GallerySummary?
    ) -> GallerySummary {
        guard let existing else { return normalizedMetadataSummary(incoming) }

        let incomingStatus = incoming.metadataCompleteness ?? GalleryMetadataCompleteness()
        let existingStatus = existing.metadataCompleteness ?? GalleryMetadataCompleteness()
        var merged = incoming
        if incomingStatus.title.isLoaded == false, existingStatus.title.isLoaded {
            merged.title = existing.title
        }
        if incomingStatus.japaneseTitle.isLoaded == false, existingStatus.japaneseTitle.isLoaded {
            merged.japaneseTitle = existing.japaneseTitle
        }
        if incomingStatus.tags.isLoaded == false, existingStatus.tags.isLoaded {
            merged.tags = existing.tags
        }
        var mergedCompleteness = incomingStatus
        if incomingStatus.title.isLoaded == false { mergedCompleteness.title = existingStatus.title }
        if incomingStatus.japaneseTitle.isLoaded == false { mergedCompleteness.japaneseTitle = existingStatus.japaneseTitle }
        if incomingStatus.authors.isLoaded == false { mergedCompleteness.authors = existingStatus.authors }
        if incomingStatus.uploader.isLoaded == false { mergedCompleteness.uploader = existingStatus.uploader }
        if incomingStatus.tags.isLoaded == false { mergedCompleteness.tags = existingStatus.tags }
        if incomingStatus.category.isLoaded == false { mergedCompleteness.category = existingStatus.category }
        if incomingStatus.pageCount.isLoaded == false { mergedCompleteness.pageCount = existingStatus.pageCount }
        if incomingStatus.postedAt.isLoaded == false { mergedCompleteness.postedAt = existingStatus.postedAt }
        if incomingStatus.thumbnailURL.isLoaded == false { mergedCompleteness.thumbnailURL = existingStatus.thumbnailURL }
        if incomingStatus.rating.isLoaded == false { mergedCompleteness.rating = existingStatus.rating }
        if incomingStatus.ratingCount.isLoaded == false { mergedCompleteness.ratingCount = existingStatus.ratingCount }
        if incomingStatus.favorite.isLoaded == false { mergedCompleteness.favorite = existingStatus.favorite }
        if incomingStatus.comments.isLoaded == false { mergedCompleteness.comments = existingStatus.comments }
        if let existingPostedAt = existing.postedAt, incoming.postedAt == nil {
            merged.postedAt = existingPostedAt
            mergedCompleteness.postedAt = existingStatus.postedAt.isLoaded
                ? existingStatus.postedAt
                : .loadedWithValue
        }
        merged.metadataCompleteness = mergedCompleteness
        return normalizedMetadataSummary(merged)
    }

    private struct MetadataResolution: Sendable {
        let summariesByKey: [GalleryKey: GallerySummary]
        let incompleteCount: Int
    }

    /// Persists the package state before requesting missing fields, then
    /// persists every successful gallery response independently. This makes a
    /// cancelled or rate-limited import resumable without repeating completed
    /// metadata requests.
    private func resolveTransferMetadata(
        _ incoming: [GallerySummary],
        existing: [GallerySummary] = [],
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> MetadataResolution {
        let existingByKey = Dictionary(
            existing.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var summariesByKey: [GalleryKey: GallerySummary] = [:]
        for summary in incoming {
            summariesByKey[summary.key] = mergeMetadataSummary(summary, with: existingByKey[summary.key])
        }

        if summariesByKey.isEmpty == false {
            try await persistence.upsert(Array(summariesByKey.values))
        }

        var pendingKeys = summariesByKey.values
            .filter { $0.metadataCompleteness?.isSummaryComplete != true }
            .map(\.key)
            .sorted { $0.id < $1.id }
        progress?(0, pendingKeys.count)

        let requestSize = 25
        var completedCount = 0
        for start in stride(from: 0, to: pendingKeys.count, by: requestSize) {
            try Task.checkCancellation()
            let end = min(start + requestSize, pendingKeys.count)
            let batchKeys = Array(pendingKeys[start..<end])
            let fetched: [GallerySummary]
            do {
                fetched = try await api.gallerySummaries(for: batchKeys, site: site)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Keep this and all later keys incomplete. A subsequent import
                // resumes at this checkpoint instead of retrying earlier keys.
                break
            }

            let requestedKeys = Set(batchKeys)
            for summary in fetched where requestedKeys.contains(summary.key) {
                try Task.checkCancellation()
                let completed = fetchedMetadataSummary(summary)
                let merged = mergeMetadataSummary(completed, with: summariesByKey[summary.key])
                try await persistence.upsert([merged])
                summariesByKey[merged.key] = merged
                completedCount += 1
                progress?(completedCount, pendingKeys.count)
            }
        }

        pendingKeys = summariesByKey.values
            .filter { $0.metadataCompleteness?.isSummaryComplete != true }
            .map(\.key)
        return MetadataResolution(
            summariesByKey: summariesByKey,
            incompleteCount: pendingKeys.count
        )
    }

    /// Ensures exports carry complete title/tag metadata for older downloads
    /// that predate the local gallery cache. The API batches these requests in
    /// groups of 25; a failed refresh keeps the locally available metadata.
    private func transferSummaries(
        for keys: Set<GalleryKey>,
        stored: [GallerySummary]
    ) async throws -> [GalleryKey: GallerySummary] {
        var summariesByKey = Dictionary(
            stored.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let keysNeedingRefresh = keys.filter { key in
            guard let summary = summariesByKey[key] else { return true }
            return summary.metadataCompleteness?.isSummaryComplete != true
        }.sorted { $0.id < $1.id }
        guard keysNeedingRefresh.isEmpty == false else {
            return summariesByKey
        }

        let fetched: [GallerySummary]
        do {
            fetched = try await api.gallerySummaries(for: keysNeedingRefresh, site: site)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return summariesByKey
        }
        guard fetched.isEmpty == false else {
            return summariesByKey
        }

        var merged: [GallerySummary] = []
        merged.reserveCapacity(fetched.count)
        let requestedKeys = Set(keysNeedingRefresh)
        for fetchedSummary in fetched where requestedKeys.contains(fetchedSummary.key) {
            let completed = fetchedMetadataSummary(fetchedSummary)
            if let existing = summariesByKey[completed.key] {
                let resolved = mergeMetadataSummary(completed, with: existing)
                summariesByKey[resolved.key] = resolved
                merged.append(resolved)
            } else {
                summariesByKey[completed.key] = completed
                merged.append(completed)
            }
        }
        try? await persistence.upsert(merged)
        return summariesByKey
    }

    nonisolated private static func timestampForExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    /// 启动时清理上次会话遗留的导出/导入暂存临时文件（分享后未删除、
    /// 导入中断等场景）。只删除创建超过 1 小时的文件，避免误伤进行中的任务。
    nonisolated static func sweepStaleTemporaryFiles() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasPrefix("EhViewer-Downloads-")
                || name.hasPrefix("EhViewer-Galleries-")
                || name.hasPrefix("EhViewer-Incoming-") else { continue }
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            guard created < cutoff else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }

    private func queueMissingSyncedDownloads(_ summaries: [GallerySummary]) async -> Int {
        var seen = Set<GalleryKey>()
        let uniqueSummaries = summaries.filter { seen.insert($0.key).inserted }
        let existingDownloadKeys = Set(await downloads.snapshot().map(\.key))
        let missing = uniqueSummaries
            .filter { existingDownloadKeys.contains($0.key) == false }
            .sorted { $0.key.id < $1.key.id }
        guard missing.isEmpty == false else { return 0 }

        let jobs = missing.map { summary -> DownloadJob in
            var job = DownloadJob(
                key: summary.key,
                title: summary.title,
                japaneseTitle: summary.japaneseTitle,
                tags: summary.tags,
                pages: []
            )
            job.state = .paused
            job.errorMessage = String(localized: "已从画廊同步包加入；开始下载时将获取页面信息。")
            return job
        }
        await downloads.restore(jobs)
        return jobs.count
    }

    private func hydrateSyncedDownload(_ job: DownloadJob) async -> Bool {
        do {
            let detail = try await api.detail(for: job.key, site: site)
            guard detail.pages.isEmpty == false else {
                throw EHError.parsingFailed(String(localized: "画廊没有可下载的页面。"))
            }
            var hydrated = DownloadJob(
                key: job.key,
                title: job.title,
                japaneseTitle: job.japaneseTitle,
                tags: job.tags,
                pages: detail.pages,
                label: job.label,
                addedAt: job.addedAt
            )
            hydrated.state = .paused
            await downloads.mergeRestored([hydrated])
            return true
        } catch {
            errorMessage = String(localized: "无法准备《\(job.displayTitle(showJapaneseTitle: readingSettings.showJapaneseTitle))》下载：\(error.localizedDescription)")
            return false
        }
    }

    nonisolated private static func gallerySyncOutcomeMessage(_ result: GallerySyncImportResult) -> String {
        let outcome = result.galleryOutcome
        var parts = [String(localized: "已加入下载列表 \(result.queuedDownloadCount) 项")]
        if outcome.insertedCount > 0 {
            parts.append(String(localized: "新增画廊摘要 \(outcome.insertedCount) 个"))
        }
        if outcome.existingCount > 0 {
            parts.append(String(localized: "本地已有画廊 \(outcome.existingCount) 个"))
        }
        if outcome.duplicateInFileCount > 0 {
            parts.append(String(localized: "文件内重复 \(outcome.duplicateInFileCount) 个"))
        }
        if result.incompleteMetadataCount > 0 {
            parts.append(String(localized: "待联网补全信息 \(result.incompleteMetadataCount) 个"))
        }
        return parts.joined(separator: "，") + "。"
    }

    private func beginMigration(status: String) -> Bool {
        guard isMigrating == false, isRestoringDownloads == false else { return false }
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
